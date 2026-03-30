# Helm LLM Inference Repository

一站式大模型推理部署 Helm Chart 仓库，`helm install` 一键部署各种推理引擎到 Kubernetes。

**Helm Repo：** `https://axeprpr.github.io/helm-llm-repo`

---

## 支持的引擎

| Chart | 引擎 | 适用场景 | 多 GPU | 多机 |
|-------|------|---------|--------|------|
| `vllm-inference` | vLLM | 通用推理：Chat / Embedding / Rerank / Vision | ✅ | ✅ |
| `sglang-inference` | SGLang | 树结构/RAG/Agent 推理 | ✅ | ✅ |
| `llamacpp-inference` | llama.cpp | CPU/GPU、5种后端、NVIDIA/AMD/ROCm/Vulkan/MUSA | ✅ | ❌ |

---

---

## 🏗️ 部署架构

### 集群组件要求

部署 LLM 推理服务前，你的 Kubernetes 集群需要满足以下要求：

#### 基础要求

| 组件 | 要求 | 说明 |
|------|------|------|
| Kubernetes | ≥ 1.27 | 推荐 1.29+ |
| Helm | ≥ 3.12 | |
| GPU 驱动 | NVIDIA Driver ≥ 525 / AMD ROCm 5.4+ | |
| 存储 (PVC) | ReadWriteMany (多副本) 或 ReadWriteOnce (单副本) | 取决于 CSI 能力 |

#### GPU 调度选项（选其一或组合）

| 方案 | 组件 | 适用场景 | 推荐度 |
|------|------|---------|--------|
| 原生调度 | kube-scheduler | 单卡 / 单机多卡，简单场景 | ⭐ 起步 |
| **HAMi** | HAMi (Xiaohongshu) | GPU 共享 (1 张卡跑多个推理)、显存虚拟化 | ⭐⭐⭐ 生产 |
| **Volcano** | Volcano (Huawei) | 批量任务、Gang 调度、多机多卡、队列管理 | ⭐⭐⭐ 生产 |
| **HAMi + Volcano** | 两者叠加 | 既要 GPU 共享又要 Gang 调度，最大集群效率 | ⭐⭐⭐⭐ 高级 |

---

### Volcano + HAMi 组合使用（推荐生产环境）

**两者不冲突，可以同时安装、协同工作。**

```
┌─────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                    │
│                                                          │
│  ┌─────────────────┐    ┌─────────────────────────────┐ │
│  │ Volcano Scheduler│◄───│ HAMi (GPU virtualization)  │ │
│  │  (gang scheduling │    │  (GPU share / vGPU)       │ │
│  │   queue, priority)│   │  (CUDA_VISIBLE_DEVICES      │ │
│  └────────┬────────┘    └──────────────┬──────────────┘ │
│           │                            │                 │
│           │     ┌──────────────────────┘                 │
│           ▼     ▼                                         │
│  ┌──────────────────────────────────────────────┐        │
│  │     PodGroup (Volcano) = Gang of Pods        │        │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐       │        │
│  │  │ Worker 0│  │ Worker 1│  │ Worker N│       │        │
│  │  │ (HAMi)  │  │ (HAMi)  │  │ (HAMi)  │       │        │
│  │  │ GPU share│  │ GPU share│  │ GPU share│       │        │
│  │  └─────────┘  └─────────┘  └─────────┘       │        │
│  └──────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────┘
```

**Volcano 负责：** Pod 整体调度（要调度就一起调度，不能单独调度）、队列优先级、资源预留
**HAMi 负责：** 每张 GPU 卡的显存虚拟化、共享使用、GPU 分配

#### 安装前提

```bash
# 1. 安装 Volcano（gang 调度 + 队列）
# 参见 https://volcano.sh/en/docs/installation/
kubectl apply -f https://raw.githubusercontent.com/volcano-sh/volcano/v1.8.0/installer/volcano-development.yaml

# 2. 安装 HAMi（GPU 共享）
# 参见 https://project-hami.io/docs/installation/how-to-install/
helm install hami openhami -n hami-system --create-namespace \
  https://hami-artifact.cn-hangzhou.oss.aliyun-inc.com/c7n/helm-charts/openhami-0.0.1.tgz
# 或从 GitHub release 安装
# kubectl apply -f https://raw.githubusercontent.com/Project-HAMi/HAMi/v2.0.0/deploy/hami-device-plugin.yaml
```

#### 集群级 Volcano + HAMi 配置

```yaml
# volcano-hami-config.yaml - 应用到 volcano-scheduler
apiVersion: v1
kind: ConfigMap
metadata:
  name: volcano-scheduler-config
  namespace: volcano-system
data:
  volcano调度器配置.conf: |
    # HAMi 集成：Volcano 调度时识别 HAMi 虚拟 GPU
    enabledDentOptions:
      - name: nvidia.com/gpu
        memoryFraction: true
        memoryVolumeSize: "16Gi"
    actions: "enqueue, allocate, reclaim"
    tiers:
      - level: 0
        name: hami
        policies:
          - name: hamiallocation
            enableNUMA: true
      - level: 1
        name: normal
        policies:
          - name: drf
          - name: priority
          - name: gang
          - name: conformance
```

```bash
kubectl apply -f volcano-hami-config.yaml
# 重启 volcano-scheduler pod 生效
kubectl rollout restart deployment volcano-scheduler -n volcano-system
```

#### Volcano 队列配置

```yaml
# queues.yaml
apiVersion: scheduling.volcano.sh/v1beta1
kind: Queue
metadata:
  name: inference-queue
spec:
  weight: 10
  reclaimable: true
  minResources:
    nvidia.com/gpu: "4"
---
apiVersion: scheduling.volcano.sh/v1beta1
kind: Queue
metadata:
  name: batch-queue
spec:
  weight: 5
  reclaimable: true
  minResources:
    nvidia.com/gpu: "0"
```

