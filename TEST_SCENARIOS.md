# Helm LLM Scheduler Test Scenarios

Date: 2026-04-05

This document is the scheduler-focused test plan for `helm-llm-repo`. It covers:

- existing automated coverage in `tests/`
- Volcano deployment and runtime scenarios
- HAMi deployment and runtime scenarios
- `volcano-vgpu-device-plugin` integration scenarios
- actual GPU-node targets already referenced by repo docs and reports

## Repo Structure Snapshot

Charts currently in this repo:

- `charts/vllm-inference`
- `charts/sglang-inference`
- `charts/llamacpp-inference`
- `charts/volcano-scheduler` (skeleton only)
- `charts/hami-scheduler` (skeleton only)

Current scheduler-oriented tests:

- `tests/volcano_test.py`
- `tests/hami_test.py`
- `tests/vllm_chart_test.py`
- `tests/chart_regression_test.py`

What these tests already prove:

- all three charts render `schedulerName: volcano` when `scheduler.type=volcano`
- all three charts render `schedulerName: hami-scheduler` when `scheduler.type=hami`
- Volcano `PodGroup` creation, `groupMinMember`, `queueName`, `minResources`, and `priorityClassName` rendering work across charts
- HAMi-related render paths for scheduler annotations and vGPU memory-share values exist
- vLLM keeps the scheduler-specific resource/annotation wiring used by real deployments

What the automated tests do not prove:

- scheduler installation on a real cluster
- queue behavior in a live Volcano deployment
- gang-scheduling admission behavior
- actual HAMi vGPU sharing on GPU nodes
- actual device isolation and GPU UUID binding
- `volcano-vgpu-device-plugin` runtime integration

## Current Real-World Evidence In This Repo

The repo already contains runtime evidence from `ENV-42` in `TEST_REPORT.md`.
That evidence should be treated as authoritative for what is already observed,
and separate from scenarios that are still planned.

| ID | Scenario | Current status | Actual result already captured |
|---|---|---|---|
| `OBS-V-01` | Volcano manifest path | PASS | `schedulerName: volcano` and `PodGroup` creation are covered by automated tests across all inference charts |
| `OBS-V-02` | Volcano runtime on `ENV-42` | PASS for failure reproduction | `PodGroup` entered `Inqueue`; with plain `nvidia.com/gpu: 1`, Volcano bound the pod and kubelet returned `UnexpectedAdmissionError` |
| `OBS-V-03` | Volcano true multi-replica gang success | NOT YET CAPTURED | no local repo evidence yet for a successful `replicaCount>1` gang admission |
| `OBS-H-01` | HAMi manifest path | PASS | all inference charts render `schedulerName: hami-scheduler`; vLLM also renders explicit HAMi policy annotations and GPU share limits |
| `OBS-H-02` | HAMi single-GPU runtime on `ENV-42` | PASS | pod bound through HAMi and allocation annotation recorded a concrete GPU UUID |
| `OBS-H-03` | HAMi multi-pod vGPU sharing | NOT YET CAPTURED | no local repo evidence yet for two pods sharing one physical GPU at the same time |
| `OBS-H-04` | HAMi UUID isolation | PARTIAL | one real UUID-bound allocation exists; a competing second UUID-pinned pod result is not yet recorded |
| `OBS-E-27` | `ENV-27` rerun on 2026-04-05 | BLOCKED | sandbox cannot SSH to `192.168.23.27`, so no new live cluster evidence was collected in this workspace |

## Actual GPU Nodes Referenced by This Repo

These are the GPU nodes already referenced in repo docs and reports and should be treated as the primary runtime targets:

| ID | Host | GPU inventory | Source in repo | Intended use |
|---|---|---|---|---|
| `ENV-42` | `192.168.3.42` (`axe-master`) | `8 x RTX 2080 Ti` | `TEST_REPORT.md`, older `TEST_SCENARIOS.md` | current real-evidence node; HAMI and Volcano behavior already observed here |
| `ENV-27` | `192.168.23.27` | `8 x RTX 4090` | older `TEST_SCENARIOS.md` | higher-capacity multi-GPU validation target |

Current repo evidence is strongest on `ENV-42`. `ENV-27` remains the preferred target for larger TP, gang, and binpack validations that are hard to complete on 2080 Ti cards.

## Evidence Standard

Every real scheduler scenario should capture:

- rendered values file or exact `helm install` command
- `kubectl get pods -o wide`
- `kubectl describe pod`
- `kubectl logs`
- relevant events from `kubectl get events --sort-by=.lastTimestamp`
- `kubectl get deployment,podgroup,queue -A`
- one live API call when the workload is expected to become Ready
- cleanup result after the test

