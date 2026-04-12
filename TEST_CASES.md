# 真实测试用例

## ENV-27 / VM104

### 用例 1：vLLM 单卡基础 Smoke

测试内容：

- Deploy `charts/vllm-inference`
- Wait for `1/1 Running`
- Verify `/health`
- Verify `/v1/models`
- Verify one real `/v1/chat/completions`
- 部署 `charts/vllm-inference`
- 等待 `1/1 Running`
- 验证 `/health`
- 验证 `/v1/models`
- 验证一次真实 `/v1/chat/completions`

测试场景：

- 单节点 `VM104`
- 原生调度器
- 单张 RTX 4090
- 用于确认 vLLM 基础部署链路、GPU 运行时和 HTTP 推理链路正常

执行命令：

```bash
helm upgrade --install vllm-smoke ./charts/vllm-inference \
  -n llm-test --create-namespace \
  -f ./examples/vm104-vllm-smoke-values.yaml
```

检查项：

```bash
kubectl -n llm-test rollout status deploy/vllm-smoke-vllm-inference --timeout=300s
kubectl -n llm-test get pods -l app.kubernetes.io/instance=vllm-smoke -o wide
curl -fsS http://<service-or-clusterip>:8000/health
curl -fsS http://<service-or-clusterip>:8000/v1/models
curl -fsS http://<service-or-clusterip>:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","messages":[{"role":"user","content":"Reply with exactly: smoke-ok"}],"max_tokens":16,"temperature":0}'
```

通过标准：

- `Ready=1/1`
- `/health` returns `200`
- `/v1/models` returns `Qwen/Qwen2.5-0.5B-Instruct`
- chat response returns a non-empty completion

场景说明：

- Do **not** set `VLLM_ENABLE_CUDA_COMPATIBILITY` on GeForce / RTX cards.
- `runtimeClassName: nvidia` is required on this node.

### 用例 2：vLLM Pod 重建自愈

测试内容：

- Delete the healthy pod
- Confirm Deployment recreates it
- Re-verify `/health`
- 删除健康 pod
- 确认 Deployment 自动重建
- 重新验证 `/health`

测试场景：

- 单节点 `VM104`
- 已有一个健康的 `vllm-smoke` deployment
- 用于验证 Deployment 自愈和服务恢复

执行命令：

```bash
kubectl -n llm-test delete pod -l app.kubernetes.io/instance=vllm-smoke
kubectl -n llm-test rollout status deploy/vllm-smoke-vllm-inference --timeout=300s
```

通过标准：

- New pod becomes `1/1 Running`
- `/health` recovers
- `/v1/models` still returns the expected model

### 用例 3：vLLM + Volcano 显式 PodGroup Smoke

测试内容：

- Deploy `charts/vllm-inference` with `scheduler.type=volcano`
- Create and use an explicit `PodGroup`
- Wait for `1/1 Running`
- Verify `/health`
- Verify `/v1/models`
- Verify one real `/v1/chat/completions`
- 用 `scheduler.type=volcano` 部署 `charts/vllm-inference`
- 创建并使用显式 `PodGroup`
- 等待 `1/1 Running`
- 验证 `/health`
- 验证 `/v1/models`
- 验证一次真实 `/v1/chat/completions`

测试场景：

- 单节点 `VM104`
- `scheduler.type=volcano`
- chart 显式创建 `PodGroup`
- 用于验证显式 `PodGroup`、Volcano 调度和真实推理请求

执行命令：

```bash
helm upgrade --install vllm-volcano-smoke ./charts/vllm-inference \
  -n llm-test --create-namespace \
  -f ./examples/vm104-vllm-volcano-smoke-values.yaml
```

检查项：

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

通过标准：

- `Ready=1/1`
- pod event `Scheduled` comes from `volcano`
- `PodGroup` status is `Running`
- `/health` returns `200`
- `/v1/models` returns `Qwen/Qwen2.5-0.5B-Instruct`
- chat response returns a non-empty completion

场景说明：

- `runtimeClassName: nvidia` is required on this node.
- `scheduler.volcano.createPodGroup=true` must also set `scheduling.k8s.io/group-name` on the pod; this chart now does that automatically.
- For this smoke, exact-string completion is not used as pass/fail; the acceptance target is successful end-to-end inference through Volcano scheduling.

### 用例 4：vLLM + Volcano 自定义队列 Smoke

测试内容：

- Deploy `charts/vllm-inference` with `scheduler.type=volcano`
- Bind the explicit `PodGroup` to `smoke-queue`
- Verify Volcano schedules the workload from the target queue
- Verify one real `/v1/chat/completions`
- 用 `scheduler.type=volcano` 部署 `charts/vllm-inference`
- 把显式 `PodGroup` 绑定到 `smoke-queue`
- 验证 Volcano 从目标 queue 调度该 workload
- 验证一次真实 `/v1/chat/completions`

