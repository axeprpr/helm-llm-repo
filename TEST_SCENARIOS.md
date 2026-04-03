# Helm LLM Repo - Test Scenarios and Test Cases

**Date:** 2026-04-03 18:30 UTC
**Repo:** https://github.com/axeprpr/helm-llm-repo

---

## 1. Overview

Comprehensive test scenarios for helm-llm-repo charts (vllm-inference, sglang-inference, llamacpp-inference).

**Scope:** Volcano scheduler, Hami GPU scheduler, vLLM engine, NVLink, and real inference.
**Environment:** axe-master (192.168.3.42) — 8× RTX 2080 Ti

---

## 2. Test Categories

### 2.1 Template Rendering Tests (No Cluster Required)

| TC | Description | Charts | Scheduler |
|----|-------------|--------|-----------|
| TC-101 | Basic chart renders | All 3 | native |
| TC-102 | volcano schedulerName set | All 3 | volcano |
| TC-103 | hami schedulerName set | All 3 | hami |
| TC-104 | Volcano PodGroup created | All 3 | volcano+createPodGroup=true |
| TC-105 | Volcano PodGroup NOT created when disabled | All 3 | volcano,createPodGroup=false |
| TC-106 | HPA manifest rendered | vllm | native |
| TC-107 | ServiceMonitor rendered | vllm | native |
| TC-108 | ConfigMap model catalog rendered | vllm | native |
| TC-109 | Shared memory /dev/shm rendered | vllm | any |
| TC-110 | GPU tolerations nvidia | All 3 | any |
| TC-111 | GPU tolerations amd | All 3 | any |
| TC-112 | GPU tolerations ascend | All 3 | any |
| TC-113 | TP=2 engine arg correct | vllm | any |
| TC-114 | PP=2 env vars correct | vllm | any |
| TC-115 | NCCL init container for distributed | vllm | any |

### 2.2 Real Deployment Tests (Cluster Required)

| TC | Description | Method | Status |
|----|-------------|--------|--------|
| TC-201 | vLLM single-GPU deploys | helm install + kubectl wait | ❌ BLOCKED |
| TC-202 | vLLM /health returns 200 | curl http://pod:8000/health | ❌ BLOCKED |
| TC-203 | vLLM chat completion works | POST /v1/chat/completions | ❌ BLOCKED |
| TC-204 | vLLM TP=2 deploys | helm install + kubectl wait | ❌ BLOCKED |
| TC-205 | TP=2 NVLink topology verified | nvidia-smi topo -m in pod | ❌ BLOCKED |
| TC-206 | TP=2 /dev/shm mounted | df -h /dev/shm in pod | ❌ BLOCKED |
| TC-207 | TP=2 inference returns correct answer | POST /v1/chat/completions | ❌ BLOCKED |
| TC-208 | Volcano pod scheduled by volcano scheduler | kubectl get pod | ⚠️ NOT TESTED |
| TC-209 | Hami pod scheduled by hami-scheduler | kubectl get pod | ⚠️ NOT TESTED |
| TC-210 | SGLang deployment | helm install | ⚠️ NOT TESTED |
| TC-211 | llama.cpp CUDA deployment | helm install | ⚠️ NOT TESTED |

**Blocker:** vLLM v0.11.0 requires HuggingFace network access to initialize, even for fully local models.

### 2.3 Hardware-Limited Tests (Documented, Not Executed)

| TC | Description | Reason |
|----|-------------|--------|
| TC-301 | Multi-node PP=2 | Requires 2+ GPU nodes |
| TC-302 | Multi-node TP=4+PP=2 | Requires 2+ GPU nodes |
| TC-303 | GPUDirect RDMA | Requires InfiniBand |
| TC-304 | MIG multi-instance | RTX 2080 Ti has no MIG support |

---

## 3. Volcano Scheduler Test Cases

### TC-VOL-001: volcano scheduler sets schedulerName
- **Input:** `scheduler.type=volcano`
- **Expected:** deployment.spec.template.spec.schedulerName = "volcano"
- **Method:** `helm template | grep schedulerName`

### TC-VOL-002: PodGroup created with createPodGroup=true
- **Input:** `scheduler.type=volcano, scheduler.volcano.createPodGroup=true`
- **Expected:** kind: PodGroup in rendered YAML
- **Method:** `helm template | grep 'kind: PodGroup'`

### TC-VOL-003: PodGroup NOT created with createPodGroup=false
- **Input:** `scheduler.type=volcano, scheduler.volcano.createPodGroup=false`
- **Expected:** No PodGroup in rendered YAML
- **Method:** `helm template | grep 'kind: PodGroup'` → 0 matches

### TC-VOL-004: PodGroup queueName
- **Input:** `scheduler.volcano.queueName=prod-queue`
- **Expected:** PodGroup.spec.queue = "prod-queue"
- **Method:** `helm template + grep`

### TC-VOL-005: PodGroup minMember
- **Input:** `scheduler.volcano.groupMinMember=3`
- **Expected:** PodGroup.spec.minMember = 3

### TC-VOL-006: PodGroup minResources
- **Input:** `scheduler.volcano.minResources.memory=32Gi, cpu=16`
- **Expected:** PodGroup.spec.minResources contains memory and cpu

### TC-VOL-007: Real Volcano pod scheduling
- **Input:** volcano PodGroup + Pod with schedulerName=volcano
- **Expected:** Pod phase = Running/Succeeded
- **Method:** kubectl apply + kubectl get pod
- **Status:** ⚠️ Not tested due to infrastructure constraint

