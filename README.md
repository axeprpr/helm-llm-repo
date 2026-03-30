# Helm LLM Inference Repository

一站式大模型推理部署 Helm Chart 仓库，`helm install` 一键部署各种推理引擎到 Kubernetes。

**Helm Repo：** `https://axeprpr.github.io/helm-llm-repo`

---

## 支持的引擎

| Chart | 引擎 | 适用场景 | 多 GPU | 多机 |
|-------|------|---------|--------|------|
| `vllm-inference` | vLLM | 通用高吞吐推理 | ✅ | ✅ |
| `sglang-inference` | SGLang | 树结构/RAG/Agent 推理 | ✅ | ✅ |
| `tgi-inference` | TGI (HuggingFace) | 官方生态、兼容性优先 | ✅ | ✅ |
| `llamacpp-inference` | llama.cpp | CPU/GPU、GGUF 格式、AMD/Intel | ✅ | ❌ |
| `ollama-inference` | Ollama | 快速尝鲜、最简部署 | ❌ | ❌ |
| `embedding-inference` | vLLM | Embedding 生成、Rerank | ✅ | ✅ |
| `vision-inference` | vLLM | 多模态图片理解 | ✅ | ✅ |

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
| Ollama 本地模型库 | ReadWriteOnce | `fast-ssd` |
| GGUF 文件 | ReadWriteOnce | `local-path` (hostPath) |


## 快速安装（通用）

```bash
# 添加 Helm 仓库
helm repo add llm-center https://axeprpr.github.io/helm-llm-repo
helm repo update

# 一行安装（默认 Qwen2.5-7B，单卡 NVIDIA）
helm install qwen llm-center/vllm-inference

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

# TGI + Phi-4（微软小模型，快速测试）
helm install phi llm-center/tgi-inference \
  --set model.name=microsoft/Phi-4-mini-instruct \
  --set resources.limits.nvidia.com/gpu=1
```

---

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
helm install embed llm-center/embedding-inference \
  --set model.name=BAAI/bge-m3 \
  --set engine.task=embed \
  --set resources.limits.nvidia.com/gpu=1

# Nomic Embed（英文为主）
helm install nomic llm-center/embedding-inference \
  --set model.name=nomic-ai/nomic-embed-text-v1.5 \
  --set engine.task=embed \
  --set engine.pooler=mean

# 调用示例
curl -X POST http://embed-embedding-inference:8000/v1/embeddings \
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
helm install rerank llm-center/embedding-inference \
  --set model.name=BAAI/bge-reranker-v2-m3 \
  --set engine.task=rank \
  --set resources.limits.nvidia.com/gpu=1

# 调用示例
curl -X POST http://rerank-embedding-inference:8000/v1/rerank \
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
helm install llava llm-center/vision-inference \
  --set model.name=llava-hf/llava-1.5-7b-hf \
  --set resources.limits.nvidia.com/gpu=1 \
  --set resources.limits.memory=32Gi

# Qwen2-VL（中文强，支持更长上下文）
helm install qwenvl llm-center/vision-inference \
  --set model.name=Qwen/Qwen2-VL-7B-Instruct \
  --set engine.maxModelLen=8192 \
  --set resources.limits.nvidia.com/gpu=1

# InternVL2-26B（最强开源多模态）
helm install internvl llm-center/vision-inference \
  --set model.name=OpenGVLab/InternVL2-26B \
  --set engine.tensorParallelSize=2 \
  --set resources.limits.nvidia.com/gpu=2

# 调用示例（图片 URL）
curl -X POST http://llava-vision-inference:8000/v1/chat/completions \
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
curl -X POST http://llava-vision-inference:8000/v1/chat/completions \
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

## 场景七：CPU / AMD / Intel / Metal 推理

适合：没有 NVIDIA GPU 的环境

```bash
# llama.cpp + AMD GPU (ROCm)
helm install amd-llama llm-center/llamacpp-inference \
  --set model.name=mistralai/Mistral-7B-Instruct-v0.3 \
  --set model.format=gguf \
  --set gpuType=amd \
  --set resources.limits.cpu=8 \
  --set resources.limits.memory=32Gi

# llama.cpp + Apple Metal (Mac M系列)
helm install mac-llama llm-center/llamacpp-inference \
  --set model.name=togethercomputer/LLaMA-2-7B-32K \
  --set model.format=gguf \
  --set gpuType=metal \
  --set resources.limits.cpu=4 \
  --set resources.limits.memory=16Gi

# llama.cpp + Intel GPU
helm install intel-llama llm-center/llamacpp-inference \
  --set model.name=TheBloke/Llama-2-7B-GGUF \
  --set model.format=gguf \
  --set gpuType=intel \
  --set resources.limits.cpu=8

# llama.cpp + 纯 CPU 运行（小模型）
helm install cpu-llama llm-center/llamacpp-inference \
  --set model.name=TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF \
  --set model.format=gguf \
  --set gpuType=none \
  --set resources.limits.cpu=4 \
  --set resources.limits.memory=8Gi
```

---

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
| Embedding | BAAI/bge-m3 | vLLM | 8GB |
| Rerank | BAAI/bge-reranker-v2-m3 | vLLM | 8GB |
| Vision | Qwen2-VL-7B-Instruct | vLLM | 24GB |
| Vision | InternVL2-26B | vLLM (2卡) | 2×40GB |
| 本地运行 | TinyLlama-1.1B | llama.cpp | 2GB (CPU) |

---

## License

MIT
