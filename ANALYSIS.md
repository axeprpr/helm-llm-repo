# Helm LLM Inference - Codex Enhancement Report

## Part 1: Best Practices from Industry

### Repo-wide gaps found in the current charts

Across `vllm`, `sglang`, `tgi`, `llama.cpp`, `ollama`, `embedding`, and `vision`, the repo currently misses several production controls that show up in official docs and better-maintained chart repos:

- No first-class `ServiceMonitor` support for Prometheus Operator.
- No `PodDisruptionBudget` control.
- No `runtimeClassName`, `priorityClassName`, `terminationGracePeriodSeconds`, or `topologySpreadConstraints`.
- No `/dev/shm` mount for NCCL-heavy engines.
- No `serviceAccount` template even though values expose `serviceAccount.create`.
- No `NetworkPolicy`.
- Scheduler integration is partial and in places wired incorrectly.
- Most charts reuse a generic value schema instead of engine-specific settings, which hides critical runtime knobs.

### 1. vLLM

Primary sources:

- vLLM official Helm docs: <https://docs.vllm.ai/en/latest/deployment/frameworks/helm/>
- Substratus AI Helm charts: <https://github.com/substratusai/helm>

What current industry practice suggests:

- vLLM deployments usually expose model download/init behavior, persistent cache, and disruption controls. The official Helm docs explicitly document readiness/liveness probes, resource settings, and a pod disruption budget style control (`maxUnavailablePodDisruptionBudget`). They also document model download workflows, including S3-backed init flows.
- Production charts usually expose Prometheus scraping, ServiceMonitor integration, and safer rollout knobs.
- Multi-GPU and multi-node deployments benefit from topology spread, pod anti-affinity, and scheduler-aware configuration instead of only raw GPU requests.

What this repo is missing for `vllm-inference`:

- No PDB.
- No ServiceMonitor.
- No `/dev/shm` option for NCCL fallback/shared memory.
- No runtime class / priority class / topology spread knobs.
- No explicit Volcano PodGroup integration.
- No service account creation even though values claim to support it.

### 2. SGLang

Primary sources:

- SGLang docs: <https://docs.sglang.ai/>
- SGLang advanced attention backend guidance: <https://docs.sglang.ai/advanced_features/attention_backend.html>

What current industry practice suggests:

- SGLang operators tune tensor parallelism together with backend selection, KV/cache behavior, and batching behavior.
- Production deployments usually separate engine-specific flags instead of reusing generic vLLM-style args.
- Multi-GPU SGLang deployments need the same scheduling, `/dev/shm`, affinity, and observability controls as vLLM.

What this repo is missing for `sglang-inference`:

- No `/dev/shm`.
- No explicit metrics/ServiceMonitor support.
- No engine-specific values for attention backend, distributed launch mode, and server/router options.
- Scheduler integration exists only as `schedulerName`; there is no PodGroup or HAMi policy surface.

Inference from sources: the chart should stop modeling SGLang as “vLLM with a different image” and should expose SGLang-specific launch arguments directly.

### 3. llama.cpp

Primary sources:

- llama.cpp official repo: <https://github.com/ggml-org/llama.cpp>
- Server README mirror with feature list: <https://github.com/oss-evaluation-repository/ggerganov-llama.cpp/blob/master/examples/server/README.md>

Relevant official llama.cpp server capabilities:

- GGUF-first model loading.
- OpenAI-compatible server mode.
- Continuous batching.
- Monitoring endpoints.

What this repo is missing for `llamacpp-inference`:

- The value model is still Hugging Face-oriented instead of GGUF-oriented.
- No first-class PVC/local-path model mount for `.gguf` files.
- No engine flags for `--n-gpu-layers`, `--threads`, `--parallel`, `--alias`, `--ctx-size`, or GPU split options.
- No metrics/monitoring integration even though the server advertises monitoring endpoints.

### 4. Ollama

Primary sources:

- Example Helm repo: <https://github.com/feiskyer/ollama-kubernetes>
- Ollama production-oriented Kubernetes example search results