```bash
kubectl apply -f queues.yaml
kubectl vc queue list
```

#### Chart 使用示例：Volcano + HAMi 同时启用

```bash
# 场景：DeepSeek-V3 多机推理，Volcano Gang 调度 + HAMi GPU 共享
# 8 机 × 8 卡，每卡共享给 2 个推理实例

helm install deepseek-volcano-hami llm-center/vllm-inference \
  \
  # === 模型配置 ===
  --set model.name=deepseek-ai/DeepSeek-V3 \
  \
  # === Volcano Gang 调度 ===
  --set scheduler.type=volcano \
  --set scheduler.volcano.queueName=inference-queue \
  --set scheduler.volcano.createPodGroup=true \
  --set scheduler.volcano.groupMinMember=8 \
  --set scheduler.volcano.minResources.cpu=128 \
  --set scheduler.volcano.minResources.memory=512Gi \
  --set scheduler.volcano.minResources.nvidia.com/gpu=8 \
  \
  # === HAMi GPU 共享 ===
  --set scheduler.hami.nodeSchedulerPolicy=bind \
  --set scheduler.hami.gpuSchedulerPolicy=share \
  --set scheduler.hami.deviceMemoryFraction=0.5 \
  \
  # === 资源请求 ===
  --set resources.limits.nvidia.com/gpu=8 \
  --set engine.tensorParallelSize=8 \
  --set engine.pipelineParallelSize=8 \
  \
  # === 生产配置 ===
  --set replicaCount=8 \
  --set terminationGracePeriodSeconds=300 \
  --set priorityClassName=high-priority \
  --set podDisruptionBudget.enabled=true \
  --set podDisruptionBudget.maxUnavailable=1 \
  --set shm.enabled=true \
  --set shm.sizeLimit=2Gi
```

#### Chart 使用示例：仅 Volcano（批量推理）

```bash
# Volcano 队列调度，无 HAMi
helm install batch-qwen llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-72B-Instruct \
  --set scheduler.type=volcano \
  --set scheduler.volcano.queueName=batch-queue \
  --set scheduler.volcano.createPodGroup=true \
  --set scheduler.volcano.groupMinMember=2 \
  --set scheduler.volcano.minResources.nvidia.com/gpu=8 \
  --set engine.tensorParallelSize=4 \
  --set replicaCount=2
```

#### Chart 使用示例：仅 HAMi（GPU 共享）

```bash
# HAMi 显存虚拟化，1 卡分给 2 个实例共用
helm install shared-qwen llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set scheduler.type=hami \
  --set scheduler.hami.nodeSchedulerPolicy=bind \
  --set scheduler.hami.gpuSchedulerPolicy=share \
  --set scheduler.hami.deviceMemoryFraction=0.5 \
  --set replicaCount=2 \
  --set resources.limits.nvidia.com/gpu=1
```

---

### NVIDIA GPU Operator 部署

生产集群建议安装 GPU Operator：

```bash
# 添加 NVIDIA Helm repo
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia \
  && helm repo update

# 安装 GPU Operator（自动安装 device-plugin / node-feature-discovery / DCGM exporter）
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator --create-namespace \
  --set devicePlugin.config.name=default \
  --set driver.enabled=false  # 已有驱动时跳过驱动安装
```

---

### Prometheus + ServiceMonitor 监控配置

```bash
# 安装 Prometheus Operator（如果没有）
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace

# 启用 ServiceMonitor（自动发现）
helm install vllm llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set metrics.enabled=true \
  --set metrics.serviceMonitor.enabled=true \
  --set metrics.serviceMonitor.interval=30s
```

---

### 存储配置建议

| 场景 | PVC 类型 | 存储类推荐 |
|------|---------|-----------|
| 单副本模型缓存 | ReadWriteOnce | `fast-ssd` / `gp3` / `local-path` |
| 多副本共享模型 | ReadWriteMany | `nfs` / `cephfs` / `juicefs` |
| Embedding 模型持久化 | ReadWriteOnce | `fast-ssd` |
| GGUF 文件 | ReadWriteOnce | `local-path` (hostPath) |


---

## 🎯 显卡选择指南

### 决策树：5 秒找到适合你的部署方案

```
你有 GPU 吗？
├── NVIDIA GPU → 你需要什么场景？
│   ├── 对话 / Embedding / Vision → vllm-inference
│   │   ├── 单卡 → model.type=chat/embedding/vision
│   │   ├── 多卡 → tensorParallelSize ≥ 2
│   │   └── Reasoning 模型 → model.reasoningParser=deepseek_r1
│   ├── RAG / Agent / 树结构推理 → sglang-inference
│   └── 混合推理 → vllm-inference + sglang-inference
├── AMD GPU → llamacpp-inference + gpuType=amd
├── Intel GPU → llamacpp-inference + gpuType=vulkan
├── 摩尔线程 → llamacpp-inference + gpuType=musa
├── Apple Silicon → llamacpp-inference + gpuType=metal
└── 无 GPU → llamacpp-inference + gpuType=none
```

---

### 显存与模型容量速查表

> **估算公式：** 所需显存 ≈ (模型参数量 × 2 bytes) + (maxModelLen × 8 bytes × KV头数比例)
> 
> **简化估算：** 16B 模型 ≈ 32GB 显存（FP16）

