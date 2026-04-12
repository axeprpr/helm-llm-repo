# Live Test Cases

## ENV-27 / VM104

### Case 1: vLLM smoke, native scheduler, single 4090

Goal:

- Deploy `charts/vllm-inference`
- Wait for `1/1 Running`
- Verify `/health`
- Verify `/v1/models`
- Verify one real `/v1/chat/completions`

Command:

```bash
helm upgrade --install vllm-smoke ./charts/vllm-inference \
  -n llm-test --create-namespace \
  -f ./examples/vm104-vllm-smoke-values.yaml
```

Checks:

```bash
kubectl -n llm-test rollout status deploy/vllm-smoke-vllm-inference --timeout=300s
kubectl -n llm-test get pods -l app.kubernetes.io/instance=vllm-smoke -o wide
curl -fsS http://<service-or-clusterip>:8000/health
curl -fsS http://<service-or-clusterip>:8000/v1/models
curl -fsS http://<service-or-clusterip>:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","messages":[{"role":"user","content":"Reply with exactly: smoke-ok"}],"max_tokens":16,"temperature":0}'
```

Pass criteria:

- `Ready=1/1`
- `/health` returns `200`
- `/v1/models` returns `Qwen/Qwen2.5-0.5B-Instruct`
- chat response returns a non-empty completion

Notes:

- Do **not** set `VLLM_ENABLE_CUDA_COMPATIBILITY` on GeForce / RTX cards.
- `runtimeClassName: nvidia` is required on this node.

### Case 2: vLLM pod recreation

Goal:

- Delete the healthy pod
- Confirm Deployment recreates it
- Re-verify `/health`

Command:

```bash
kubectl -n llm-test delete pod -l app.kubernetes.io/instance=vllm-smoke
kubectl -n llm-test rollout status deploy/vllm-smoke-vllm-inference --timeout=300s
```

Pass criteria:

- New pod becomes `1/1 Running`
- `/health` recovers
- `/v1/models` still returns the expected model

### Case 3: SGLang smoke, native scheduler, single 4090

Goal:

- Deploy `charts/sglang-inference`
- Wait for `1/1 Running`
- Verify `/get_model_info`
- Verify `/v1/models`
- Verify one real `/v1/chat/completions`

Command:

```bash
helm upgrade --install sglang-smoke ./charts/sglang-inference \
  -n llm-test --create-namespace \
  -f ./examples/vm104-sglang-smoke-values.yaml
```

Checks:

```bash
kubectl -n llm-test rollout status deploy/sglang-smoke-sglang-inference --timeout=300s
kubectl -n llm-test get pods -l app.kubernetes.io/instance=sglang-smoke -o wide
curl -fsS http://<service-or-clusterip>:8000/get_model_info
curl -fsS http://<service-or-clusterip>:8000/v1/models
curl -fsS http://<service-or-clusterip>:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","messages":[{"role":"user","content":"Reply with exactly: sglang-ok"}],"max_tokens":16,"temperature":0}'
```

Pass criteria:

- `Ready=1/1`
- `/get_model_info` returns `200`
- `/v1/models` returns `Qwen/Qwen2.5-0.5B-Instruct`
- chat response returns a non-empty completion

Notes:

- `runtimeClassName: nvidia` is required on this node.
- `latest-runtime` is the validated tag on `VM104`.
- This image is large. If containerd cannot pull from Docker Hub directly, pre-pull it through the configured proxy before rollout.
- On this tested build, `/health` returns `503` even when the service is usable; use `/get_model_info` for probes.

### Case 4: llama.cpp smoke, native scheduler, single 4090

Goal:

- Deploy `charts/llamacpp-inference`
- Pre-download the GGUF file in an init container
- Wait for `1/1 Running`
- Verify `/health`
- Verify `/v1/models`
- Verify one real `/v1/chat/completions`

Command:

```bash
helm upgrade --install llamacpp-smoke ./charts/llamacpp-inference \
  -n llm-test --create-namespace \
  -f ./examples/vm104-llamacpp-smoke-values.yaml
```

Checks:

```bash
kubectl -n llm-test rollout status deploy/llamacpp-smoke-llamacpp-inference --timeout=420s
kubectl -n llm-test get pods -l app.kubernetes.io/instance=llamacpp-smoke -o wide
curl -fsS http://<service-or-clusterip>:8000/health
curl -fsS http://<service-or-clusterip>:8000/v1/models
curl -fsS http://<service-or-clusterip>:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen2.5-0.5b-instruct-q4_k_m.gguf","messages":[{"role":"user","content":"Reply with exactly: llamacpp-ok"}],"max_tokens":16,"temperature":0}'
```

Pass criteria:

- `Ready=1/1`
- `/health` returns `200`
- `/v1/models` lists `qwen2.5-0.5b-instruct-q4_k_m.gguf`
- chat response returns a non-empty completion

Notes:

- The in-process `--hf-repo/--hf-file` downloader was not reliable on this node and returned `common_download_file_single_online: HEAD failed`.
- The validated path on `VM104` is `initContainer + curl -L` to a shared volume, then local `-m /models/...`.
- The chart must support `initContainers.env`; this smoke depends on that.