Additional scheduler-specific evidence:

- Volcano: `kubectl get podgroup -o yaml`, `kubectl get queue -o yaml`
- HAMi: pod annotations showing allocation, `nvidia.com/use-gpuuuid` evidence, device-share evidence
- vGPU plugin: node allocatable resources and device plugin pod logs

## Volcano Scheduler

### What Volcano Is

Volcano is a batch and AI/HPC scheduler for Kubernetes. In this repo, it matters because:

- it supplies `schedulerName: volcano`
- it uses `PodGroup` for gang scheduling
- it supports queue-based admission and quota management
- it exposes plugins such as `gang`, `binpack`, `drf`, and `proportion`

For this repo, Volcano-specific chart knobs are:

- `scheduler.type=volcano`
- `scheduler.volcano.createPodGroup=true`
- `scheduler.volcano.groupMinMember`
- `scheduler.volcano.queueName`
- `scheduler.volcano.minResources.*`

### How To Deploy Volcano

Official upstream project:

- `volcano-sh/volcano`

Typical install flow:

```bash
git clone https://github.com/volcano-sh/volcano.git
cd volcano
kubectl apply -f installer/volcano-development.yaml
kubectl get pods -n volcano-system
```

Minimum readiness check:

```bash
kubectl get pods -n volcano-system
kubectl get crd | rg 'volcano|podgroups|queues'
kubectl get svc -n volcano-system
```

Cluster expectations before testing this repo:

- `volcano-scheduler` is Running
- `PodGroup` and `Queue` CRDs exist
- queue admission is configured for your namespace
- if testing binpack behavior, the scheduler profile enables the relevant plugin

### Volcano Scenario V-01: Scheduler Smoke Test

Goal:

- prove a repo chart can target Volcano and render its core objects

Command template:

```bash
helm install vllm-volcano-smoke ./charts/vllm-inference \
  --namespace llm-serving --create-namespace \
  --set image.repository=test/vllm \
  --set image.tag=latest \
  --set scheduler.type=volcano \
  --set scheduler.volcano.createPodGroup=true \
  --set scheduler.volcano.groupMinMember=1
```

Success:

- Deployment has `schedulerName: volcano`
- `PodGroup` exists
- pod is scheduled or remains Pending for a scheduler reason that matches the requested resources

### Volcano Scenario V-02: Gang Scheduling

Goal:

- verify that replicas wait as a group instead of partially starting

Current repo evidence:

- `TEST_REPORT.md` already proves the Volcano path creates `PodGroup` objects and reaches scheduler/kubelet interaction on `ENV-42`
- the strongest observed runtime result so far is:
  - `PodGroup` created and `Inqueue` when constraints were not feasible
  - single-pod Volcano binding followed by kubelet `UnexpectedAdmissionError` when the cluster did not have the expected post-bind device allocation
- there is still no captured repo evidence for a successful `replicaCount=2` gang admission or a partial-admission prevention trace from a real two-replica Helm release

Recommended target:

- `ENV-27` first
- `ENV-42` second

Suggested config:

```bash
helm install vllm-volcano-gang ./charts/vllm-inference \
  --namespace llm-serving \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set replicaCount=2 \
  --set resources.limits.nvidia\.com/gpu=1 \
  --set scheduler.type=volcano \
  --set scheduler.volcano.createPodGroup=true \
  --set scheduler.volcano.groupMinMember=2 \
  --set scheduler.volcano.queueName=gpu-queue
```

Checks:

- `kubectl get podgroup -n llm-serving`
- `kubectl describe podgroup vllm-volcano-gang`
- both pods stay Pending until all resources are satisfiable, or both transition together
- no single replica becomes the only Running member when `minMember=2`

Pass criteria:

- `PodGroup.spec.minMember=2`
- scheduler events mention group admission rather than per-pod native scheduling

Observed result classification:

- mark as `PASS` when both replicas transition together or stay queued together
- mark as `PARTIAL` when only `PodGroup` creation and queueing are observed
- mark as `PASS for failure reproduction` when Volcano binds but kubelet/device-plugin admission fails after scheduling, because that still proves the chart reached the Volcano path
- keep `NOT YET EXECUTED` if the cluster run never happened

Failure categories to record:

- queue admission blocked
- insufficient GPUs
- kubelet/device-plugin admission failure after Volcano binding

### Volcano Scenario V-03: Queue Management

Goal:

- prove queue selection and queue-level control work with repo charts

Prerequisite:

- create explicit queues in Volcano

Example:

```yaml
apiVersion: scheduling.volcano.sh/v1beta1
kind: Queue
metadata:
  name: gpu-queue
spec:
  weight: 1
  reclaimable: true
  capability:
    cpu: "64"
    memory: "256Gi"
    nvidia.com/gpu: "8"
```

Test cases:

- deploy one release to `gpu-queue`
- deploy one release to `default`
- oversubscribe `gpu-queue` and verify only in-queue work is admitted within queue quota
- set `scheduler.volcano.minResources` larger than free capacity and verify the `PodGroup` stays queued

Repo-specific Helm knobs:

- `scheduler.volcano.queueName`
- `scheduler.volcano.minResources.cpu`
- `scheduler.volcano.minResources.memory`

Pass criteria:

- `PodGroup.spec.queue` matches the Helm value
- scheduler events mention queue gating when blocked

### Volcano Scenario V-04: Binpack Placement

Goal:

- verify Volcano can prefer dense packing when the cluster policy enables binpack

Why this matters here:

- TP and multi-replica inference often benefit from predictable packing on fewer nodes

Cluster prerequisite:

- Volcano scheduler config enables the `binpack` plugin for the active queue/profile

Suggested workload pair:

- deploy two single-GPU `vllm-inference` releases
- deploy one 2-GPU release after that

Checks:

- compare selected nodes for the three workloads
- if the cluster has multiple GPU nodes, verify whether Volcano packs onto the busiest eligible node instead of spreading
- if the result differs, capture the scheduler policy and node free-resource state before calling it a chart issue

Important repo boundary:

- the chart only tells Kubernetes to use Volcano and creates `PodGroup`
- actual binpack behavior is a cluster scheduler policy concern, not a Helm templating concern

## HAMi Scheduler

### What HAMi Is

HAMi is a heterogeneous device scheduler and virtualization layer for Kubernetes. In this repo, it matters because:

- it supplies `schedulerName: hami-scheduler`
- it supports GPU sharing and device-level placement
- it exposes policy annotations for node and GPU scheduling
- it supports GPU UUID pinning and vGPU memory/core limits

Repo knobs relevant to HAMi:

- `scheduler.type=hami`
- `scheduler.hami.gpuSharePercent`
- `scheduler.hami.nodeSchedulerPolicy`
- `scheduler.hami.gpuSchedulerPolicy`
- `scheduler.annotations.*` for cluster-specific HAMi keys such as `nvidia.com/use-gpuuuid`

### How To Deploy HAMi

Official upstream project:

- `Project-HAMi/HAMi`

Typical install flow:

```bash
git clone https://github.com/Project-HAMi/HAMi.git
cd HAMi
helm install hami hami-charts/hami \
  -n kube-system --create-namespace
kubectl get pods -n kube-system | rg hami
```

Minimum readiness check:

```bash
kubectl get pods -n kube-system
kubectl get ds -A | rg 'hami|vgpu'
kubectl get nodes -o custom-columns=NAME:.metadata.name,GPUMEM:.status.allocatable.nvidia\\.com/gpumem-percentage
```

Cluster expectations before testing this repo:

- `hami-scheduler` is Running
- HAMi device plugin DaemonSet is Running on GPU nodes
- GPU nodes advertise the expected allocatable resources

### HAMi Scenario H-01: Scheduler Smoke Test

Goal:

- prove a repo chart targets `hami-scheduler` correctly

Command template:

```bash
helm install llamacpp-hami-smoke ./charts/llamacpp-inference \
  --namespace llm-serving --create-namespace \
  --set scheduler.type=hami \
  --set gpuType=nvidia \
  --set model.name=Qwen/Qwen2.5-0.5B-Instruct-GGUF \
  --set model.ggufFile=qwen2.5-0.5b-instruct-q4_k_m.gguf
```

Pass criteria:

- pod spec shows `schedulerName: hami-scheduler`
- scheduling events are emitted by HAMi

### HAMi Scenario H-02: vGPU Sharing

Goal:

- verify multiple workloads can share one physical GPU through HAMi limits

Current repo evidence:

- `tests/hami_test.py` and `tests/vllm_chart_test.py` already prove the chart renders the HAMi scheduler path and maps `scheduler.hami.gpuSharePercent` to `nvidia.com/gpumem-percentage`
- `TEST_REPORT.md` already proves one real HAMi-scheduled pod bound successfully on `ENV-42` and exposed allocation annotations with a concrete GPU UUID
- there is still no local repo evidence for two concurrent pods sharing one physical GPU, and `TEST_PROCESS.md` records that the planned `ENV-27` rerun on `2026-04-05` was blocked by the sandbox before SSH could start

