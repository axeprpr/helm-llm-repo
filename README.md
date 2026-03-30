# Helm LLM Inference 仓库

一行命令，在 Kubernetes 上部署大模型推理服务。支持 vLLM、SGLang、llama.cpp，覆盖 NVIDIA/AMD/Intel/摩尔线程/CPU 全硬件。

**Helm 仓库：** `https://axeprpr.github.io/helm-llm-repo`

---

## 环境准备

### 第一步：确认集群有 GPU

```bash
# 确认 Kubernetes 可用
kubectl get nodes

# 确认 NVIDIA 驱动正常
kubectl run nvidia-smi --rm -it --image=nvidia/cuda:12.1.0-base -- nvidia-smi
# 能看到显卡型号和显存则正常

# 确认 Helm 已安装
helm version
```

### 第二步：添加本仓库

```bash
helm repo add llm-center https://axeprpr.github.io/helm-llm-repo
helm repo update
```

---

## 快速部署（一行命令跑起来）

```bash
# 部署 Qwen2.5-7B 对话模型（需要 1 张 NVIDIA 显卡，16GB 以上显存）
helm install qwen llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set model.type=chat \
  --set resources.limits.nvidia.com/gpu=1

# 验证
kubectl get pods -l app.kubernetes.io/name=vllm-inference
kubectl logs -l app.kubernetes.io/name=vllm-inference
```

---

## 选择器：我的情况该用哪个？

根据你的硬件和场景，找对应行：

| 硬件 | 场景 | Chart | 模型类型参数 | 快速命令 |
|------|------|-------|------------|---------|
| NVIDIA GPU | 对话 | `vllm-inference` | `model.type=chat` | 见场景一 |
| NVIDIA GPU | RAG Embedding | `vllm-inference` | `model.type=embedding` | 见场景二 |
| NVIDIA GPU | 多模态（看图） | `vllm-inference` | `model.type=vision` | 见场景三 |
| NVIDIA GPU | Reasoning 模型 | `vllm-inference` | + `model.reasoningParser` | 见场景四 |
| NVIDIA 多卡 | 70B 以上模型 | `vllm-inference` | `engine.tensorParallelSize=2+` | 见场景五 |
| AMD GPU | 任意模型 | `llamacpp-inference` | `gpuType=amd` | 见场景六 |
| Intel / 摩尔线程 GPU | 任意模型 | `llamacpp-inference` | `gpuType=vulkan` | 见场景七 |
| 无 GPU | 小模型（≤3B） | `llamacpp-inference` | `gpuType=none` | 见场景八 |
| NVIDIA GPU | RAG 精排 | `vllm-inference` | `engine.embeddingTask=rank` | 见场景九 |
| SGLang 特有场景 | RAG / Agent / 树结构 | `sglang-inference` | 无需特殊参数 | 见场景十 |

---

## 场景一：NVIDIA GPU + 对话模型

```bash
helm install qwen llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set model.type=chat \
  --set resources.limits.nvidia.com/gpu=1
```

**适用：** T4 / A10G / A100 / H100 等 NVIDIA 显卡，7B 参数模型。

---

## 场景二：NVIDIA GPU + RAG Embedding

```bash
helm install embed llm-center/vllm-inference \
  --set model.name=BAAI/bge-m3 \
  --set model.type=embedding \
  --set engine.embeddingTask=embed
```

**适用：** 知识库向量检索。模型 BGE-M3 支持中英文和稀疏/稠密向量。

---

## 场景三：NVIDIA GPU + 多模态（看图）

```bash
helm install vision llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2-VL-7B-Instruct \
  --set model.type=vision \
  --set engine.maxModelLen=16384
```

**适用：** 图文问答、图表理解。需要 A100 以上（24GB+ 显存）。

---

## 场景四：NVIDIA GPU + Reasoning 模型（DeepSeek R1）

```bash
helm install deepseekr1 llm-center/vllm-inference \
  --set model.name=deepseek-ai/DeepSeek-R1-Distill-Qwen-7B \
  --set model.type=chat \
  --set model.reasoningParser=deepseek_r1
```