What better Ollama charts usually add:

- Persistent `/root/.ollama` storage.
- A values field for a list of models to pre-pull.
- Optional WebUI/Open WebUI integration.
- Replica/storage caveats when using multiple replicas.

What this repo is missing for `ollama-inference`:

- The persistence path is modeled like Hugging Face cache, which is wrong for Ollama.
- No model pre-pull job or init container.
- No `/api/pull` bootstrap workflow.
- No WebUI sidecar/subchart option.
- No production note about replica > 1 requiring shared model storage or pre-distributed model layers.

### 5. Hugging Face TGI

Primary sources:

- TGI official repo: <https://github.com/huggingface/text-generation-inference>
- Hugging Face HUGS on Kubernetes: <https://huggingface.co/docs/hugs/en/how-to/kubernetes>

Relevant official TGI guidance:

- TGI uses NCCL for tensor parallelism and explicitly documents `/dev/shm` requirements for Kubernetes deployments.
- TGI exposes OpenTelemetry via `--otlp-endpoint` and `--otlp-service-name`.
- Hugging Face Kubernetes guidance requires Kubernetes 1.23+ and Helm 3+.

What this repo is missing for `tgi-inference`:

- No `/dev/shm`.
- No OTel configuration surface.
- No ServiceMonitor / Prometheus integration.
- No engine-specific flags for sharding, max batch totals, JSON output settings, or tracing.

### Production concerns that should be standardized across charts

#### Metrics and observability

- Add `ServiceMonitor` to all server charts.
- Add `prometheus.io/*` annotations for clusters that do not use Prometheus Operator.
- Expose OpenTelemetry env/flags for TGI and, where applicable, vLLM.
- Document that Volcano vGPU metrics are served by the volcano scheduler metrics endpoint when HAMi/Volcano vGPU is used: <https://project-hami.io/docs/v2.5.1/userguide/volcano-vgpu/nvidia-gpu/monitor>

#### Logging

- Make JSON logging or structured logging configurable where engines support it.
- Add correlation or trace propagation env support for gateways and collectors.
- Avoid `apt-get` at runtime in entrypoint commands.

#### Resource management

- Add `/dev/shm` size configuration.
- Add `topologySpreadConstraints` and anti-affinity examples.
- Add `terminationGracePeriodSeconds` large enough for draining active requests.
- Add engine-specific resource knobs instead of only generic CPU/memory/GPU values.

#### Features popular chart repos expose

- Persistent model cache or model PVC.
- Model pre-download / pre-pull workflows.
- PDB.
- ServiceAccount creation.
- Prometheus Operator support.
- Optional ingress plus auth gateway.
- GPU placement and scheduler-specific settings.

## Part 2: Volcano + Hami Integration Guide

### How Volcano and Hami work together

Primary sources:

- Volcano unified scheduling: <https://volcano.sh/en/docs/v1-12-0/unified_scheduling/>
- Volcano PodGroup docs: <https://volcano.sh/en/docs/v1-10-0/podgroup/>
- HAMi architecture: <https://project-hami.io/docs/v2.5.1/core-concepts/architecture/>
- HAMi Volcano vGPU docs: <https://project-hami.io/docs/installation/how-to-use-volcano-vgpu>

Observed model:

- Volcano provides batch-style scheduling semantics for Kubernetes workloads, including gang scheduling, queueing, and PodGroup-based admission.
- HAMi provides GPU sharing, memory slicing, device accounting, and a scheduler extender / webhook path for heterogeneous AI devices.
- HAMi architecture explicitly states that the mutating webhook can set `schedulerName: HAMi-scheduler` and that the device-plugin layer reads scheduling results from pod annotations.
- HAMi also supports Volcano vGPU mode. This is the cleanest integration path when you want both gang scheduling and GPU sharing in the same cluster.

Practical integration model:

1. Use Volcano for queueing and gang scheduling semantics.
2. Use HAMi for GPU sharing and device-level allocation.
3. For strict gang behavior, create or reference a `PodGroup`.
4. For GPU sharing, request HAMi-managed extended resources or Volcano vGPU resources instead of raw `nvidia.com/gpu` when sharing is desired.