测试场景：

- 单节点 `VM104`
- 预先创建 `smoke-queue`
- workload 绑定到自定义 queue
- 用于验证 `PodGroup.spec.queue`、Volcano 调度来源和真实推理请求

执行命令：

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

检查项：

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

通过标准：

- `Ready=1/1`
- `Queue=smoke-queue`
- `PodGroup.spec.queue=smoke-queue`
- pod event `Scheduled` comes from `volcano`
- `/health` returns `200`
- `/v1/models` returns `Qwen/Qwen2.5-0.5B-Instruct`
- chat response returns a non-empty completion

### 用例 5：vLLM + Volcano 自动 PodGroup Smoke

测试内容：

- Deploy `charts/vllm-inference` with `scheduler.type=volcano`
- Disable explicit `PodGroup` creation
- Verify Volcano auto-creates `podgroup-<uid>`
- Verify one real `/v1/chat/completions`
- 用 `scheduler.type=volcano` 部署 `charts/vllm-inference`
- 关闭显式 `PodGroup` 创建
- 验证 Volcano 自动创建 `podgroup-<uid>`
- 验证一次真实 `/v1/chat/completions`

测试场景：

- 单节点 `VM104`
- `scheduler.type=volcano`
- `createPodGroup=false`
- 用于验证 Volcano 自动创建匿名 `podgroup-<uid>` 的路径

执行命令：

```bash
helm upgrade --install vllm-volcano-auto ./charts/vllm-inference \
  -n llm-test --create-namespace \
  -f ./examples/vm104-vllm-volcano-auto-pg-values.yaml
```

检查项：

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

通过标准：

- `Ready=1/1`
- an anonymous `podgroup-<uid>` exists and reaches `Running`
- pod event `Scheduled` comes from `volcano`
- `/health` returns `200`
- `/v1/models` returns `Qwen/Qwen2.5-0.5B-Instruct`
- chat response returns a non-empty completion

### 用例 6：vLLM + Volcano Gang 调度 Smoke

测试内容：

- Deploy `charts/vllm-inference` with `replicaCount=2`
- Require `groupMinMember=2`
- Verify both replicas are coordinated through the same explicit `PodGroup`
- Verify one real `/v1/chat/completions`
- 用 `replicaCount=2` 部署 `charts/vllm-inference`
- 要求 `groupMinMember=2`
- 验证两个副本由同一个显式 `PodGroup` 协同推进
- 验证一次真实 `/v1/chat/completions`

测试场景：

- 单节点 `VM104`
- `replicaCount=2`
- `groupMinMember=2`
- 用于验证 Gang 语义和双副本共同推进

执行命令：

```bash
helm upgrade --install vllm-volcano-gang ./charts/vllm-inference \
  -n llm-test --create-namespace \
  -f ./examples/vm104-vllm-volcano-gang-values.yaml
```

检查项：

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

通过标准：

- deployment reaches `2/2 Available`
- both pods are `1/1 Running`
- `PodGroup` reaches `Running`
- `MINMEMBER=2` and `RUNNINGS=2`
- chat response returns a non-empty completion

### 用例 7：Volcano Queue close/open 行为记录

测试内容：

- Use the official `vcctl` CLI to switch queue state
- Verify the queue transitions `Open -> Closing -> Closed -> Open`
- Record the actual behavior of a new workload created while the queue is `Closed`
- 使用官方 `vcctl` CLI 切换 queue 状态
- 验证 queue 可以完成 `Open -> Closing -> Closed -> Open`
- 记录在 `Closed` 状态下新 workload 的真实行为

测试场景：

- 单节点 `VM104`
- 使用 Volcano 官方 `vcctl`
- 不验证“理想语义”，只记录当前版本真实行为

执行命令：

```bash
vcctl queue operate -n smoke-queue -a close
vcctl queue get -n smoke-queue

helm upgrade --install vllm-volcano-closed ./charts/vllm-inference \
  -n llm-test --create-namespace \
  -f ./examples/vm104-vllm-volcano-custom-queue-values.yaml

vcctl queue operate -n smoke-queue -a open
vcctl queue get -n smoke-queue
```

检查项：

```bash
vcctl queue get -n smoke-queue
kubectl -n llm-test get deploy,pods,podgroup -l app.kubernetes.io/instance=vllm-volcano-closed -o wide
kubectl -n llm-test describe podgroup vllm-volcano-closed-vllm-inference
```