**适用：** 数学证明、代码生成等复杂推理任务。

---

## 场景五：NVIDIA 多卡 + 70B 大模型

```bash
# 单卡 H100/H200 80GB（直接装得下 70B）
helm install llama70b llm-center/vllm-inference \
  --set model.name=meta-llama/Llama-3.1-70B-Instruct \
  --set model.type=chat

# A100 40GB × 2 卡（需要切分）
helm install llama70b-tp2 llm-center/vllm-inference \
  --set model.name=meta-llama/Llama-3.1-70B-Instruct \
  --set engine.tensorParallelSize=2 \
  --set resources.limits.nvidia.com/gpu=2
```

| 显卡 | 显存 | 70B 模型 | 配置 |
|------|------|---------|------|
| H100/H200/H3 | 80GB | ✅ FP16 原生 | 单卡，tensorParallelSize=1 |
| A100 40GB | 40GB | ✅ TP2 | 两卡，tensorParallelSize=2 |
| A100 40GB | 40GB | ✅ Q4 量化 | 单卡，--set model.format=awq |
| T4 16GB | 16GB | ❌ | 显存不足 |

---

## 场景六：AMD GPU（ROCm）

```bash
helm install llama-amd llm-center/llamacpp-inference \
  --set model.name=TheBloke/Llama-3.1-70B-Instruct-GGUF \
  --set model.ggufFile=Llama-3.1-70B-Instruct-Q4_K_M.gguf \
  --set gpuType=amd \
  --set engine.gpuLayers=-1
```

**适用：** AMD MI210 / MI250X / MI300X。llamacpp 是 AMD 上唯一成熟的高性能推理方案。

---

## 场景七：Intel / 摩尔线程 GPU

```bash
# Intel Data Center GPU Max（Vulkan 后端）
helm install llama-intel llm-center/llamacpp-inference \
  --set model.name=TheBloke/Qwen2.5-7B-Instruct-GGUF \
  --set gpuType=vulkan \
  --set engine.gpuLayers=-1

# 摩尔线程 MUSA
helm install llama-musa llm-center/llamacpp-inference \
  --set model.name=TheBloke/Qwen2.5-7B-Instruct-GGUF \
  --set gpuType=musa \
  --set engine.gpuLayers=-1
```

---

## 场景八：纯 CPU 推理（无 GPU）

```bash
# TinyLlama（1B，最适合 CPU）
helm install tinyllama llm-center/llamacpp-inference \
  --set model.name=TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF \
  --set model.ggufFile=TinyLlama-1.1B-Chat-v1.0.Q4_K_M.gguf \
  --set gpuType=none \
  --set engine.threads=16
```

**注意：** CPU 上只能跑 ≤3B 的量化模型，7B 模型速度极慢（1-3 tokens/s）。

---

## 场景九：RAG 精排（Rerank）

```bash
helm install rerank llm-center/vllm-inference \
  --set model.name=BAAI/bge-reranker-v2-m3 \
  --set model.type=embedding \
  --set engine.embeddingTask=rank
```

**适用：** RAG 两阶段中的精排步骤。先召回 100 条，再精排选出 Top 10。

---

## 场景十：SGLang（RAG Agent / 树结构推理）

```bash
helm install agent llm-center/sglang-inference \
  --set model.name=meta-llama/Llama-3.1-8B-Instruct
```

**选 SGLang 而非 vLLM 的场景：**
- RAG 需要跨请求的 KV Cache 复用（RadixAttention）
- Agent 多轮对话，树结构生成
- 需要 Guided Decoding（强制 JSON Schema 输出）
- Beam Search 高质量翻译

---

## 统一配置参数表