| 显卡 | 显存 | Qwen2.5-7B | Qwen2.5-14B | Llama-3.1-8B | Llama-3.1-70B | Llama-3.3-70B | DeepSeek-V3 | Qwen3-32B |
|------|------|-----------|-------------|-------------|--------------|--------------|-------------|-----------|
| **T4** | 16GB | ✅ FP16 | ❌ | ✅ Q4 | ❌ | ❌ | ❌ | ❌ |
| **L20** | 24GB | ✅ FP16 | ✅ FP16 | ✅ FP16 | ❌ | ❌ | ❌ | ❌ |
| **L40** | 48GB | ✅ FP16 | ✅ FP16 | ✅ FP16 | ❌ | ❌ | ❌ | ❌ |
| **A10G** | 24GB | ✅ FP16 | ✅ FP16 | ✅ FP16 | ❌ | ❌ | ❌ | ❌ |
| **A100-SXM4** | 40GB | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ TP2 | ✅ TP2 | ✅ TP2 | ❌ |
| **A100-NVL** | 80GB | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ TP1 | ✅ TP1 | ✅ TP1 | ✅ FP16 |
| **H100** | 80GB | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ TP1 | ✅ TP1 | ✅ TP1 | ✅ FP16 |
| **H200** | 80GB | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ TP1 | ✅ TP1 | ✅ TP1 | ✅ FP16 |
| **H3** | 80GB | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ TP1 | ✅ TP1 | ✅ TP1 | ✅ FP16 |
| **MI210** | 64GB | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ TP1 | ✅ TP1 | ✅ TP1 | ✅ FP16 |
| **MI250X** | 128GB | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ FP16 |
| **MI300X** | 192GB | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ FP16 |
| **Apple M3 Max** | 64GB | ✅ FP16 | ✅ FP16 | ✅ FP16 | ❌ | ❌ | ❌ | ❌ |
| **Apple M3 Ultra** | 512GB | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ FP16 | ✅ FP16 |
| **CPU (64C)** | - | ✅ Q4 | ❌ | ✅ Q4 | ❌ | ❌ | ❌ | ❌ |

> **图例：** ✅ FP16 = 原生精度可跑 | ✅ Q4 = 量化后可跑 | ❌ = 显存不足
> **TP1** = tensorParallelSize=1（单卡）| **TP2** = tensorParallelSize=2（双卡）

---

### 场景 A: NVIDIA T4 / L20 / L40 / A10G（单卡，推荐量化）

**显存范围：** 16-48GB
**推荐引擎：** vllm-inference
**推荐模型：** Qwen2.5-7B / Qwen2.5-14B / Llama-3.1-8B

> ⚠️ **14B 以上模型建议用量化**，AWQ 量化可在 24GB 内跑 14B 模型

**方案 1: FP16 原生精度（推荐 7B 模型）**
```bash
helm install qwen7b llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set model.type=chat \
  --set resources.limits.nvidia.com/gpu=1 \
  --set engine.gpuMemoryUtilization=0.90 \
  --set engine.maxModelLen=8192
```
参数说明：
- `model.name` — HuggingFace 模型 ID
- `resources.limits.nvidia.com/gpu=1` — 申请 1 张 GPU
- `engine.gpuMemoryUtilization=0.90` — 使用 90% 显存（16GB 卡的 90% = 14.4GB）
- `engine.maxModelLen=8192` — 最大上下文 8K token

**方案 2: AWQ 量化（推荐 14B 模型，24GB 显卡）**
```bash
helm install qwen14b-awq llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-14B-Instruct-AWQ \
  --set model.format=awq \
  --set resources.limits.nvidia.com/gpu=1 \
  --set engine.gpuMemoryUtilization=0.85
```
参数说明：
- `model.format=awq` — 使用 AWQ 4-bit 量化，显存占用减少 60%
- AWQ 量化模型显存估算：参数量 × 0.5GB（如 14B × 0.5GB = 7GB）

---

### 场景 B: NVIDIA A100 40GB（单卡 / 双卡）

**显存范围：** 40GB 或 80GB
**推荐引擎：** vllm-inference
**推荐模型：** Llama-3.1-70B（需 2 卡 TP2）

**单卡（40GB，推荐 30B 以下模型）**
```bash
helm install qwen32b llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-32B-Instruct \
  --set resources.limits.nvidia.com/gpu=1 \
  --set engine.gpuMemoryUtilization=0.90 \
  --set engine.maxModelLen=16384
```

**双卡 TP2（40GB×2，推荐 70B 模型）**
```bash
helm install llama70b llm-center/vllm-inference \
  --set model.name=meta-llama/Llama-3.1-70B-Instruct \
  --set engine.tensorParallelSize=2 \
  --set resources.limits.nvidia.com/gpu=2 \
  --set engine.gpuMemoryUtilization=0.85 \
  --set engine.maxModelLen=8192
```
参数说明：
- `tensorParallelSize=2` — 切分到 2 张卡，每卡负载 20GB
- `resources.limits.nvidia.com/gpu=2` — Kubernetes 申请 2 张 GPU
- ⚠️ **两卡必须在同一节点**，用 `nodeSelector` 或 `affinity` 约束

---

### 场景 C: NVIDIA A100-NVL / H100 / H200 / H3（80GB 单卡）

**显存范围：** 80GB
**推荐引擎：** vllm-inference
**推荐模型：** Llama-3.1-70B / Qwen2.5-72B / DeepSeek-V3

**单卡跑 70B（原生 FP16）**
```bash
helm install llama70b llm-center/vllm-inference \
  --set model.name=meta-llama/Llama-3.1-70B-Instruct \
  --set engine.tensorParallelSize=1 \
  --set resources.limits.nvidia.com/gpu=1 \
  --set engine.gpuMemoryUtilization=0.90 \
  --set engine.maxModelLen=8192
```

**长上下文优化（128K context）**
```bash
helm install llama70b ctx128k llm-center/vllm-inference \
  --set model.name=meta-llama/Llama-3.1-70B-Instruct \
  --set engine.tensorParallelSize=2 \
  --set resources.limits.nvidia.com/gpu=2 \
  --set engine.gpuMemoryUtilization=0.75 \
  --set engine.maxModelLen=131072
```
参数说明：
- `gpuMemoryUtilization=0.75` — 预留更多显存给 KV Cache，支持更长上下文
- `maxModelLen=131072` — 128K token 上下文