Recommended target:

- `ENV-42`

Suggested `vllm-inference` values:

```bash
helm install vllm-hami-share-a ./charts/vllm-inference \
  --namespace llm-serving \
  --set scheduler.type=hami \
  --set model.name=Qwen/Qwen2.5-0.5B-Instruct \
  --set resources.limits.nvidia\.com/gpu=1 \
  --set scheduler.hami.gpuSharePercent=50

helm install vllm-hami-share-b ./charts/vllm-inference \
  --namespace llm-serving \
  --set scheduler.type=hami \
  --set model.name=Qwen/Qwen2.5-0.5B-Instruct \
  --set resources.limits.nvidia\.com/gpu=1 \
  --set scheduler.hami.gpuSharePercent=50
```

Checks:

- both pods schedule successfully
- allocation annotations identify either the same physical GPU or compatible shared allocation according to HAMi
- neither pod is admitted beyond the configured share policy

Pass criteria:

- pod resources render `nvidia.com/gpumem-percentage`
- HAMi annotations or events prove the shared-device allocation

Detailed result cases to record:

- `H-02A Render-only PASS`: manifests contain `schedulerName: hami-scheduler` and `nvidia.com/gpumem-percentage`
- `H-02B Single-pod runtime PASS`: one pod binds through HAMi and exposes `hami.io/vgpu-devices-allocated`
- `H-02C Shared-GPU runtime PASS`: two pods are Running and their annotations prove a shared physical device or compatible HAMi fractional allocation
- `H-02D BLOCKED`: one pod binds but the second stays Pending because the node does not expose enough shareable device capacity

### HAMi Scenario H-03: Device Isolation With GPU UUID Pinning

Goal:

- prove a workload can be forced onto a specific GPU and kept off others

Recommended target:

- `ENV-42`, because repo evidence already includes a known allocated GPU UUID there

Suggested values:

```bash
helm install vllm-hami-isolated ./charts/vllm-inference \
  --namespace llm-serving \
  --set scheduler.type=hami \
  --set model.name=Qwen/Qwen2.5-0.5B-Instruct \
  --set resources.limits.nvidia\.com/gpu=1 \
  --set-string scheduler.annotations.nvidia\.com/use-gpuuuid=GPU-REPLACE-ME
```

Checks:

- pod annotation keeps the requested UUID
- actual allocated device matches that UUID
- a second pod pinned to a different UUID lands elsewhere or remains Pending when unavailable

Pass criteria:

- device binding is deterministic and auditable from pod annotations/events

### HAMi Scenario H-04: Node And GPU Policy Validation

Goal:

- verify repo values for node and GPU policy affect placement

Suggested values:

```bash
helm install vllm-hami-binpack ./charts/vllm-inference \
  --namespace llm-serving \
  --set scheduler.type=hami \
  --set scheduler.hami.nodeSchedulerPolicy=binpack \
  --set scheduler.hami.gpuSchedulerPolicy=spread \
  --set resources.limits.nvidia\.com/gpu=1
```

Checks:

- pod annotations include:
  - `hami.io/node-scheduler-policy=binpack`
  - `hami.io/gpu-scheduler-policy=spread`
- placement changes when re-run with the opposite policy pair

Important repo boundary:

- only `vllm-inference` currently renders the explicit HAMi node/GPU policy annotations
- `sglang-inference` and `llamacpp-inference` still rely on generic `scheduler.annotations.*` for cluster-specific HAMi keys

## `volcano-vgpu-device-plugin`

### What It Is

`volcano-vgpu-device-plugin` is the Volcano-side NVIDIA vGPU device plugin used with Volcano device sharing. It complements Volcano scheduling by advertising and allocating vGPU-style resources on GPU nodes.

In practical terms:

- Volcano handles queueing, gang, and scheduling
- the vGPU device plugin handles GPU resource advertisement and device allocation

### How To Deploy It

Upstream project:

- `Project-HAMi/volcano-vgpu-device-plugin`

Typical install flow:

```bash
git clone https://github.com/Project-HAMi/volcano-vgpu-device-plugin.git
cd volcano-vgpu-device-plugin
kubectl apply -f ./volcano-vgpu-device-plugin.yml
kubectl get pods -n kube-system | rg 'volcano|vgpu'
```

Minimum readiness check:

```bash
kubectl get ds -A | rg 'volcano|vgpu'
kubectl get nodes -o yaml | rg 'volcano.sh/vgpu|volcano\.sh'
```

Cluster expectations:

- Volcano is already installed
- GPU nodes expose the Volcano vGPU allocatable resources after the plugin starts