### 全局参数（所有 Chart 适用）

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `replicaCount` | int | 1 | Pod 副本数 |
| `resources.limits.nvidia.com/gpu` | int | 1 | GPU 数量 |
| `resources.limits.memory` | string | 16Gi | 内存限制 |
| `autoscaling.enabled` | bool | false | 开启 HPA 自动扩缩 |
| `autoscaling.minReplicas` | int | 1 | 最小副本数 |
| `autoscaling.maxReplicas` | int | 10 | 最大副本数 |
| `autoscaling.targetCPUUtilizationPercentage` | int | 80 | CPU 触发阈值 |
| `persistence.enabled` | bool | false | 开启 PVC 模型缓存 |
| `persistence.size` | string | 50Gi | PVC 存储大小 |
| `metrics.enabled` | bool | true | 开启 Prometheus 指标 |
| `metrics.serviceMonitor.enabled` | bool | false | 开启 ServiceMonitor |
| `ingress.enabled` | bool | false | 开启 Ingress |
| `service.type` | string | ClusterIP | Service 类型 |
| `podDisruptionBudget.enabled` | bool | false | 开启 PDB |
| `priorityClassName` | string | "" | Pod 优先级 |

### vllm-inference 专属参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `model.name` | string | Qwen/Qwen2.5-7B-Instruct | HuggingFace 模型 ID |
| `model.type` | string | chat | chat / embedding / vision |
| `model.format` | string | auto | auto / fp16 / fp8 / int8 / awq / gptq |
| `model.downloadOnStartup` | bool | true | 启动时下载模型 |
| `model.hfToken` | string | "" | HuggingFace Token（gated 模型需要）|
| `model.reasoningParser` | string | "" | deepseek_r1 / qwen3（思维链模型）|
| `engine.tensorParallelSize` | int | 1 | Tensor 并行卡数 |
| `engine.pipelineParallelSize` | int | 1 | Pipeline 并行节点数 |
| `engine.maxModelLen` | int | 8192 | 最大上下文长度 |
| `engine.gpuMemoryUtilization` | float | 0.90 | GPU 显存使用比例 |
| `engine.embeddingTask` | string | embed | embed / rank（embedding 专用）|
| `engine.poolerType` | string | mean | mean / cls / last_token |
| `benchmark.type` | string | "" | throughput / latency / longContext |
| `scheduler.type` | string | native | native / hami / volcano |
| `scheduler.volcano.queueName` | string | "" | Volcano 队列名称 |
| `scheduler.hami.gpuSharePercent` | int | 50 | HAMi GPU 共享比例 |

### llamacpp-inference 专属参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `model.name` | string | TheBloke/...-GGUF | GGUF 模型 ID |
| `model.ggufFile` | string | "" | 具体 GGUF 文件名 |
| `gpuType` | string | nvidia | nvidia / amd / vulkan / musa / none |
| `engine.contextSize` | int | 8192 | 上下文长度 |
| `engine.gpuLayers` | int | -1 | GPU 加载层数（-1=全部）|
| `engine.batchSize` | int | 512 | 批处理大小 |
| `engine.parallel` | int | 4 | 并行序列数 |

### sglang-inference 专属参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `model.name` | string | meta-llama/Llama-3.1-8B-Instruct | 模型 ID |
| `model.reasoningParser` | string | "" | 思维链解析器 |
| `engine.maxModelLen` | int | 8192 | 最大上下文长度 |
| `engine.tensorParallelSize` | int | 1 | Tensor 并行 |
| `engine.enableChunkedPrefill` | bool | true | 分块预填充，省显存 |

---

## 常见问题

**Q1：Pod 一直是 Pending？**
```bash
kubectl describe pod -l app.kubernetes.io/name=vllm-inference
# 常见原因：节点没有 GPU、存储未就绪
```

**Q2：显存不够（OOM）？**
```bash
# 方案1：量化模型（减少 60% 显存）
--set model.format=awq

# 方案2：减小上下文
--set engine.maxModelLen=4096

# 方案3：换更小的模型
--set model.name=Qwen/Qwen2.5-3B-Instruct
```

**Q3：如何持久化模型（不用每次重下）？**
```bash
--set persistence.enabled=true \
--set persistence.size=100Gi \
--set persistence.storageClass=fast-ssd
```

**Q4：怎么从集群外部访问？**
```bash
--set service.type=LoadBalancer
# 或配置 Ingress
--set ingress.enabled=true \
--set ingress.className=nginx \
--set ingress.hosts[0].host=qwen.example.com
```