---

### 场景 D: 多机推理 4-8 卡（A100 / H100 集群）

**适用：** Llama-3.1-70B / Qwen2.5-72B / DeepSeek-V3（8B 以上模型）

**4 卡 TP4**
```bash
helm install qwen72b llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-72B-Instruct \
  --set engine.tensorParallelSize=4 \
  --set resources.limits.nvidia.com/gpu=4 \
  --set engine.gpuMemoryUtilization=0.85 \
  --set engine.pipelineParallelSize=1 \
  --set engine.maxModelLen=8192
```

**8 卡 TP8（DeepSeek-V3）**
```bash
helm install deepseekv3 llm-center/vllm-inference \
  --set model.name=deepseek-ai/DeepSeek-V3 \
  --set engine.tensorParallelSize=8 \
  --set engine.pipelineParallelSize=1 \
  --set resources.limits.nvidia.com/gpu=8 \
  --set engine.gpuMemoryUtilization=0.90 \
  --set engine.maxModelLen=16384 \
  --set replicaCount=8
```
参数说明：
- `tensorParallelSize=8` — 8 张卡切分模型权重
- `pipelineParallelSize=1` — 单机（多机改为 2 或 4）
- `replicaCount=8` — 每张卡一个副本，形成完整推理管道

---

### 场景 E: AMD MI210 / MI250X / MI300X（ROCm）

**推荐引擎：** llamacpp-inference + gpuType=amd
**推荐镜像：** `ghcr.io/ggerganov/llama.cpp:server-rocm`

> llama.cpp 是 AMD ROCm 上唯一成熟的高性能推理方案。vLLM 对 AMD 支持不完善。

**MI300X 单卡（192GB，可跑 FP16 70B）**
```bash
helm install llama70b-rocm llm-center/llamacpp-inference \
  --set model.name=TheBloke/Llama-3.1-70B-Instruct-GGUF \
  --set model.ggufFile=Llama-3.1-70B-Instruct-FP8.gguf \
  --set gpuType=amd \
  --set engine.gpuLayers=-1 \
  --set engine.contextSize=8192 \
  --set engine.parallel=4
```
参数说明：
- `gpuType=amd` — 自动使用 `server-rocm` 后端镜像
- `engine.gpuLayers=-1` — 加载所有层到 GPU（-1 = 全部）
- `model.ggufFile` — 指定具体 GGUF 文件（建议 FP8 量化）
- `engine.parallel=4` — 4 个并行序列

**MI250X 多卡 TP2**
```bash
helm install llama70b-rocm tp2 llm-center/llamacpp-inference \
  --set model.name=TheBloke/Llama-3.1-70B-Instruct-GGUF \
  --set model.ggufFile=Llama-3.1-70B-Instruct-Q4_K_M.gguf \
  --set gpuType=amd \
  --set engine.tensorParallelSize=2 \
  --set engine.gpuLayers=-1
```

---

### 场景 F: Intel Data Center GPU（Vulkan 后端）

**推荐引擎：** llamacpp-inference + gpuType=vulkan
**推荐镜像：** `ghcr.io/ggerganov/llama.cpp:server`

> Intel Data Center GPU Max (PVC) 上用 Vulkan 后端。注意：vulkan 后端为跨厂商设计，性能略低于专用 CUDA/ROCm 后端。

```bash
helm install qwen7b-intel llm-center/llamacpp-inference \
  --set model.name=TheBloke/Qwen2.5-7B-Instruct-GGUF \
  --set model.ggufFile=Qwen2.5-7B-Instruct-Q4_K_M.gguf \
  --set gpuType=vulkan \
  --set engine.gpuLayers=-1 \
  --set engine.contextSize=4096
```
参数说明：
- `gpuType=vulkan` — 自动使用 `server` 后端镜像（Vulkan 通用）
- Vulkan 驱动必须已安装（`apt-get install vulkan-tools`）

---

### 场景 G: 摩尔线程 MUSA GPU

**推荐引擎：** llamacpp-inference + gpuType=musa
**推荐镜像：** `ghcr.io/ggerganov/llama.cpp:server-musa`

> 摩尔线程 MUSA 生态正在发展中，生产使用前请确认驱动和运行时版本。

```bash
helm install qwen7b-musa llm-center/llamacpp-inference \
  --set model.name=TheBloke/Qwen2.5-7B-Instruct-GGUF \
  --set model.ggufFile=Qwen2.5-7B-Instruct-Q4_K_M.gguf \
  --set gpuType=musa \
  --set engine.gpuLayers=-1
```

---

### 场景 H: Apple Silicon M1/M2/M3/M4（Metal 后端）

**推荐引擎：** llamacpp-inference + gpuType=none（Metal 后端在 llama.cpp 里通过 vulkan 处理）
**备选方案：** Ollama 官方支持 Metal（但 K8s 场景不推荐）

> Apple Silicon GPU 在 K8s 场景有限制。推荐开发/测试用 Ollama Desktop，生产用专用 GPU 服务器。

**Mac + Docker Desktop（开发测试用）**
```bash
helm install qwen7b-metal llm-center/llamacpp-inference \
  --set model.name=TheBloke/Qwen2.5-7B-Instruct-GGUF \
  --set model.ggufFile=Qwen2.5-7B-Instruct-Q4_K_M.gguf \
  --set gpuType=none \
  --set engine.threads=12 \
  --set resources.limits.cpu=12 \
  --set resources.limits.memory=16Gi
```

---

### 场景 I: CPU Only（无 GPU）

