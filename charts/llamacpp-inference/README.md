# vLLM Inference Helm Chart

High-throughput LLM inference using [vLLM](https://docs.vllm.ai/) engine with OpenAI-compatible API.

## Features

- 🚀 **OpenAI-compatible API** - Drop-in replacement for OpenAI API
- 🖥️ **Multi-GPU** - Tensor parallelism support (1-N GPUs)
- 🌐 **Multi-node** - Pipeline parallelism for distributed inference
- 🔧 **Flexible scheduling** - Native K8s, Hami, Volcano schedulers
- ⚡ **GPU variety** - NVIDIA, AMD, Ascend support via tolerations
- 📦 **Model formats** - HuggingFace, AWQ, GPTQ, GGUF

## Quick Start

```bash
# Add repo
helm repo add llm-center https://axeprpr.github.io/helm-llm-repo
helm repo update

# Install vLLM with Qwen2.5-7B
helm install qwen7b llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set resources.limits.nvidia.com/gpu=1

# Install with custom model
helm install mymodel llm-center/vllm-inference \
  --set model.name=meta-llama/Llama-3.3-70B-Instruct \
  --set engine.tensorParallelSize=2 \
  --set resources.limits.nvidia.com/gpu=2
```

## API Usage

```bash
# Chat completions (OpenAI compatible)
curl http://qwen7b-api:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-7B-Instruct",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'

# Health check
curl http://qwen7b-api:8000/health
```

## Key Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `model.name` | HuggingFace model ID | `Qwen/Qwen2.5-7B-Instruct` |
| `model.format` | Model format (auto/fp16/bf16/awq/gptq) | `auto` |
| `engine.port` | API server port | `8000` |
| `engine.tensorParallelSize` | GPUs per node | `1` |
| `engine.pipelineParallelSize` | Pipeline stages | `1` |
| `engine.maxModelLen` | Max sequence length | `8192` |
| `engine.gpuMemoryUtilization` | GPU memory fraction | `0.90` |
| `gpuType` | GPU vendor (nvidia/amd/ascend) | `nvidia` |
| `scheduler.type` | Scheduler (native/hami/volcano) | `native` |
| `replicaCount` | Number of replicas | `1` |
| `autoscaling.enabled` | Enable HPA | `false` |

## Multi-GPU (Tensor Parallelism)

```bash
helm install qwen72b llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-72B-Instruct \
  --set engine.tensorParallelSize=4 \
  --set resources.limits.nvidia.com/gpu=4
```

## Multi-Node (Distributed Inference)

```bash
helm install qwen72b llm-center/vllm-inference \
  --set model.name=Qwen/Qwen2.5-72B-Instruct \
  --set distributed.enabled=true \
  --set distributed.nodeList={node1,node2,node3,node4} \
  --set distributed.masterAddr=node1 \
  --set engine.tensorParallelSize=4 \
  --set engine.pipelineParallelSize=2
```

## Hami Scheduler (Xiaohongshu)

```bash
helm install qwen7b llm-center/vllm-inference \
  --set scheduler.type=hami \
  --set scheduler.annotations.nvidia.com/'{resource-name}': nvidia.com/gpu \
  --set scheduler.annotations.hami.io/'{resource-name}': nvidia.com/gpu
```

## Volcano Scheduler (Huawei)

```bash
helm install qwen7b llm-center/vllm-inference \
  --set scheduler.type=volcano \
  --set scheduler.annotations.scheduling.k8s.io/'group-name': vllm-job
```

## Model Formats

### AWQ Quantized
```yaml
model:
  name: "Qwen/Qwen2.5-7B-Instruct-AWQ"
  format: awq
```

### GPTQ Quantized
```yaml
model:
  name: "Qwen/Qwen2.5-7B-Instruct-GPTQ"
  format: gptq
```

## Resources

| GPU Count | Recommended Model | Max Model Length |
|-----------|------------------|-----------------|
| 1x H100 80GB | 70B | 32k |
| 1x A100 40GB | 30B | 16k |
| 1x A10G 24GB | 7B | 8k |
| 4x A100 40GB | 70B | 16k |
| 8x H100 80GB | 405B | 32k |
