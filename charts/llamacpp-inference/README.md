# llama.cpp Inference Helm Chart

Deploy [llama.cpp](https://github.com/ggml-org/llama.cpp) server builds on Kubernetes for NVIDIA, AMD, Vulkan, MUSA, or CPU-only environments.

## Quick Start

```bash
helm repo add llm-center https://axeprpr.github.io/helm-llm-repo
helm repo update

helm install llamacpp-smoke llm-center/llamacpp-inference \
  --set model.name=Qwen/Qwen2.5-0.5B-Instruct-GGUF \
  --set model.ggufFile=qwen2.5-0.5b-instruct-q4_k_m.gguf \
  --set gpuType=nvidia \
  --set scheduler.type=hami \
  --set extraEnv[0].name=http_proxy \
  --set extraEnv[0].value=http://192.168.3.42:7890 \
  --set extraEnv[1].name=https_proxy \
  --set extraEnv[1].value=http://192.168.3.42:7890
```

## Key Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `gpuType` | Backend selector (`nvidia`, `amd`, `vulkan`, `musa`, `intel`, `none`) | `nvidia` |
| `model.name` | Hugging Face repo or local GGUF path | `TheBloke/Qwen2.5-7B-Instruct-GGUF` |
| `model.ggufFile` | GGUF filename within the repo | `""` |
| `model.downloadOnStartup` | Download from Hugging Face on startup | `true` |
| `engine.contextSize` | Context window size | `8192` |
| `engine.gpuLayers` | Number of GPU layers to offload | `-1` |
| `engine.parallel` | Parallel request slots | `4` |
| `engine.batchSize` | Prompt batch size | `512` |
| `extraEnv` | Extra environment variables for proxy or auth | `[]` |
| `persistence.mountPath` | Model cache mount path | `/root/.cache/huggingface` |

## Notes

- With `image.autoBackend=true`, the chart selects the correct llama.cpp image tag from `gpuType`.
- `extraEnv` is the supported way to inject outbound proxy settings.
- If you use a local proxy on `192.168.3.42`, prefer lowercase `http_proxy` and `https_proxy`.