**适用：** 开发测试、轻量模型（≤3B）、内网无 GPU 环境
**推荐引擎：** llamacpp-inference + gpuType=none
**推荐镜像：** `ghcr.io/ggerganov/llama.cpp:server-cpu`
**性能预期：** 1B 模型 ≈ 10-30 tokens/s，7B 模型 ≈ 1-3 tokens/s

```bash
# TinyLlama（推荐 CPU 入门，2GB 内存）
helm install tinyllama llm-center/llamacpp-inference \
  --set model.name=TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF \
  --set model.ggufFile=TinyLlama-1.1B-Chat-v1.0.Q4_K_M.gguf \
  --set gpuType=none \
  --set engine.threads=16 \
  --set engine.contextSize=2048 \
  --set resources.limits.cpu=16 \
  --set resources.limits.memory=4Gi

# Qwen2.5-1.5B（中等规模 CPU 模型）
helm install qwen1b5-cpu llm-center/llamacpp-inference \
  --set model.name=TheBloke/Qwen2.5-1.5B-Instruct-GGUF \
  --set model.ggufFile=Qwen2.5-1.5B-Instruct-Q4_K_M.gguf \
  --set gpuType=none \
  --set engine.threads=16 \
  --set engine.contextSize=4096 \
  --set resources.limits.cpu=16 \
  --set resources.limits.memory=8Gi
```
参数说明：
- `gpuType=none` — 自动使用 `server-cpu` 后端镜像
- `engine.threads=16` — 分配 16 核 CPU（设为物理核心数）
- CPU 模型必须使用 GGUF 量化格式

---

### 显存计算器

```
估算 vLLM 所需显存：

基础公式：
显存 = 模型参数量 × 2B (FP16) × 压缩比 + KV Cache

| 量化方式 | 压缩比 | 7B 显存 | 14B 显存 | 70B 显存 |
|---------|--------|---------|---------|---------|
| FP16 | 1.0 | 14GB | 28GB | 140GB |
| FP8 | 0.5 | 7GB | 14GB | 70GB |
| INT4 (AWQ/GPTQ) | 0.25 | 3.5GB | 7GB | 35GB |
| INT8 | 0.5 | 7GB | 14GB | 70GB |

KV Cache 估算：
KV Cache = 2 × 层数 × 每层KV头维度 × maxModelLen × 2 bytes
         ≈ 0.5GB per token per 1B parameters

示例：Qwen2.5-7B, maxModelLen=8192, FP16
KV Cache ≈ 0.5GB × 7 × 8K / 1M ≈ 3GB
总显存 ≈ 14GB + 3GB = 17GB → 需要 A10G(24GB) 或 T4(16GB)+AWQ
```

---

## 🧠 推理引擎运行逻辑

### vLLM 如何工作

```
1. Pod 启动
   └── 下载模型（HuggingFace → /root/.cache/huggingface/）
       └── vLLM Server 进程启动
           └── 加载模型到 GPU（分片 + KV Cache 预分配）
               └── 启动 HTTP Server（端口 8000）

2. 请求流程
   HTTP POST /v1/chat/completions
   → Kubernetes Service（负载均衡）
   → vLLM Pod
   → PagedAttention 管理 KV Cache
   → GPU 推理（CUDA kernel）
   → Streaming HTTP 响应

3. vLLM 内部
   ├── PagedAttention：虚拟显存管理，支持 OS 级 KV Cache
   ├── Continuous Batching：动态 batch 请求
   ├── Tensor Parallelism：多卡切分模型权重
   └── CUDA Graph：加速推理 kernel
```

### llama.cpp 如何工作

```
1. Pod 启动
   └── 下载 GGUF 模型文件
       └── llama.cpp server 进程启动
           └── 加载 GGUF 到内存/GPU
               └── 启动 HTTP Server（端口 8000）

2. llama.cpp vs vLLM 区别
   ├── llama.cpp 不预分配 KV Cache（按需分配，显存更灵活）
   ├── 支持更多量化格式（Q8_0, Q6_K, Q4_K_M 等 GGUF 格式）
   ├── 不支持 Continuous Batching（吞吐量低于 vLLM）
   └── CPU/GPU/Metal 统一接口
```

### SGLang vs vLLM 选择逻辑

```
选 vLLM：吞吐量优先、简单场景、Embedding/Vision
选 SGLang：复杂推理（RAG/Agent）、RadixAttention 缓存、树结构生成

SGLang 独有特性：
├── RadixAttention：跨请求的 KV Cache 自动复用（RAG 必备）
├── Constrained Decoding：带约束的生成（JSON Schema / Regex）
├── Chain-of-Density：文档摘要
├── Beam Search：高质量翻译
└── Tree Attention：树结构推理（代码补全）
```

### 部署逻辑总结

```
                    ┌─────────────────┐
                    │  推理请求进来     │
                    └────────┬────────┘
                             ▼
               ┌──────────────────────────────┐
               │  Kubernetes Ingress / Service │
               └──────────────┬───────────────┘
                              ▼
        ┌──────────────────────────────────────────┐
        │  选择推理引擎                           │
        │  ├── NVIDIA GPU → vLLM 或 SGLang       │
        │  ├── AMD GPU → llama.cpp (ROCm)        │
        │  ├── Intel / 摩尔线程 → llama.cpp (V)  │
        │  ├── Apple Silicon → llama.cpp (CPU)   │
        │  └── CPU Only → llama.cpp (CPU)        │
        └──────────────┬─────────────────────────┘
                       ▼
        ┌──────────────────────────────────────────┐
        │  选择部署规模                           │
        │  ├── ≤7B / 16GB → 单卡 FP16             │
        │  ├── 7B-14B / 16GB → 单卡 AWQ           │
        │  ├── 14B-30B / 40GB → 单卡 AWQ          │
        │  ├── 30B-70B / 80GB → TP2 (双卡)        │
        │  └── 70B+ / 8卡 → TP8 + PP (多机)      │
        └──────────────┬─────────────────────────┘
                       ▼
        ┌──────────────────────────────────────────┐
        │  配置调度策略                            │
        │  ├── 普通集群 → 原生调度                  │
        │  ├── GPU 共享 → HAMi                    │
        │  └── 批处理队列 → Volcano               │
        └──────────────────────────────────────────┘
```