### Plugin Scenario P-01: Resource Advertisement

Goal:

- verify GPU nodes advertise Volcano-managed vGPU resources

Checks:

- `kubectl describe node <gpu-node>` shows Volcano vGPU resource keys
- device plugin logs show successful device registration

Pass criteria:

- allocatable resources exist before any repo workload is submitted

### Plugin Scenario P-02: Volcano + vGPU Workload Integration

Goal:

- prove a Volcano-scheduled workload can consume vGPU resources on actual GPU nodes

Recommended target:

- `ENV-42` first for smoke validation
- `ENV-27` for larger multi-workload validation

Suggested approach:

- use `vllm-inference` with `scheduler.type=volcano`
- inject plugin-specific resource requests through chart resource overrides or scheduler annotations used by your cluster
- keep `scheduler.volcano.createPodGroup=true` so queue/gang behavior remains visible

Checks:

- pod is bound by Volcano
- kubelet/device plugin admits the requested vGPU allocation
- allocation is visible in node or pod-level evidence

Record separately if failure happens at:

- Volcano queue admission
- podgroup gang admission
- device-plugin allocation
- kubelet post-bind admission

### Plugin Scenario P-03: Gang Scheduling With vGPU Resources

Goal:

- verify a multi-replica Volcano workload does not partially admit when the vGPU plugin cannot satisfy all members

Suggested config:

- `replicaCount=2`
- `scheduler.volcano.groupMinMember=2`
- vGPU resource request sized so only one replica fits

Pass criteria:

- no single replica starts alone
- `PodGroup` remains queued or pending until the full gang is feasible

## Actual-Node Execution Plan

### Phase 1: `ENV-42` Real Validation

Run these first because the repo already contains evidence from this node:

1. HAMi smoke test
2. HAMi vGPU sharing
3. HAMi UUID isolation
4. Volcano smoke test
5. Volcano gang scheduling with 2 small replicas
6. Volcano queue gating with explicit `Queue`
7. Volcano + vGPU plugin smoke test

Expected outcomes on `ENV-42`:

- strongest value for scheduler correctness and reproducibility
- weaker value for large TP and high-memory model success due to `8 x RTX 2080 Ti`
- current repo evidence already covers items `1`, part of `3`, and part of `4`

### Phase 2: `ENV-27` Scale Validation

Run these next:

1. Volcano gang scheduling with larger models
2. Volcano binpack across multiple GPU nodes if the cluster exposes them
3. HAMi TP=2 or TP=4 scheduling
4. Volcano + vGPU plugin saturation tests

Expected outcomes on `ENV-27`:

- better chance of completing real TP and large-model scenarios
- better target for queue/binpack tests that need more free GPU headroom
- as of `2026-04-05`, no new `ENV-27` evidence was added from this workspace because outbound SSH is blocked by the sandbox

## Pass/Fail Rules

Treat as chart failure when:

- a Helm value does not render into the expected manifest field
- the repo chart prevents the scheduler/plugin from receiving the needed config

Treat as environment or cluster-policy failure when:

- Volcano queue policy blocks admission but manifests are correct
- HAMi or vGPU plugin does not advertise resources correctly
- runtime image or driver compatibility blocks startup after successful scheduling
- the node simply does not have enough free GPU resources

## Quick Mapping From Repo Values To Scheduler Behavior

| Repo value | Scheduler path | Runtime effect to validate |
|---|---|---|
| `scheduler.type=volcano` | Volcano | pod uses Volcano scheduler |
| `scheduler.volcano.createPodGroup=true` | Volcano | gang object is created |
| `scheduler.volcano.groupMinMember` | Volcano | minimum gang size for admission |
| `scheduler.volcano.queueName` | Volcano | queue assignment |
| `scheduler.volcano.minResources.*` | Volcano | queue/admission gating |
| `scheduler.type=hami` | HAMi | pod uses `hami-scheduler` |
| `scheduler.hami.gpuSharePercent` | HAMi | GPU memory-share request |
| `scheduler.hami.nodeSchedulerPolicy` | HAMi | node packing/spread preference |
| `scheduler.hami.gpuSchedulerPolicy` | HAMi | GPU-level packing/spread/topology preference |
| `scheduler.annotations.nvidia.com/use-gpuuuid` | HAMi | deterministic device isolation |

## Related Files

- `tests/volcano_test.py`
- `tests/hami_test.py`
- `tests/vllm_chart_test.py`
- `TEST_REPORT.md`
- `charts/vllm-inference/README.md`
- `charts/sglang-inference/README.md`
- `charts/llamacpp-inference/README.md`