**Q5：如何开启 Prometheus 监控？**
```bash
--set metrics.enabled=true \
--set metrics.serviceMonitor.enabled=true
# 需要 Prometheus Operator 在集群中
```

**Q6：Volcano 批量调度怎么做？**
```bash
--set scheduler.type=volcano \
--set scheduler.volcano.queueName=inference-queue
# 需要提前创建 Queue CRD
```

**Q7：如何扩缩容？**
```bash
# 自动（HPA）
--set autoscaling.enabled=true \
--set autoscaling.minReplicas=1 \
--set autoscaling.maxReplicas=10

# 手动
kubectl scale deployment qwen-vllm-inference --replicas=3
```

**Q8：删除部署？**
```bash
helm uninstall qwen
kubectl delete pvc qwen-model-cache  # 如果有 PVC
```

---

## 附录 A：概念解释

<details>
<summary>什么是 Helm？为什么要用它？</summary>

Helm 是 Kubernetes 的包管理器，类似 apt（Ubuntu 软件包）或 pip（Python 包）。

**不用 Helm：** `kubectl apply` 逐个部署 yaml，容易版本混乱。  
**用 Helm：** `helm install qwen vllm-inference --set model.name=Qwen...` 一行搞定，可升级、可回滚。

</details>

<details>
<summary>显存（VRAM）和内存（RAM）的区别？</summary>

显存是显卡上的内存，内存是主板上的内存。跑 LLM 靠显存，不是内存。

估算公式：7B 参数（FP16）≈ 14GB 显存。显存不够会报 OOM 错误。

</details>

<details>
<summary>Tensor Parallelism（TP）是什么？</summary>

模型太大一张卡装不下时，把模型权重切分到多张卡上。

示例：Llama-70B 需要 140GB，单卡 A100 40GB 不够 → TP4（4张卡）每卡 35GB。

</details>

<details>
<summary>量化（Quantization）是什么？</summary>

把 FP16（16位浮点）压缩成 INT8/Q4（8位/4位），减少显存占用 50-75%。

常用量化：AWQ（推荐 NVIDIA）、GPTQ（推荐）、GGUF Q4_K_M（推荐 llama.cpp）。

</details>

<details>
<summary>vLLM vs SGLang vs llama.cpp 怎么选？</summary>

- **vLLM：** 吞吐最高，NVIDIA GPU 首选，支持 Embedding/Vision
- **SGLang：** RAG/Agent 场景，支持 RadixAttention，支持 Guided Decoding
- **llamacpp：** 全硬件支持（AMD/Intel/MUSA/CPU），支持 GGUF 量化格式

</details>

<details>
<summary>什么是 HPA？</summary>

HorizontalPodAutoscaler，根据 CPU/内存使用率自动增减 Pod 副本数。

示例：CPU > 80% 时自动扩容到 10 副本，CPU < 30% 时自动缩容到 1 副本。

</details>

---

## 附录 B：显卡与模型容量对照表

| 显卡 | 显存 | FP16 7B | FP16 14B | FP16 70B | 推荐量化 |
|------|------|---------|---------|---------|---------|
| T4 | 16GB | ✅ | ❌ | ❌ | AWQ Q4 |
| L20/L40 | 24-48GB | ✅ | ✅ | ❌ | AWQ Q4 |
| A10G | 24GB | ✅ | ✅ | ❌ | AWQ Q4 |
| A100 40GB | 40GB | ✅ | ✅ | TP2 ✅ | FP8 |
| A100 80GB | 80GB | ✅ | ✅ | ✅ | FP16 |
| H100/H200/H3 | 80GB | ✅ | ✅ | ✅ | FP16 |
| AMD MI300X | 192GB | ✅ | ✅ | ✅ | FP16 |
| AMD MI250X | 128GB | ✅ | ✅ | ✅ | FP16 |
| Apple M3 Ultra | 512GB | ✅ | ✅ | ✅ | FP16 |
| CPU (16核) | - | ❌ | ❌ | ❌ | GGUF Q4 |