## 快速安装（通用）

```bash
# 添加 Helm 仓库
helm repo add llm-center https://axeprpr.github.io/helm-llm-repo
helm repo update

# 一行安装（默认 Qwen2.5-7B，单卡 NVIDIA）
helm install qwen llm-center/vllm-inference  # chat by default

# 查看服务状态
kubectl get pods -l app.kubernetes.io/name=vllm-inference
kubectl logs -l app.kubernetes.io/name=vllm-inference

# OpenAI 兼容 API 调用
curl http://qwen-vllm-inference:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-7B-Instruct",
    "messages": [{"role": "user", "content": "解释量子纠缠"}]
  }'
```

---



## 📋 集群依赖速查表

| 功能 | 依赖组件 | 安装方式 |
|------|---------|---------|
| NVIDIA GPU 推理 | NVIDIA GPU Operator 或 device-plugin | `helm install gpu-operator nvidia/gpu-operator` |
| HAMi GPU 共享 | HAMi (Project-HAMi) | `kubectl apply -f hami-deploy.yaml` |
| Volcano Gang 调度 | Volcano Scheduler + CRD | `kubectl apply -f volcano-installer.yaml` |
| Volcano + HAMi 组合 | 两者同时安装 | 见上方「组合使用」章节 |
| Prometheus 监控 | Prometheus Operator | `helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack` |
| ServiceMonitor | Prometheus Operator CRD | `--set metrics.serviceMonitor.enabled=true` |
| ReadWriteMany 存储 | NFS / CephFS / JuiceFS | 对应 CSI 驱动 |
| 模型运行时下载 | Egress 到 HuggingFace + PVC | `--set persistence.enabled=true` |

> **提示：** 生产环境强烈建议同时安装 Volcano + HAMi，前者保证 Gang 调度，后者最大化 GPU 利用率。

## 场景一：单机单卡（最常见）

适合：测试、demo、小规模推理

```bash
# vLLM + Qwen2.5-7B
helm install qwen7b llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set resources.limits.nvidia.com/gpu=1 \
  --set resources.limits.memory=16Gi \
  --set engine.gpuMemoryUtilization=0.90

# SGLang + Llama3.3-70B（70B 需要更多内存）
helm install llama70b llm-center/sglang-inference \
  --set model.name=meta-llama/Llama-3.3-70B-Instruct \
  --set resources.limits.nvidia.com/gpu=2 \
  --set engine.tensorParallelSize=2 \
  --set engine.maxModelLen=8192

## 场景二：单机多卡（Tensor Parallelism）

适合：大模型推理、高并发服务

```bash
# vLLM + Qwen2.5-72B，4 卡并行
helm install qwen72b llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-72B-Instruct \
  --set engine.tensorParallelSize=4 \
  --set resources.limits.nvidia.com/gpu=4 \
  --set resources.limits.memory=64Gi \
  --set engine.gpuMemoryUtilization=0.85

# SGLang + DeepSeek-V3，8 卡
helm install deepseek llm-center/sglang-inference \
  --set model.name=deepseek-ai/DeepSeek-V3 \
  --set engine.tensorParallelSize=8 \
  --set resources.limits.nvidia.com/gpu=8 \
  --set engine.maxModelLen=32768

# vLLM + 量化模型（AWQ，节省显存）
helm install qwen-awq llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-72B-Instruct-AWQ \
  --set model.format=awq \
  --set engine.tensorParallelSize=2 \
  --set resources.limits.nvidia.com/gpu=2
```

---



### Reasoning 模型（DeepSeek R1 / Qwen3）

适合：需要思维链推理的复杂问题回答

> `--reasoning-parser` 参数让 vLLM/SGLang 正确处理思维链输出

```bash
# DeepSeek R1 Distill（7B）
helm install deepseekr1 llm-center/vllm-inference \
  --set model.name=deepseek-ai/DeepSeek-R1-Distill-Qwen-7B \
  --set model.reasoningParser=deepseek_r1 \
  --set resources.limits.nvidia.com/gpu=1

# DeepSeek R1 Distill（32B，多卡）
helm install deepseekr1-32b llm-center/vllm-inference \
  --set model.name=deepseek-ai/DeepSeek-R1-Distill-Qwen-32B \
  --set model.reasoningParser=deepseek_r1 \
  --set engine.tensorParallelSize=2 \
  --set resources.limits.nvidia.com/gpu=2
```

## 场景三：多机多卡（Pipeline Parallelism）

适合：超大模型分布式推理，需要配合 Kubernetes Pod 拓扑分布

```bash
# vLLM 分布式推理：2 机各 8 卡
helm install huge llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-72B-Instruct \
  --set engine.tensorParallelSize=8 \
  --set engine.pipelineParallelSize=2 \
  --set distributed.enabled=true \
  --set distributed.masterAddr=qwen-worker-0 \
  --set distributed.masterPort=29500 \
  --set resources.limits.nvidia.com/gpu=8 \
  --set affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].topologyKey=kubernetes.io/hostname
```

> **提示：** 多机需要 NCCL 配置，集群需支持跨节点 GPU 通信（UCX/TCP 或 NCCL-RDMA）。

---

## 场景四：Embedding 向量生成

适合：RAG 知识库、语义搜索

```bash
# BGE-M3（推荐，中英文兼顾，稀疏+稠密向量）
helm install embed llm-center/vllm-inference \
  --set model.name=BAAI/bge-m3 \
  --set engine.task=embed \
  --set resources.limits.nvidia.com/gpu=1

