# SGLang Inference Helm Chart

Deploy [SGLang](https://docs.sglang.ai/) with an OpenAI-compatible API on Kubernetes.

## Quick Start

```bash
helm repo add llm-center https://axeprpr.github.io/helm-llm-repo
helm repo update

helm install sglang-smoke llm-center/sglang-inference \
  --set model.name=Qwen/Qwen2.5-7B-Instruct \
  --set scheduler.type=hami \
  --set resources.limits.nvidia\.com/gpu=1 \
  --set extraEnv[0].name=http_proxy \
  --set extraEnv[0].value=http://192.168.3.42:7890 \
  --set extraEnv[1].name=https_proxy \
  --set extraEnv[1].value=http://192.168.3.42:7890
```

## Key Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `model.name` | Hugging Face model ID or local model path | `Qwen/Qwen2.5-7B-Instruct` |
| `model.reasoningParser` | Reasoning parser (`deepseek_r1`, `qwen3`) | `""` |
| `engine.port` | OpenAI-compatible API port | `8000` |
| `engine.tensorParallelSize` | Tensor parallel size | `1` |
| `engine.pipelineParallelSize` | Pipeline parallel size | `1` |
| `engine.maxModelLen` | Maximum context length | `8192` |
| `engine.gpuMemoryUtilization` | Fraction of GPU memory to use | `0.90` |
| `scheduler.type` | Scheduler (`native`, `hami`, `volcano`) | `native` |
| `extraEnv` | Extra environment variables for proxy or auth | `[]` |
| `persistence.enabled` | Enable PVC-backed model cache | `false` |

## Notes

- The default image tag is pinned to `v0.5.9-cu129-amd64-runtime` because `lmsysorg/sglang:latest` required a newer CUDA runtime than the tested RTX 2080 Ti node driver accepted.
- `extraEnv` is the supported way to inject outbound proxy settings.
- If you use a local proxy on `192.168.3.42`, prefer lowercase `http_proxy` and `https_proxy`.
- For HAMI, provide the scheduler annotations required by your cluster.