Inference from sources: for inference workloads, the simplest chart UX is:

- `scheduler.type: volcano` for full-device gang-scheduled jobs.
- `scheduler.type: hami` for HAMi native scheduling.
- `scheduler.type: volcano` plus Volcano vGPU resources when the cluster is installed in HAMi Volcano-vGPU mode.

### Key CRDs and objects

#### Volcano

- `PodGroup` (`scheduling.volcano.sh/v1beta1`)
  - Core gang-scheduling object.
  - Important fields: `spec.minMember`, `spec.minResources`, `spec.queue`, `spec.priorityClassName`.
- `Queue`
  - Queue object used for fairness and capacity management.
- `VCJob`
  - Volcano-native job abstraction for distributed and batch workloads.

For Helm charts serving long-running inference Deployments, `PodGroup` + native `Deployment` is usually a better first integration than forcing all users into `VCJob`.

#### HAMi

HAMi is mainly integrated through:

- Mutating webhook
- Scheduler / scheduler extender
- Device plugin
- Extended resources and annotations

Relevant resource examples from HAMi docs:

- `nvidia.com/gpu`
- `nvidia.com/gpumem`
- `nvidia.com/gpumem-percentage`

Example from official docs: <https://project-hami.io/docs/userguide/nvidia-device/examples/allocate-device-memory2/>

### Annotations and labels to support

Recommended chart surface:

- Volcano:
  - `schedulerName: volcano`
  - `scheduling.volcano.sh/queue-name`
  - `scheduling.volcano.sh/group-min-member`
  - optional explicit `PodGroup`
- HAMi:
  - `schedulerName: hami-scheduler`
  - `hami.io/node-scheduler-policy`
  - `hami.io/gpu-scheduler-policy`
- Shared labels:
  - stable `app.kubernetes.io/*` labels for ServiceMonitor, PDB, and PodGroup selectors

### Example YAML: Volcano gang scheduling for an inference Deployment

```yaml
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  name: qwen-vllm
  namespace: llm
spec:
  minMember: 2
  minResources:
    cpu: "16"
    memory: "128Gi"
    nvidia.com/gpu: "8"
  queue: inference
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qwen-vllm
  namespace: llm
  annotations:
    scheduling.volcano.sh/group-min-member: "2"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: qwen-vllm
  template:
    metadata:
      labels:
        app: qwen-vllm
      annotations:
        scheduling.k8s.io/group-name: qwen-vllm
        scheduling.volcano.sh/queue-name: inference
    spec:
      schedulerName: volcano
      containers:
        - name: vllm
          image: ghcr.io/vllm-project/vllm:0.8.5
          args:
            - serve
            - Qwen/Qwen2.5-72B-Instruct
            - --tensor-parallel-size=4
          resources:
            limits:
              nvidia.com/gpu: 4
              cpu: "8"
              memory: 64Gi
            requests:
              nvidia.com/gpu: 4
              cpu: "8"
              memory: 64Gi
```

### Example YAML: HAMi GPU sharing

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qwen-vllm-hami
  namespace: llm
spec:
  replicas: 1
  selector:
    matchLabels:
      app: qwen-vllm-hami
  template:
    metadata:
      labels:
        app: qwen-vllm-hami
      annotations:
        hami.io/node-scheduler-policy: binpack
        hami.io/gpu-scheduler-policy: spread
    spec:
      schedulerName: hami-scheduler
      containers:
        - name: vllm
          image: ghcr.io/vllm-project/vllm:0.8.5
          resources:
            limits:
              nvidia.com/gpu: 1
              nvidia.com/gpumem-percentage: 50
              cpu: "8"
              memory: 48Gi
            requests:
              nvidia.com/gpu: 1
              nvidia.com/gpumem-percentage: 50
              cpu: "8"
              memory: 48Gi
```

### Example YAML: Volcano + HAMi Volcano-vGPU mode

```yaml
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  name: llama70b-volcano-vgpu
  namespace: llm
