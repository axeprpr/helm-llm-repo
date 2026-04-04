# Helm LLM Test Scenarios

Date: 2026-04-04

## Purpose

This document defines the complete test matrix for `helm-llm-repo`, with emphasis on:

- `charts/vllm-inference`
- HAMi scheduling behavior
- Volcano scheduling behavior
- real deployment evidence on:
  - `192.168.3.42` with `8 x RTX 2080 Ti`
  - `192.168.23.27` with `8 x RTX 4090`

The goal is not “template renders OK”, but end-to-end proof that:

- chart values map to the expected Kubernetes manifest,
- the chosen scheduler really binds workloads as designed,
- vLLM can perform real inference,
- failures are recorded as environment incompatibility, scheduler limitation, or chart bug with evidence.

## Scheduler Difference Summary

### HAMi

HAMi is device-centric. The key behaviors to validate are:

- GPU sharing through `nvidia.com/gpumem` or `nvidia.com/gpumem-percentage`
- GPU core sharing through `nvidia.com/gpucores`
- explicit GPU UUID selection through `nvidia.com/use-gpuuuid`
- node and GPU placement policies through:
  - `hami.io/node-scheduler-policy`
  - `hami.io/gpu-scheduler-policy`
- topology-aware GPU placement on NVIDIA when available
- dynamic MIG support on compatible NVIDIA generations

### Volcano

Volcano is queue and gang-scheduling centric. The key behaviors to validate are:

- `PodGroup` creation and lifecycle
- `minMember` gang semantics
- `queue` assignment and queue state
- `minResources` admission gating
- `priorityClassName` ordering / preemption interaction
- queue-level multi-tenant resource control
- unified scheduling plugins such as `gang`, `drf`, `proportion`, `nodeorder`, `binpack`

### Practical Difference for This Repository

- HAMi answers “which GPU, how much GPU memory/core, can I share or pin a device?”
- Volcano answers “when may this group run, in which queue, and under what gang / priority / quota policy?”
- `vllm-inference` must therefore be tested in three modes:
  - native kube-scheduler
  - HAMi scheduler
  - Volcano scheduler

## Environments

### ENV-42

- Host: `192.168.3.42`
- GPUs: `8 x RTX 2080 Ti`
- Purpose:
  - validate proxy-assisted model pulls
  - validate HAMi on older Turing GPUs
  - validate Volcano admission and failure modes on the existing cluster
- Known facts already observed:
  - Clash proxy exists at `http://192.168.3.42:7890`
  - actual topology is not “GPU6/GPU7 NVLink”
  - `GPU0 <-> GPU3 = NV1`
  - `GPU6 <-> GPU7 = PIX`

### ENV-27

- Host: `192.168.23.27`
- GPUs: `8 x RTX 4090`
- Purpose:
  - validate the same chart on larger Ada GPUs
  - validate higher-probability multi-GPU inference success
  - validate whether topology-aware or explicit card pinning changes placement outcome

## Evidence Standard

Every real deployment scenario must collect:

- rendered Helm values file
- `kubectl get pod -o wide`
- `kubectl describe pod`
- `kubectl logs`
- scheduler events
- if Volcano is enabled:
  - `kubectl get podgroup -o yaml`
- if HAMi is enabled:
  - pod annotations showing device allocation
- one real API call:
  - `/health`
  - `/v1/chat/completions`, `/v1/embeddings`, or `/v1/rerank`
- cleanup status after the test

## Test Matrix

### A. Static Render Tests

#### A-01 vLLM launcher correctness

Goal:
- prove the chart launches `vllm serve` with model name as a positional argument.

Checks:
- command contains `vllm serve <model>`
- command does not contain deprecated `--model` server invocation

#### A-02 vLLM feature flag rendering

Goal:
- validate value-to-flag mapping for chart-managed vLLM features.

Checks:
- `model.type=embedding` renders `--task`
- `engine.embeddingTask=embed` renders `--pooler-output-fn`
- `engine.embeddingTask=rank` does not render pooler output flag
- `engine.enablePrefixCaching=true` renders `--enable-prefix-caching`
- `engine.enableChunkedPrefill=true` renders `--enable-chunked-prefill`
- `model.reasoningParser=...` renders `--reasoning-parser`
- `engine.tensorParallelSize` renders `--tensor-parallel-size`
- `engine.pipelineParallelSize` renders `--pipeline-parallel-size`

