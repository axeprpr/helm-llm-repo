# Helm LLM Inference Repository

一站式大模型推理部署 Helm Chart 仓库，让 `helm install` 一键部署各种推理引擎。

## 支持的引擎

| Chart | 引擎 | 特点 |
|--------|------|------|
| `vllm-inference` | vLLM | 高吞吐，PagedAttention，开源最强 |
| `sglang-inference` | SGLang | RadixAttention，树结构推理快 |
| `tgi-inference` | TGI (HuggingFace) | 官方推理服务器，生态最广 |
| `llamacpp-inference` | llama.cpp | CPU/GPU 通用，GGUF 格式 |
| `ollama-inference` | Ollama | 最简单，一条命令跑模型 |

## 支持的硬件

- **NVIDIA GPU** (CUDA) - vLLM, SGLang, TGI
- **AMD GPU** (ROCm) - vLLM, llama.cpp
- **Ascend NPU** (CANN) - 华为昇腾
- **Intel GPU** (PPS) - vLLm, llama.cpp
- **Apple Metal** - llama.cpp

## 支持的调度器

- **Kubernetes Native** - 默认
- **Hami** (小红书) - GPU 调度增强
- **Volcano** (华为) - 批任务调度

## 快速开始

```bash
# 添加 Helm 仓库
helm repo add llm-center https://axeprpr.github.io/helm-llm-repo
helm repo update

# 安装 vLLM 推理服务
helm install myllm llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set resources.limits.nvidia.com/gpu=1

# 查看服务
kubectl get pods -l app.kubernetes.io/name=vllm-inference
kubectl logs -l app.kubernetes.io/name=vllm-inference

# API 调用
curl http://myllm-vllm-inference:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen2.5-7B-Instruct","messages":[{"role":"user","content":"Hello"}]}'
```

## 模型类型

| 类型 | 示例模型 | 推荐引擎 |
|------|---------|---------|
| Chat | Qwen2.5, Llama3.3, DeepSeek | vLLM, SGLang, TGI |
| Embedding | bge-m3, m3e-base | vLLM, TGI |
| Rerank | bge-reranker, colbert | vLLM |
| Vision | Qwen2-VL, LLaVA | vLLM, SGLang |
| Multimodal | InternVL, Pixtral | SGLang, TGI |

## 本地开发

```bash
# 安装 chart 到 kind 集群
make kind-install

# lint chart
make lint

# 模板渲染测试
make template

# 打包
make package

# 生成 index
make index

# 完整发布流程
make release
```

## Chart 通用配置

所有 chart 支持以下统一配置：

```yaml
model:
  name: "Qwen/Qwen2.5-7B-Instruct"
  format: auto  # auto, fp16, bf16, fp8, int8, awq, gptq, gguf

engine:
  port: 8000
  tensorParallelSize: 1
  maxModelLen: 8192
  gpuMemoryUtilization: 0.90

resources:
  limits:
    nvidia.com/gpu: "1"
    memory: "16Gi"

scheduler:
  type: native  # native, hami, volcano
  annotations: {}

gpuType: nvidia  # nvidia, amd, ascend, intel, metal

autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 10
```

## License

MIT