spec:
  minMember: 2
  queue: inference
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llama70b-volcano-vgpu
  namespace: llm
spec:
  replicas: 2
  selector:
    matchLabels:
      app: llama70b-volcano-vgpu
  template:
    metadata:
      labels:
        app: llama70b-volcano-vgpu
      annotations:
        scheduling.k8s.io/group-name: llama70b-volcano-vgpu
        scheduling.volcano.sh/queue-name: inference
    spec:
      schedulerName: volcano
      containers:
        - name: server
          image: ghcr.io/huggingface/text-generation-inference:3.3.5
          volumeMounts:
            - name: shm
              mountPath: /dev/shm
          resources:
            limits:
              volcano.sh/vgpu-number: 1
              volcano.sh/vgpu-memory: 32768
              cpu: "8"
              memory: 64Gi
      volumes:
        - name: shm
          emptyDir:
            medium: Memory
            sizeLimit: 1Gi
```

Inference from sources: exact Volcano vGPU resource names should match the installed HAMi/Volcano mode and cluster version; charts should make these names configurable rather than hard-code them.

### How the Helm chart should integrate with both schedulers

Recommended values model:

```yaml
scheduler:
  type: native
  name: ""
  annotations: {}
  volcano:
    queueName: inference
    groupMinMember: 2
    createPodGroup: true
    minResources:
      cpu: "16"
      memory: "128Gi"
  hami:
    nodeSchedulerPolicy: binpack
    gpuSchedulerPolicy: spread