#### A-03 vLLM runtime override rendering

Goal:
- validate chart escape hatches needed for real clusters.

Checks:
- `command` override renders exactly
- `args` override renders exactly
- `startupProbe` renders
- `runtimeClassName` renders
- `priorityClassName` renders
- `terminationGracePeriodSeconds` renders
- persistence mount path is configurable

#### A-04 HAMi manifest rendering

Goal:
- validate that HAMi-specific values actually affect the manifest.

Checks:
- `scheduler.type=hami` sets `schedulerName: hami-scheduler`
- `scheduler.hami.nodeSchedulerPolicy` maps to `hami.io/node-scheduler-policy`
- `scheduler.hami.gpuSchedulerPolicy` maps to `hami.io/gpu-scheduler-policy`
- `scheduler.hami.gpuSharePercent` maps to `nvidia.com/gpumem-percentage`
- arbitrary scheduler annotations such as `nvidia.com/use-gpuuuid` are preserved

#### A-05 Volcano manifest rendering

Goal:
- validate Volcano-specific resources emitted by the chart.

Checks:
- `scheduler.type=volcano` sets `schedulerName: volcano`
- `scheduler.volcano.createPodGroup=true` creates `PodGroup`
- `scheduler.volcano.groupMinMember` maps to:
  - `PodGroup.spec.minMember`
  - deployment annotation when PodGroup creation is disabled
- `scheduler.volcano.queueName` maps to `PodGroup.spec.queue`
- `scheduler.volcano.minResources` maps to `PodGroup.spec.minResources`
- `priorityClassName` maps to `PodGroup.spec.priorityClassName`

### B. vLLM Functional Scenarios

#### B-01 Chat completion

Target:
- ENV-42
- ENV-27

Goal:
- serve a chat model and return a real completion.

Minimum config:
- `model.type=chat`
- `scheduler.type=hami`
- 1 GPU

Success:
- pod becomes Ready
- `/health` returns success
- `/v1/chat/completions` returns non-empty content

#### B-02 Embedding

Target:
- ENV-27 preferred
- ENV-42 optional with a small embedding model

Goal:
- prove embedding mode works with `model.type=embedding`.

Minimum config:
- `engine.embeddingTask=embed`

Success:
- `/v1/embeddings` returns a numeric vector

#### B-03 Rerank / score

Target:
- ENV-27 preferred

Goal:
- prove pooling/rerank path works.

Minimum config:
- `model.type=embedding`
- `engine.embeddingTask=rank`

Success:
- `/v1/rerank` or equivalent scoring endpoint returns ranked results

#### B-04 Reasoning parser

Target:
- ENV-27 preferred

Goal:
- prove reasoning-capable models render and boot with `--reasoning-parser`.

Success:
- process starts without CLI error
- chat completion returns valid OpenAI-compatible payload

#### B-05 Tensor parallelism

Target:
- ENV-27 primary
- ENV-42 secondary

Goal:
- prove TP>1 scheduling and inference.

Variants:
- TP=2
- TP=4 if model and environment permit

Success:
- requested GPU count is allocated
- container logs show multi-GPU startup
- inference succeeds

Failure recording:
- if blocked, capture whether it is:
  - scheduler allocation
  - topology / NCCL issue
  - model OOM
  - runtime incompatibility

#### B-06 NVLink / topology-aware placement

Target:
- both hosts

Goal:
- determine whether topology-aware selection produces better placement than naive free-card selection.

Method:
- compare:
  - explicit UUID pinning
  - free-card scheduling
  - HAMi topology-aware policy when available
- collect `nvidia-smi topo -m` before deployment

Success:
- chosen cards and observed performance / startup stability are recorded

Important:
- do not assume `GPU6/GPU7` are an NVLink pair; verify per host first

### C. HAMi Scheduler Scenarios

#### C-01 Single GPU explicit UUID pinning

Goal:
- verify `nvidia.com/use-gpuuuid` is respected.

Success:
- pod is scheduled by `hami-scheduler`
- allocation annotation includes the requested UUID

#### C-02 GPU memory sharing

Goal:
- verify `nvidia.com/gpumem-percentage` based sharing.