验收要求：

- `vcctl` can switch the queue between `Open`, `Closing`, `Closed`, and back to `Open`
- the behavior of a newly created workload while the queue is `Closed` must be captured as evidence

实测结果（`VM104` / `Volcano v1.10.0`）：

- queue state transitions through `Open -> Closing -> Closed -> Open` succeeded
- a new workload created while the queue was `Closed` still entered `smoke-queue`
- once GPU resources were released, the workload was eventually scheduled and the `PodGroup` became `Running`

这条用例是当前版本行为记录，不是 “Closed 队列会硬阻塞所有新 workload” 的证明。

### 用例 8：SGLang 单卡基础 Smoke

测试内容：

- Deploy `charts/sglang-inference`
- Wait for `1/1 Running`
- Verify `/model_info`
- Verify `/v1/models`
- Verify one real `/v1/chat/completions`
- 部署 `charts/sglang-inference`
- 等待 `1/1 Running`
- 验证 `/model_info`
- 验证 `/v1/models`
- 验证一次真实 `/v1/chat/completions`

测试场景：

- 单节点 `VM104`
- 原生调度器
- 单张 RTX 4090
- 用于验证 SGLang 启动命令、探针路径和真实推理链路

执行命令：

```bash
helm upgrade --install sglang-smoke ./charts/sglang-inference \
  -n llm-test --create-namespace \
  -f ./examples/vm104-sglang-smoke-values.yaml
```

检查项：

```bash
kubectl -n llm-test rollout status deploy/sglang-smoke-sglang-inference --timeout=300s
kubectl -n llm-test get pods -l app.kubernetes.io/instance=sglang-smoke -o wide
curl -fsS http://<service-or-clusterip>:8000/model_info
curl -fsS http://<service-or-clusterip>:8000/v1/models
curl -fsS http://<service-or-clusterip>:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","messages":[{"role":"user","content":"Reply with exactly: sglang-ok"}],"max_tokens":16,"temperature":0}'
```

通过标准：

- `Ready=1/1`
- `/model_info` returns `200`
- `/v1/models` returns `Qwen/Qwen2.5-0.5B-Instruct`
- chat response returns a non-empty completion

场景说明：

- `runtimeClassName: nvidia` is required on this node.
- `latest-runtime` is the validated tag on `VM104`.
- This image is large. If containerd cannot pull from Docker Hub directly, pre-pull it through the configured proxy before rollout.
- On this tested build, `/health` returns `503` even when the service is usable; use `/model_info` for probes.

### 用例 9：llama.cpp 单卡基础 Smoke

测试内容：

- Deploy `charts/llamacpp-inference`
- Pre-download the GGUF file in an init container
- Wait for `1/1 Running`
- Verify `/health`
- Verify `/v1/models`
- Verify one real `/v1/chat/completions`
- 部署 `charts/llamacpp-inference`
- 用 initContainer 预下载 GGUF 文件
- 等待 `1/1 Running`
- 验证 `/health`
- 验证 `/v1/models`
- 验证一次真实 `/v1/chat/completions`

测试场景：

- 单节点 `VM104`
- 原生调度器
- 单张 RTX 4090
- 通过 initContainer 预下载 GGUF
- 用于验证本地模型文件路径和 OpenAI 兼容接口

执行命令：

```bash
helm upgrade --install llamacpp-smoke ./charts/llamacpp-inference \
  -n llm-test --create-namespace \
  -f ./examples/vm104-llamacpp-smoke-values.yaml
```

检查项：

```bash
kubectl -n llm-test rollout status deploy/llamacpp-smoke-llamacpp-inference --timeout=420s
kubectl -n llm-test get pods -l app.kubernetes.io/instance=llamacpp-smoke -o wide
curl -fsS http://<service-or-clusterip>:8000/health
curl -fsS http://<service-or-clusterip>:8000/v1/models
curl -fsS http://<service-or-clusterip>:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen2.5-0.5b-instruct-q4_k_m.gguf","messages":[{"role":"user","content":"Reply with exactly: llamacpp-ok"}],"max_tokens":16,"temperature":0}'
```

通过标准：

- `Ready=1/1`
- `/health` returns `200`
- `/v1/models` lists `qwen2.5-0.5b-instruct-q4_k_m.gguf`
- chat response returns a non-empty completion

场景说明：

- The in-process `--hf-repo/--hf-file` downloader was not reliable on this node and returned `common_download_file_single_online: HEAD failed`.
- The validated path on `VM104` is `initContainer + curl -L` to a shared volume, then local `-m /models/...`.
- The chart must support `initContainers.env`; this smoke depends on that.