```

Recommended template behavior:

- If `scheduler.type == volcano`, set `schedulerName: volcano`.
- If `scheduler.volcano.queueName` is set, add `scheduling.volcano.sh/queue-name`.
- If `scheduler.volcano.createPodGroup` is true, render a `PodGroup` and annotate pods with `scheduling.k8s.io/group-name`.
- If `scheduler.type == hami`, set `schedulerName: hami-scheduler`.
- If HAMi policy values are set, add the related `hami.io/*` annotations.
- Keep raw resource keys configurable so the chart can support:
  - full GPU: `nvidia.com/gpu`
  - HAMi share mode: `nvidia.com/gpumem`, `nvidia.com/gpumem-percentage`
  - Volcano vGPU mode: `volcano.sh/vgpu-number`, `volcano.sh/vgpu-memory`

## Part 3: Deployment Architecture Requirements

### Kubernetes cluster requirements

Based on the repo and cited upstream docs:

- Kubernetes 1.23+ is the safe documented baseline from Hugging Face HUGS Kubernetes docs.
- Helm 3+ is required. The local environment already has Helm `v3.20.1`.
- CRDs required for optional integrations:
  - Volcano CRDs for `PodGroup`, `Queue`, `VCJob`
  - Prometheus Operator CRDs for `ServiceMonitor`
- Ingress controller is required if `ingress.enabled=true`.

### GPU operator requirements

#### NVIDIA

For `vllm`, `sglang`, `tgi`, `vision`, and many `embedding` workloads:

- NVIDIA driver on nodes
- NVIDIA Container Toolkit / runtime integration
- NVIDIA device plugin or GPU Operator
- For shared GPU:
  - HAMi installed, or
  - NVIDIA device plugin time-slicing if you choose that model instead of HAMi

Recommended chart documentation should call out these alternatives clearly:

- Full GPU allocation: `nvidia.com/gpu`
- NVIDIA time-slicing: works for best-effort sharing but does not provide the same memory isolation semantics as HAMi
- HAMi sharing: supports memory- or percentage-based slicing and device-level accounting

#### AMD / Intel / Ascend

- The charts expose `gpuType`, but actual runtime requirements are not documented.
- `llama.cpp` especially needs explicit docs for AMD/Intel drivers, runtime class, and node labels.

Inference from repo analysis: `gpuType` values exist, but cluster prerequisites for non-NVIDIA backends are not documented enough to be safely operable.

### Storage requirements

#### Model cache / PVC

- `vllm`, `sglang`, `tgi`, `embedding`, and `vision` need persistent cache support if startup downloads are used.
- `llama.cpp` should support a dedicated PVC for GGUF model files.
- `ollama` should use persistent `/root/.ollama`, not Hugging Face cache paths.

Recommended storage classes:

- `ReadWriteOnce` for single-replica local model caches
- `ReadWriteMany` only when your CSI actually supports it and you intentionally want multi-replica shared model cache

Important repo-specific observation:

- The repo currently assumes model download on startup in many places. That creates long cold starts, repeated downloads, and readiness flapping unless PVC or prefetch jobs are used.

### Network policy requirements

Recommended policies:

- Ingress:
  - allow only gateway / ingress controller / trusted namespaces to the API port
- Egress:
  - DNS
  - object storage / Hugging Face / model registry endpoints if downloading at runtime
  - telemetry collector if OTLP is enabled

Minimum example:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: vllm-inference
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: vllm-inference
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
      ports:
        - protocol: TCP
          port: 8000
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

### Node affinity and topology requirements

Recommended additions:

- `nodeSelector` for GPU class, zone, or accelerator SKU
- required anti-affinity or topology spread for multi-replica frontends
- required pod anti-affinity or topology rules for multi-node inference workers
- topology-aware placement when using NVLink islands or rack-local RDMA

For large tensor-parallel models:

- Prefer same-node placement when all shards fit on one node.
- For cross-node inference, document latency and network requirements explicitly.

### Helm version requirements

- Charts should declare Helm 3 support in docs.
- If optional templates require CRDs (`ServiceMonitor`, Volcano CRDs), document those as conditional dependencies rather than hard requirements.

## Part 4: Recommended Improvements (with code)

### A. Implemented in this branch: `vllm-inference`

The branch now adds these production-focused improvements to `charts/vllm-inference`:

- service account template
- pod disruption budget template
- ServiceMonitor template
- optional Volcano `PodGroup`
- scheduler annotation wiring for Volcano and HAMi
- `runtimeClassName`, `priorityClassName`, `terminationGracePeriodSeconds`
- `topologySpreadConstraints`
- `/dev/shm` support for NCCL-heavy workloads

Example values now supported:

```yaml
serviceAccount:
  create: true

podDisruptionBudget:
  enabled: true
  maxUnavailable: 1

metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s

shm:
  enabled: true
  sizeLimit: 1Gi

runtimeClassName: nvidia
priorityClassName: llm-serving-high
terminationGracePeriodSeconds: 180

scheduler:
  type: volcano
  volcano:
    queueName: inference
    groupMinMember: 2
    createPodGroup: true
    minResources:
      cpu: "16"
      memory: "128Gi"
```

### B. Apply the same baseline to `sglang-inference` and `tgi-inference`

These two charts should receive the same baseline templates as `vllm-inference` because they have the same operational needs:

```yaml
metrics:
  enabled: true
  serviceMonitor:
    enabled: false

podDisruptionBudget:
  enabled: false
  maxUnavailable: 1

shm:
  enabled: true
  sizeLimit: 1Gi

runtimeClassName: ""
priorityClassName: ""
terminationGracePeriodSeconds: 120
topologySpreadConstraints: []
```

### C. Fix engine-specific configuration drift

#### `llamacpp-inference`

Move from Hugging Face-style model values to GGUF-oriented values:

```yaml
model:
  ggufPath: /models/Qwen2.5-7B-Instruct-Q4_K_M.gguf
  alias: qwen2.5-7b

engine:
  port: 8080
  ctxSize: 8192
  threads: 8
  parallel: 4
  gpuLayers: 99
  extraArgs: ""

persistence:
  enabled: true
  mountPath: /models
  size: 100Gi
```

Deployment command example:

```yaml
command:
  - /bin/sh
  - -c
  - >
    llama-server
    -m {{ .Values.model.ggufPath }}
    --alias {{ .Values.model.alias }}
    --host 0.0.0.0
    --port {{ .Values.engine.port }}
    --ctx-size {{ .Values.engine.ctxSize }}
    --threads {{ .Values.engine.threads }}
    --parallel {{ .Values.engine.parallel }}
    --n-gpu-layers {{ .Values.engine.gpuLayers }}
    {{ .Values.engine.extraArgs }}
```

#### `ollama-inference`

Use Ollama-native cache and model pull workflow:

```yaml
persistence:
  enabled: true
  mountPath: /root/.ollama
  size: 100Gi

models:
  pull:
    - qwen2.5:7b
    - nomic-embed-text
```

Init container example:

```yaml
initContainers:
  - name: pull-models
    image: ollama/ollama:latest
    command:
      - /bin/sh
      - -c
      - |
        ollama serve &
        sleep 5
        ollama pull qwen2.5:7b
        ollama pull nomic-embed-text
```

#### `tgi-inference`

Add `/dev/shm` and OpenTelemetry:

```yaml
shm:
  enabled: true
  sizeLimit: 1Gi

extraEnv:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: http://otel-collector.observability.svc.cluster.local:4317

engine:
  extraArgs: >-
    --otlp-endpoint=$(OTEL_EXPORTER_OTLP_ENDPOINT)
    --otlp-service-name=tgi-inference
```

### D. Add a chart-level network policy toggle to every server chart

Recommended values surface:

```yaml
networkPolicy:
  enabled: false
  ingressNamespaces: []
  allowDnsEgress: true
  extraEgress: []
```

Recommended template behavior:

- permit API ingress only from listed namespaces
- always permit DNS if `allowDnsEgress=true`
- add object-store / Hugging Face egress rules only when runtime download is enabled

### E. Stop doing package installation in container start commands

Several charts currently run `apt-get update && apt-get install -y ssh-client` inside the main container command for distributed mode. This should be replaced with:

- a custom image that already contains the dependency, or
- an init container that prepares what is needed without mutating the main runtime image

This is a reliability and security issue for production clusters.

### F. Add a repo-wide requirements matrix

Recommended `README` table:

```markdown
| Feature | Requirement |
|---|---|
| vLLM / SGLang / TGI GPU | NVIDIA driver + device plugin or GPU Operator |
| HAMi sharing | HAMi installed; use HAMi resource keys |
| Volcano gang scheduling | Volcano CRDs + volcano scheduler |
| ServiceMonitor | Prometheus Operator CRDs |
| Runtime model download | Egress to HF/object store + PVC strongly recommended |
| Ollama persistence | PVC mounted at /root/.ollama |
| llama.cpp GGUF | PVC or hostPath with GGUF files |
```

## Sources

- vLLM Helm docs: <https://docs.vllm.ai/en/latest/deployment/frameworks/helm/>
- SGLang docs: <https://docs.sglang.ai/>
- SGLang attention backend docs: <https://docs.sglang.ai/advanced_features/attention_backend.html>
- llama.cpp official repo: <https://github.com/ggml-org/llama.cpp>
- llama.cpp server README mirror: <https://github.com/oss-evaluation-repository/ggerganov-llama.cpp/blob/master/examples/server/README.md>
- feiskyer Ollama Helm repo: <https://github.com/feiskyer/ollama-kubernetes>
- Hugging Face TGI repo: <https://github.com/huggingface/text-generation-inference>
- Hugging Face HUGS on Kubernetes: <https://huggingface.co/docs/hugs/en/how-to/kubernetes>
- Volcano unified scheduling: <https://volcano.sh/en/docs/v1-12-0/unified_scheduling/>
- Volcano PodGroup docs: <https://volcano.sh/en/docs/v1-10-0/podgroup/>
- Volcano Queue docs: <https://volcano.sh/en/docs/v1-9-0/queue/>
- HAMi architecture: <https://project-hami.io/docs/v2.5.1/core-concepts/architecture/>
- HAMi Volcano vGPU docs: <https://project-hami.io/docs/installation/how-to-use-volcano-vgpu>
- HAMi GPU memory percentage example: <https://project-hami.io/docs/userguide/nvidia-device/examples/allocate-device-memory2/>