# Nomic Embed（英文为主）
helm install nomic llm-center/vllm-inference \
  --set model.name=nomic-ai/nomic-embed-text-v1.5 \
  --set engine.task=embed \
  --set engine.pooler=mean

# 调用示例
curl -X POST http://embed-vllm-inference:8000/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{
    "input": "什么是 Kubernetes",
    "model": "BAAI/bge-m3"
  }'
```

---

## 场景五：Rerank 重排序

适合：RAG 二阶段、先召回再精排

```bash
# BGE Reranker
helm install rerank llm-center/vllm-inference \
  --set model.name=BAAI/bge-reranker-v2-m3 \
  --set engine.task=rank \
  --set resources.limits.nvidia.com/gpu=1

# 调用示例
curl -X POST http://rerank-vllm-inference:8000/v1/rerank \
  -H "Content-Type: application/json" \
  -d '{
    "query": "量子计算原理",
    "documents": [
      "量子纠缠是量子力学现象",
      "云计算是分布式计算",
      "量子计算机利用叠加态并行计算"
    ],
    "model": "BAAI/bge-reranker-v2-m3"
  }'
```

---

## 场景六：Vision 多模态图片理解

适合：图文问答、图表分析、OCR

```bash
# LLaVA 1.5（轻量，7B）
helm install llava llm-center/vllm-inference \
  --set model.name=llava-hf/llava-1.5-7b-hf \
  --set resources.limits.nvidia.com/gpu=1 \
  --set resources.limits.memory=32Gi

# Qwen2-VL（中文强，支持更长上下文）
helm install qwenvl llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2-VL-7B-Instruct \
  --set engine.maxModelLen=8192 \
  --set resources.limits.nvidia.com/gpu=1

# InternVL2-26B（最强开源多模态）
helm install internvl llm-center/vllm-inference \
  --set model.name=OpenGVLab/InternVL2-26B \
  --set engine.tensorParallelSize=2 \
  --set resources.limits.nvidia.com/gpu=2

# 调用示例（图片 URL）
curl -X POST http://llava-vllm-inference:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llava-hf/llava-1.5-7b-hf",
    "messages": [
      {
        "role": "user",
        "content": [
          {"type": "text", "text": "描述这张图片"},
          {"type": "image_url", "image_url": {"url": "https://example.com/photo.jpg"}}
        ]
      }
    ]
  }'

# 调用示例（Base64 图片）
curl -X POST http://llava-vllm-inference:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llava-hf/llava-1.5-7b-hf",
    "messages": [{
      "role": "user",
      "content": [
        {"type": "text", "text": "这张图里有什么？"},
        {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,/9j/4AAQSkZ..."}}
      ]
    }]
  }'
```

---

## 场景七：CPU / AMD / ROCm / Vulkan / MUSA / Metal 推理

适合：没有 NVIDIA GPU 的环境，或需要 llama.cpp 灵活性的场景

**GPUStack llama.cpp 5 种后端镜像（自动匹配）：**

| 后端 | 镜像标签 | 适用硬件 | 推荐场景 |
|------|---------|---------|---------|
| CUDA | `server-cuda` | NVIDIA GPU | 生产推理 |
| ROCm | `server-rocm` | AMD GPU | AMD 显卡 |
| Vulkan | `server` | NVIDIA/AMD/Intel | 跨厂商 GPU |
| MUSA | `server-musa` | 摩尔线程 GPU | 国产 GPU |
| CPU | `server-cpu` | 无 GPU | 轻量模型、开发测试 |

```bash
# llama.cpp + AMD GPU (ROCm)
# llama.cpp + AMD ROCm GPU
helm install amd-llama llm-center/llamacpp-inference \
  --set model.name=TheBloke/Mistral-7B-Instruct-v0.3-GGUF \
  --set model.ggufFile=Mistral-7B-Instruct-v0.3-Q4_K_M.gguf \
  --set gpuType=amd

# llama.cpp + Vulkan 跨厂商 GPU (Intel/AMD/NVIDIA)
helm install vulkan-llama llm-center/llamacpp-inference \
  --set model.name=TheBloke/Qwen2.5-7B-Instruct-GGUF \
  --set gpuType=vulkan

# llama.cpp + 摩尔线程 MUSA
helm install musa-llama llm-center/llamacpp-inference \
  --set model.name=TheBloke/Qwen2.5-7B-Instruct-GGUF \
  --set gpuType=musa

# llama.cpp + 纯 CPU（小模型、开发测试）
helm install cpu-llama llm-center/llamacpp-inference \
  --set model.name=TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF \
  --set gpuType=none \
  --set engine.gpuLayers=0 \
  --set engine.threads=8
```

---



### 性能调优：Benchmark Profile 预设

参考 GPUStack profiles_config.yaml，针对不同场景优化资源分配：

```bash
# 高吞吐场景（大批量、离线推理）：1024 input + 128 output
helm install qwen-throughput llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set benchmark.type=throughput

# 低延迟场景（在线 API）：128 + 128
helm install qwen-latency llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set benchmark.type=latency

# 长上下文场景：32000 token 输入
helm install qwen-longctx llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set benchmark.type=longContext
```

## 场景八：HPA 自动扩缩容

适合：生产环境、弹性流量

```bash
# 基于 CPU 利用率扩缩容
helm install qwen-hpa llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set autoscaling.enabled=true \
  --set autoscaling.minReplicas=1 \
  --set autoscaling.maxReplicas=10 \
  --set autoscaling.targetCPUUtilizationPercentage=80 \
  --set autoscaling.targetMemoryUtilizationPercentage=80

# 基于自定义 QPS 指标（需要 Prometheus + KEDA）
helm install qwen-keda llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set autoscaling.enabled=true \
  --set autoscaling.minReplicas=1 \
  --set autoscaling.maxReplicas=20
