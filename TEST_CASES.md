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

### Case 3: vLLM smoke, Volcano scheduler, single 4090

Goal:

- Deploy `charts/vllm-inference` with `scheduler.type=volcano`
- Create and use an explicit `PodGroup`
- Wait for `1/1 Running`
- Verify `/health`
- Verify `/v1/models`
- Verify one real `/v1/chat/completions`

Command:

```bash
helm upgrade --install vllm-volcano-smoke ./charts/vllm-inference \
  -n llm-test --create-namespace \
  -f ./examples/vm104-vllm-volcano-smoke-values.yaml
```

Checks:

```bash
kubectl -n llm-test rollout status deploy/vllm-volcano-smoke-vllm-inference --timeout=420s
kubectl -n llm-test get pods -l app.kubernetes.io/instance=vllm-volcano-smoke -o wide
kubectl -n llm-test get podgroup vllm-volcano-smoke-vllm-inference -o wide
curl -fsS http://<service-or-clusterip>:8000/health
curl -fsS http://<service-or-clusterip>:8000/v1/models
curl -fsS http://<service-or-clusterip>:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","messages":[{"role":"user","content":"Reply with exactly: volcano-ok"}],"max_tokens":32,"temperature":0}'
```

Pass criteria:

- `Ready=1/1`
- pod event `Scheduled` comes from `volcano`
- `PodGroup` status is `Running`
- `/health` returns `200`
- `/v1/models` returns `Qwen/Qwen2.5-0.5B-Instruct`
- chat response returns a non-empty completion

Notes:

- `runtimeClassName: nvidia` is required on this node.
- `scheduler.volcano.createPodGroup=true` must also set `scheduling.k8s.io/group-name` on the pod; this chart now does that automatically.
- For this smoke, exact-string completion is not used as pass/fail; the acceptance target is successful end-to-end inference through Volcano scheduling.

### Case 4: vLLM smoke, Volcano scheduler, custom queue

Goal:

- Deploy `charts/vllm-inference` with `scheduler.type=volcano`
- Bind the explicit `PodGroup` to `smoke-queue`
- Verify Volcano schedules the workload from the target queue
- Verify one real `/v1/chat/completions`

Command:

```bash
kubectl apply -f - <<'YAML'
apiVersion: scheduling.volcano.sh/v1beta1
kind: Queue
metadata:
  name: smoke-queue
spec:
  weight: 1
  reclaimable: true
YAML

helm upgrade --install vllm-volcano-queue ./charts/vllm-inference \
  -n llm-test --create-namespace \
  -f ./examples/vm104-vllm-volcano-custom-queue-values.yaml
```

Checks:

```bash
kubectl -n llm-test rollout status deploy/vllm-volcano-queue-vllm-inference --timeout=420s
kubectl get queue smoke-queue -o wide
kubectl -n llm-test get podgroup vllm-volcano-queue-vllm-inference -o wide
kubectl -n llm-test describe pod -l app.kubernetes.io/instance=vllm-volcano-queue
curl -fsS http://<service-or-clusterip>:8000/health
curl -fsS http://<service-or-clusterip>:8000/v1/models
curl -fsS http://<service-or-clusterip>:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","messages":[{"role":"user","content":"Reply with exactly: queue-ok"}],"max_tokens":32,"temperature":0}'
```

Pass criteria:

- `Ready=1/1`
- `Queue=smoke-queue`
- `PodGroup.spec.queue=smoke-queue`
- pod event `Scheduled` comes from `volcano`
- `/health` returns `200`
- `/v1/models` returns `Qwen/Qwen2.5-0.5B-Instruct`
- chat response returns a non-empty completion

### Case 5: vLLM smoke, Volcano scheduler, auto PodGroup

Goal:

- Deploy `charts/vllm-inference` with `scheduler.type=volcano`
- Disable explicit `PodGroup` creation
- Verify Volcano auto-creates `podgroup-<uid>`
- Verify one real `/v1/chat/completions`

Command:

```bash
helm upgrade --install vllm-volcano-auto ./charts/vllm-inference \
  -n llm-test --create-namespace \
  -f ./examples/vm104-vllm-volcano-auto-pg-values.yaml
```

Checks:

```bash
kubectl -n llm-test rollout status deploy/vllm-volcano-auto-vllm-inference --timeout=420s
kubectl -n llm-test get podgroup -o wide
kubectl -n llm-test describe pod -l app.kubernetes.io/instance=vllm-volcano-auto
curl -fsS http://<service-or-clusterip>:8000/health
curl -fsS http://<service-or-clusterip>:8000/v1/models
curl -fsS http://<service-or-clusterip>:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","messages":[{"role":"user","content":"Reply with exactly: auto-ok"}],"max_tokens":32,"temperature":0}'
```