Variants:
- 25%
- 50%
- 100%

Success:
- pod is admitted only when accounting permits
- actual allocation is reflected in annotations or scheduler events

#### C-03 Node policy

Goal:
- verify `hami.io/node-scheduler-policy`.

Variants:
- `binpack`
- `spread`

Success:
- scheduling preference matches cluster state and policy intent

#### C-04 GPU policy

Goal:
- verify `hami.io/gpu-scheduler-policy`.

Variants:
- `binpack`
- `spread`
- `topology-aware` on NVIDIA

Success:
- selected GPU differs when policy changes, if cluster state makes the choice observable

#### C-05 Card type filter

Goal:
- verify `nvidia.com/use-gputype` and blacklist behavior where relevant.

Success:
- pod lands only on allowed card type

#### C-06 Dynamic MIG compatibility

Goal:
- record whether MIG scenarios are applicable on the host.

Expectation:
- ENV-42 and ENV-27 are not Ampere/Hopper MIG environments, so this is likely “not applicable”.

Success:
- explicitly record N/A instead of silently omitting the feature

### D. Volcano Scheduler Scenarios

#### D-01 PodGroup creation and lifecycle

Goal:
- verify `PodGroup` creation and phase transitions.

Success:
- `PodGroup` exists
- observed phase is one of:
  - `pending`
  - `inqueue`
  - `running`
  - `unknown`

#### D-02 Gang scheduling via `minMember`

Goal:
- verify “all-or-nothing” behavior for grouped pods.

Variants:
- `replicaCount=2`, `groupMinMember=2`
- `replicaCount=2`, `groupMinMember=1`

Success:
- group with unmet minimum does not partially run

#### D-03 Queue routing

Goal:
- verify `queueName` places the PodGroup into the expected queue.

Success:
- `PodGroup.spec.queue` matches
- queue exists and is `Open`

#### D-04 `minResources` admission gating

Goal:
- verify the pod group remains blocked when minimum resources are not available.

Success:
- failure is visible in `PodGroup.conditions` or events

#### D-05 Priority / preemption behavior

Goal:
- verify `priorityClassName` propagation and observe whether higher-priority PodGroups preempt or outrank lower-priority ones in the queue.

Success:
- ordering change or preemption evidence is recorded

#### D-06 Volcano vs HAMi interaction

Goal:
- document whether Volcano alone can allocate GPU workloads correctly on the host, and how that differs from HAMi.

Success:
- exact observed behavior is captured:
  - success
  - `UnexpectedAdmissionError`
  - `PodGroup` stuck `Inqueue`
  - other cluster-specific failure

### E. Proxy and Artifact Pull Scenarios

#### E-01 ENV-42 proxy verification

Goal:
- prove model/image pulls can route through Clash when required.

Checks:
- pod env contains lowercase and/or uppercase proxy variables as intended
- model/image pull proceeds
- failures distinguish:
  - DNS
  - registry access
  - runtime compatibility

#### E-02 Offline / local-model path

Goal:
- prove local PVC-mounted model deployment works without external download dependency.

Success:
- no remote model download is required
- inference succeeds from local cache or PVC

## Real Deployment Execution Order

Recommended order:

1. static render tests
2. ENV-42 proxy verification
3. ENV-42 HAMi single-GPU smoke
4. ENV-42 Volcano PodGroup and failure-mode capture
5. ENV-27 HAMi single-GPU smoke
6. ENV-27 TP=2 / topology comparison
7. ENV-27 embedding / rerank / reasoning

## Real Deployment Command Templates

### ENV-42 Hami chat smoke