---

## 4. Hami GPU Scheduler Test Cases

### TC-HAM-001: hami scheduler sets schedulerName
- **Input:** `scheduler.type=hami`
- **Expected:** deployment.spec.template.spec.schedulerName = "hami-scheduler"

### TC-HAM-002: Real Hami pod scheduling
- **Input:** Pod with schedulerName=hami-scheduler
- **Expected:** Pod phase = Running
- **Status:** ⚠️ Not tested due to infrastructure constraint

### TC-HAM-003: gpuMemoryFraction values
- **Input:** `scheduler.hami.gpuMemoryFraction=0.2/0.5/0.9/1.0`
- **Expected:** renders without error

### TC-HAM-004: nodeSchedulerPolicy
- **Input:** `scheduler.hami.nodeSchedulerPolicy=binpack/spread/bind`

### TC-HAM-005: gpuSchedulerPolicy
- **Input:** `scheduler.hami.gpuSchedulerPolicy=binds/full/shared`

### TC-HAM-006: migStrategy
- **Input:** `scheduler.hami.migStrategy=none/single/mixed`
- **Note:** RTX 2080 Ti does not support MIG

---

## 5. vLLM Engine Test Cases

### TC-VLLM-001: Basic engine args
- **Input:** `model.name=Qwen/Qwen2.5-7B-Instruct`, all defaults
- **Expected:** `--model Qwen/Qwen2.5-7B-Instruct --trust-remote-code --gpu-memory-utilization=0.90 --max-model-len=8192 --port=8000`

### TC-VLLM-002: TP=2 adds --tensor-parallel-size=2
- **Input:** `engine.tensorParallelSize=2`
- **Expected:** `--tensor-parallel-size 2`

### TC-VLLM-003: PP=2 adds VLLM_PIPELINE_PARALLEL_SIZE env
- **Input:** `engine.pipelineParallelSize=2`
- **Expected:** `VLLM_PIPELINE_PARALLEL_SIZE=2` env var

### TC-VLLM-004: Reasoning parser
- **Input:** `model.reasoningParser=deepseek_r1`
- **Expected:** `--reasoning-parser deepseek_r1`

### TC-VLLM-005: Embedding task
- **Input:** `model.type=embedding, engine.embeddingTask=embed`
- **Expected:** `--task embed`

### TC-VLLM-006: extraArgs passthrough
- **Input:** `engine.extraArgs="--enforce-eager"`
- **Expected:** `--enforce-eager`

---

## 6. NVLink Test Cases (RTX 2080 Ti)

### TC-NVL-001: TP=2 on NVLink-connected GPUs
- **Input:** `engine.tensorParallelSize=2, resources.limits.nvidia.com/gpu=2`
- **Method:** nvidia-smi topo -m shows NV1 for connected GPU pairs
- **RTX 2080 Ti NVLink pairs:** (0,3), (1,2), (4,7), (5,6)
- **Test pair:** GPU 6+7 (PIX connection)

### TC-NVL-002: NVLink topology verification
- **Method:** `nvidia-smi topo -m` in pod
- **Expected:** NV1 or PIX for GPU pairs

### TC-NVL-003: TP=2 throughput vs TP=1
- **Method:** Run identical benchmark TP=1 vs TP=2, compare req/s
- **Note:** RTX 2080 Ti is slow (3.5 TFLOPS vs 55+ TFLOPS needed for 27B model)

---

## 7. Multi-Node Test (Hardware Limited)

> ⚠️ **NOTE:** Multi-node tests require at least 2 GPU nodes.
> Current environment has only 1 node (axe-master).
> For multi-node testing:
> ```bash
> helm install test charts/vllm-inference \
>   --set distributed.enabled=true \
>   --set distributed.nodeList=node2,node3 \
>   --set distributed.masterAddr=node2 \
>   --set engine.tensorParallelSize=2 \
>   --set engine.pipelineParallelSize=2
> ```

---

## 8. How to Run Tests

### Prerequisites
- Kubernetes cluster with GPU nodes
- kubectl and helm installed
- NVIDIA device plugin installed
- Volcano and/or Hami schedulers installed

### Template Tests (no cluster required)
```bash
git clone https://github.com/axeprpr/helm-llm-repo
cd helm-llm-repo
REPO_ROOT=$PWD pytest tests/ -v --tb=short
```

### Real Deployment Tests
```bash
# Single GPU deployment
helm install test-vllm-single charts/vllm-inference \
  --namespace default \
  --set image.repository=docker.io/vllm/vllm-openai \
  --set image.tag=v0.11.0-x86_64 \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set scheduler.type=hami \
  --timeout 300s

# Wait for pod
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=test-vllm-single -n default --timeout=300s

# Health check
kubectl exec -it test-vllm-single-xxx -n default -- wget -q -O- http://localhost:8000/health

# Inference test
kubectl exec -it test-vllm-single-xxx -n default -- \
  wget -q -O- --post-data='{"model":"Qwen/Qwen2.5-7B-Instruct","messages":[{"role":"user","content":"What is 2+2?"}],"max_tokens":20}' \
  --header="Content-Type: application/json" \
  http://localhost:8000/v1/chat/completions
```

---

_Generated by 35号技师 (Codex Agent) on 2026-04-03_