```

---

## 场景九：模型缓存持久化

适合：避免每次启动重新下载模型，节省时间和带宽

```bash
# 使用 PVC 持久化 HuggingFace 缓存
helm install qwen-cached llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set persistence.enabled=true \
  --set persistence.size=100Gi \
  --set persistence.storageClass=fast-ssd  # 使用你的 SSD 存储类

# 或手动提前下载模型到 PVC
kubectl cp ./model-dir mynamespace/qwen-cached-vllm-inference-xxx:/model
```

---

## 场景十：Hami / Volcano 调度器

适合：GPU 集群使用自定义调度器做更优的资源分配

```bash
# 使用 Hami 调度器（小红书开源，GPU 共享增强）
helm install qwen-hami llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set scheduler.type=hami \
  --set scheduler.annotations.workloadlk.com/scheduling-gpu-type=NVIDIA-A100

# 使用 Volcano 调度器（华为云，批任务优化）
helm install qwen-volcano llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set scheduler.type=volcano \
  --set scheduler.annotations.scheduling.volcano.sh/queue-name=ml-queue
```

---

## 场景十一：本地模型文件

适合：内网环境、无外网访问、或想用微调后本地模型

```bash
# 将模型文件放到 PVC 或 NFS
# 模型目录结构: /models/my-finetuned-qwen/

# 安装，指向本地路径（不联网下载）
helm install mymodel llm-center/vllm-inference \
  --set model.name=/models/my-finetuned-qwen \
  --set model.downloadOnStartup=false \
  --set persistence.enabled=true \
  --set persistence.mountPath=/models \
  --set volumes[0].name=models \
  --set volumes[0].persistentVolumeClaim.claimName=model-storage-pvc \
  --set volumeMounts[0].name=models \
  --set volumeMounts[0].mountPath=/models
```

---

## 场景十二：Sidecar 模式（监控/日志）

适合：添加 Prometheus 采集、日志收集等 Sidecar

```bash
helm install qwen-mon llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set sidecars[0].name=prometheus \
  --set sidecars[0].image=prometheus:latest \
  --set sidecars[0].ports[0].name=http \
  --set sidecars[0].ports[0].containerPort=9090
```

---



### Model Catalog（推荐模型配置库）

启用 GPUStack 风格模型目录 ConfigMap，包含 87 个模型的推荐配置：

```bash
helm install qwen llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set modelCatalog.enabled=true
```

ConfigMap 包含：
- `chat-models.yaml` — Chat 模型推荐参数（Qwen/Llama/DeepSeek）
- `embedding-models.yaml` — Embedding/Rerank 模型
- `vision-models.yaml` — 多模态模型

查看推荐配置：
```bash
kubectl get configmap -l app.kubernetes.io/component=model-catalog
kubectl get configmap MODEL_NAME-model-catalog -o yaml
```

## 统一配置参考

所有 chart 共享以下配置结构：

```yaml
# 模型配置
model:
  name: "Qwen/Qwen2.5-7B-Instruct"   # HuggingFace 模型 ID 或本地路径
  format: auto                         # auto, fp16, bf16, fp8, int8, awq, gptq, gguf
  downloadOnStartup: true              # true=启动时联网下载, false=使用本地模型
  hfToken: ""                          # gated 模型需要（HuggingFace token）

# 引擎配置
engine:
  port: 8000
  tensorParallelSize: 1               # GPU 数量
  pipelineParallelSize: 1             # 多机并行
  maxModelLen: 8192
  gpuMemoryUtilization: 0.90
  extraArgs: ""                       # 额外 vLLM/SGLang 参数

# 资源
resources:
  limits:
    nvidia.com/gpu: "1"
    memory: "16Gi"
    cpu: "4"

# 调度器
scheduler:
  type: native                        # native, hami, volcano
  annotations: {}

# 硬件类型（决定 taint/toleration）
gpuType: nvidia                       # nvidia, amd, ascend, intel, metal

# HPA
autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80

# PVC 持久化
persistence:
  enabled: false
  storageClass: ""
  size: 50Gi
```

---

## 通用 API 调用

所有引擎提供 OpenAI 兼容 API：

```bash
# Chat Completion
curl http://SERVICE:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"...","messages":[{"role":"user","content":"..."}]}'

# Embedding
curl http://SERVICE:8000/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"input":"...","model":"..."}'

# Rerank
curl http://SERVICE:8000/v1/rerank \
  -H "Content-Type: application/json" \
  -d '{"query":"...","documents":[...]}'

# Models list
curl http://SERVICE:8000/v1/models

# Health check
curl http://SERVICE:8000/health
```

---

## 本地开发

```bash
# 安装依赖工具
make kind-install       # helm install 到 kind 集群
make lint               # helm lint 所有 chart
make template           # helm template 渲染测试
make package            # 打包 chart 为 .tgz
make index              # 生成 index.yaml
make release            # 完整发布流程
make clean              # 清理构建产物
```

---

## 推荐模型速查

| 任务 | 模型 | 引擎 | 最低显存 |
|------|------|------|---------|
| 对话 | Qwen2.5-7B-Instruct | vLLM | 16GB |
| 对话 | Llama-3.3-70B-Instruct | vLLM (4卡) | 4×20GB |
| 对话 | DeepSeek-V3 | SGLang | 8×A100 |
| Embedding | BAAI/bge-m3 | vLLM (embedding) | 8GB |
| Rerank | BAAI/bge-reranker-v2-m3 | vLLM (embedding) | 8GB |
| Vision | Qwen/Qwen2-VL-7B-Instruct | vLLM (vision) | 24GB |
| Vision | InternVL2-26B | vLLM (2卡) | 2×40GB |
| 本地运行 | TinyLlama-1.1B | llama.cpp | 2GB (CPU) |

---

## License

MIT
