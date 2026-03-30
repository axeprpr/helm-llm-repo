# Helm LLM Inference 仓库

一行命令，在 Kubernetes 上部署大模型推理服务。支持 vLLM、SGLang、llamacpp，覆盖 NVIDIA / AMD / Intel / 摩尔线程 / CPU 全硬件。

**Helm 仓库：** https://axeprpr.github.io/helm-llm-repo

---

## 环境准备



---

## 快速部署



---

## 选择器：我的情况用哪个？

| 硬件 | 场景 | Chart | 关键参数 |
|------|------|--------|---------|
| NVIDIA GPU | 对话 | vllm-inference | model.type=chat |
| NVIDIA GPU | Embedding | vllm-inference | model.type=embedding |
| NVIDIA GPU | Vision 多模态 | vllm-inference | model.type=vision |
| NVIDIA GPU | Reasoning 思维链 | vllm-inference | model.reasoningParser= |
| NVIDIA 多卡 | 70B 大模型 | vllm-inference | tensorParallelSize=2+ |
| AMD GPU | 任意模型 | llamacpp-inference | gpuType=amd |
| Intel / 摩尔线程 | 任意模型 | llamacpp-inference | gpuType=vulkan/musa |
| 无 GPU | 小模型 3B | llamacpp-inference | gpuType=none |
| NVIDIA GPU | RAG 精排 | vllm-inference | embeddingTask=rank |
| NVIDIA GPU | RAG Agent | sglang-inference | 默认参数 |

## 场景一：NVIDIA GPU + 对话



适用于：T4 / A10G / A100 / H100 等任意 NVIDIA 显卡。

---

## 场景二：Embedding 向量生成



适用于：RAG 知识库向量检索。

---

## 场景三：Vision 多模态（看图）



适用于：图文问答。需要 A100 以上（24GB+ 显存）。

---

## 场景四：Reasoning 模型（DeepSeek R1）



---

## 场景五：多卡 70B 大模型



---

## 场景六：AMD GPU（ROCm）



---

## 场景七：Intel / 摩尔线程 GPU



---

## 场景八：纯 CPU 推理



---

## 场景九：RAG 精排（Rerank）



---

## 场景十：SGLang（RAG Agent / 树结构）



选 SGLang 而非 vLLM：RAG RadixAttention / Agent 多轮 / Guided Decoding / Beam Search。

---

## 统一配置参数表

### 全局参数（所有 Chart）

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| replicaCount | int | 1 | Pod 副本数 |
| resources.limits.nvidia.com/gpu | int | 1 | GPU 数量 |
| resources.limits.memory | string | 16Gi | 内存上限 |
| autoscaling.enabled | bool | false | 开启 HPA |
| autoscaling.minReplicas | int | 1 | 最小副本数 |
| autoscaling.maxReplicas | int | 10 | 最大副本数 |
| autoscaling.targetCPUUtilizationPercentage | int | 80 | CPU 扩容阈值 |
| persistence.enabled | bool | false | PVC 模型缓存 |
| persistence.size | string | 50Gi | PVC 大小 |
| metrics.enabled | bool | true | Prometheus 指标 |
| metrics.serviceMonitor.enabled | bool | false | ServiceMonitor |
| ingress.enabled | bool | false | 开启 Ingress |

### vllm-inference 专属

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| model.name | string | Qwen2.5-7B | HuggingFace 模型 ID |
| model.type | string | chat | chat / embedding / vision |
| model.format | string | auto | auto / fp16 / fp8 / awq / gptq |
| model.reasoningParser | string | - | deepseek_r1 / qwen3 |
| engine.tensorParallelSize | int | 1 | Tensor 并行卡数 |
| engine.maxModelLen | int | 8192 | 最大上下文长度 |
| engine.gpuMemoryUtilization | float | 0.90 | GPU 显存比例 |
| engine.embeddingTask | string | embed | embed / rank |
| benchmark.type | string | - | throughput / latency / longContext |
| scheduler.type | string | native | native / hami / volcano |
| scheduler.volcano.queueName | string | - | Volcano 队列名 |
| scheduler.hami.gpuSharePercent | int | 50 | HAMi 共享比例 |

### llamacpp-inference 专属

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| model.name | string | ...-GGUF | GGUF 模型 ID |
| model.ggufFile | string | - | GGUF 文件名 |
| gpuType | string | nvidia | nvidia / amd / vulkan / musa / none |
| engine.gpuLayers | int | -1 | GPU 层数（-1=全部）|
| engine.contextSize | int | 8192 | 上下文长度 |

### sglang-inference 专属

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| model.name | string | Llama-3.1-8B | HuggingFace 模型 ID |
| model.reasoningParser | string | - | 思维链解析器 |
| engine.maxModelLen | int | 8192 | 最大上下文长度 |
| engine.tensorParallelSize | int | 1 | Tensor 并行 |

---

## 常见问题

**Q1：Pod 一直是 Pending？**


**Q2：显存不够（OOM）？**


**Q3：模型每次重新下载太慢？**


**Q4：外部怎么访问？**


**Q5：Prometheus 监控？**


**Q6：Volcano 批量调度？**


**Q7：HPA 自动扩缩容？**


**Q8：删除部署？**


---

## 附录 A：核心概念

<details>
<summary>显存和内存有什么区别？</summary>
显存是显卡上的内存，内存是主板上的内存。跑 LLM 靠显存。7B FP16 = 14GB 显存。
</details>

<details>
<summary>Tensor Parallelism 是什么？</summary>
模型太大一张卡装不下时，把模型切分到多张卡。70B FP16 需要 140GB → TP4（4张卡）每卡 35GB。
</details>

<details>
<summary>量化是什么？</summary>
把 FP16 压缩成 INT8 / Q4，减少显存 50-75%。常用：AWQ（NVIDIA）、GGUF Q4_K_M（llamacpp）。
</details>

<details>
<summary>vLLM vs SGLang vs llama.cpp 怎么选？</summary>
vLLM：吞吐最高，NVIDIA 首选。SGLang：RAG/Agent 场景。llamacpp：全硬件支持（AMD/Intel/CPU）。
</details>

<details>
<summary>什么是 HPA？</summary>
HorizontalPodAutoscaler，CPU/内存超过阈值时自动增减 Pod 副本。
</details>

<details>
<summary>什么是 Helm？</summary>
Kubernetes 包管理器，helm install qwen vllm-inference --set model.name=Qwen...
</details>

---

## 附录 B：显卡与模型容量

| 显卡 | 显存 | 7B | 14B | 70B | 推荐 |
|------|------|-----|------|------|------|
| T4 | 16GB | FP16 | - | - | AWQ Q4 |
| L20/L40 | 24-48GB | FP16 | FP16 | - | AWQ Q4 |
| A10G | 24GB | FP16 | FP16 | - | AWQ Q4 |
| A100 40GB | 40GB | FP16 | FP16 | TP2 | FP8 |
| A100 80GB / H100 | 80GB | FP16 | FP16 | FP16 | FP16 |
| AMD MI300X | 192GB | FP16 | FP16 | FP16 | FP16 |
| CPU | - | - | - | - | GGUF Q4 |