Pass criteria:

- `Ready=1/1`
- an anonymous `podgroup-<uid>` exists and reaches `Running`
- pod event `Scheduled` comes from `volcano`
- `/health` returns `200`
- `/v1/models` returns `Qwen/Qwen2.5-0.5B-Instruct`
- chat response returns a non-empty completion

### Case 6: vLLM smoke, Volcano scheduler, gang

Goal:

- Deploy `charts/vllm-inference` with `replicaCount=2`
- Require `groupMinMember=2`
- Verify both replicas are coordinated through the same explicit `PodGroup`
- Verify one real `/v1/chat/completions`

Command:

```bash
helm upgrade --install vllm-volcano-gang ./charts/vllm-inference \
  -n llm-test --create-namespace \
  -f ./examples/vm104-vllm-volcano-gang-values.yaml
```

Checks:

```bash
kubectl -n llm-test rollout status deploy/vllm-volcano-gang-vllm-inference --timeout=600s
kubectl -n llm-test get pods -l app.kubernetes.io/instance=vllm-volcano-gang -o wide
kubectl -n llm-test get podgroup vllm-volcano-gang-vllm-inference -o wide
curl -fsS http://<service-or-clusterip>:8000/health
curl -fsS http://<service-or-clusterip>:8000/v1/models
curl -fsS http://<service-or-clusterip>:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","messages":[{"role":"user","content":"Reply with exactly: gang-ok"}],"max_tokens":32,"temperature":0}'
```

Pass criteria:

- deployment reaches `2/2 Available`
- both pods are `1/1 Running`
- `PodGroup` reaches `Running`
- `MINMEMBER=2` and `RUNNINGS=2`
- chat response returns a non-empty completion

### Case 7: Volcano queue close/open

Goal:

- Use the official `vcctl` CLI to switch queue state
- Verify the queue transitions `Open -> Closing -> Closed -> Open`
- Record the actual behavior of a new workload created while the queue is `Closed`

Command:

```bash
vcctl queue operate -n smoke-queue -a close
vcctl queue get -n smoke-queue

helm upgrade --install vllm-volcano-closed ./charts/vllm-inference \
  -n llm-test --create-namespace \
  -f ./examples/vm104-vllm-volcano-custom-queue-values.yaml

vcctl queue operate -n smoke-queue -a open
vcctl queue get -n smoke-queue
```

Checks:

```bash
vcctl queue get -n smoke-queue
kubectl -n llm-test get deploy,pods,podgroup -l app.kubernetes.io/instance=vllm-volcano-closed -o wide
kubectl -n llm-test describe podgroup vllm-volcano-closed-vllm-inference
```

Acceptance:

- `vcctl` can switch the queue between `Open`, `Closing`, `Closed`, and back to `Open`
- the behavior of a newly created workload while the queue is `Closed` must be captured as evidence

Observed result on `VM104` / Volcano `v1.10.0`:

- queue state transitions through `Open -> Closing -> Closed -> Open` succeeded
- a new workload created while the queue was `Closed` still entered `smoke-queue`
- once GPU resources were released, the workload was eventually scheduled and the `PodGroup` became `Running`

This case is therefore a behavior record for the tested Volcano version, not a proof that `Closed` hard-blocks all new workloads.

### Case 8: SGLang smoke, native scheduler, single 4090

Goal:

- Deploy `charts/sglang-inference`
- Wait for `1/1 Running`
- Verify `/model_info`
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
curl -fsS http://<service-or-clusterip>:8000/model_info
curl -fsS http://<service-or-clusterip>:8000/v1/models
curl -fsS http://<service-or-clusterip>:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","messages":[{"role":"user","content":"Reply with exactly: sglang-ok"}],"max_tokens":16,"temperature":0}'
```

Pass criteria:

- `Ready=1/1`
- `/model_info` returns `200`
- `/v1/models` returns `Qwen/Qwen2.5-0.5B-Instruct`
- chat response returns a non-empty completion

Notes:

- `runtimeClassName: nvidia` is required on this node.
- `latest-runtime` is the validated tag on `VM104`.
- This image is large. If containerd cannot pull from Docker Hub directly, pre-pull it through the configured proxy before rollout.
- On this tested build, `/health` returns `503` even when the service is usable; use `/model_info` for probes.

### Case 9: llama.cpp smoke, native scheduler, single 4090

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