```bash
helm upgrade --install vllm-hami-chat ./charts/vllm-inference \
  -n llm-serving --create-namespace \
  --set scheduler.type=hami \
  --set scheduler.annotations.nvidia.com/use-gpuuuid=GPU-REPLACE_ME \
  --set scheduler.hami.nodeSchedulerPolicy=binpack \
  --set scheduler.hami.gpuSchedulerPolicy=topology-aware \
  --set scheduler.hami.gpuSharePercent=100 \
  --set model.name=Qwen/Qwen2.5-0.5B-Instruct \
  --set model.type=chat \
  --set persistence.enabled=true \
  --set persistence.mountPath=/root/.cache/huggingface \
  --set extraEnv[0].name=http_proxy \
  --set extraEnv[0].value=http://192.168.3.42:7890 \
  --set extraEnv[1].name=https_proxy \
  --set extraEnv[1].value=http://192.168.3.42:7890

kubectl -n llm-serving get pod -o wide
kubectl -n llm-serving describe pod -l app.kubernetes.io/instance=vllm-hami-chat
kubectl -n llm-serving logs -l app.kubernetes.io/instance=vllm-hami-chat --tail=200
kubectl -n llm-serving port-forward deploy/vllm-hami-chat-vllm-inference 18000:8000
curl http://127.0.0.1:18000/health
curl http://127.0.0.1:18000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","messages":[{"role":"user","content":"reply with HAMI_OK"}]}'
```

### ENV-42 Volcano PodGroup smoke

```bash
helm upgrade --install vllm-volcano-chat ./charts/vllm-inference \
  -n llm-serving --create-namespace \
  --set scheduler.type=volcano \
  --set scheduler.volcano.createPodGroup=true \
  --set scheduler.volcano.groupMinMember=1 \
  --set scheduler.volcano.queueName=default \
  --set model.name=Qwen/Qwen2.5-0.5B-Instruct

kubectl -n llm-serving get podgroup
kubectl -n llm-serving get podgroup vllm-volcano-chat-vllm-inference -o yaml
kubectl -n llm-serving describe pod -l app.kubernetes.io/instance=vllm-volcano-chat
kubectl -n llm-serving get events --sort-by=.lastTimestamp | tail -n 50
```

### ENV-27 Hami TP=2 smoke

```bash
helm upgrade --install vllm-hami-tp2 ./charts/vllm-inference \
  -n llm-serving --create-namespace \
  --set scheduler.type=hami \
  --set scheduler.hami.nodeSchedulerPolicy=binpack \
  --set scheduler.hami.gpuSchedulerPolicy=topology-aware \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set model.type=chat \
  --set engine.tensorParallelSize=2 \
  --set resources.limits.nvidia.com/gpu=2 \
  --set shm.enabled=true \
  --set shm.sizeLimit=8Gi

kubectl -n llm-serving get pod -o wide
kubectl -n llm-serving describe pod -l app.kubernetes.io/instance=vllm-hami-tp2
kubectl -n llm-serving logs -l app.kubernetes.io/instance=vllm-hami-tp2 --tail=200
```

### Evidence collection bundle

```bash
kubectl -n llm-serving get pod -o wide > evidence-pods.txt
kubectl -n llm-serving get events --sort-by=.lastTimestamp > evidence-events.txt
kubectl -n llm-serving get podgroup -o yaml > evidence-podgroups.yaml
kubectl -n llm-serving get deploy -o yaml > evidence-deployments.yaml
```

## Exit Criteria

The repository can be called “tested” only when all of the following are true:

- static render tests pass
- at least one real Hami-scheduled `vllm-inference` deployment returns real inference on ENV-42
- at least one real Hami-scheduled `vllm-inference` deployment returns real inference on ENV-27
- Volcano behavior is recorded with real `PodGroup` and scheduler evidence
- unsupported or blocked scenarios are marked explicitly as:
  - environment limitation
  - scheduler limitation
  - chart bug
- all fixes are committed in-repo

## Reference Links

- vLLM serve CLI: <https://docs.vllm.ai/en/latest/cli/serve/>
- vLLM quantization support matrix: <https://docs.vllm.ai/en/stable/features/quantization/>
- HAMi scheduler policy: <https://project-hami.io/docs/developers/scheduling/>
- HAMi device memory allocation: <https://project-hami.io/docs/userguide/nvidia-device/specify-device-memory-usage>
- HAMi assign task to a certain GPU: <https://project-hami.io/docs/userguide/nvidia-device/examples/specify-certain-card/>
- HAMi dynamic MIG support: <https://project-hami.io/docs/userguide/nvidia-device/dynamic-mig-support>
- Volcano PodGroup: <https://volcano.sh/en/docs/podgroup/>
- Volcano queue: <https://volcano.sh/en/docs/queue/>
- Volcano unified scheduling: <https://volcano.sh/en/docs/v1-12-0/unified_scheduling/>
