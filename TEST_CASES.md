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

### 用例 8：Volcano VCJob Quickstart

测试内容：

- 部署 `batch.volcano.sh/v1alpha1` 的 `VCJob`
- 验证 `Pending -> Running -> Completed`
- 验证作业日志输出

测试场景：

- 单节点 `VM104`
- 使用节点本地已有的 `docker.io/calico/node:v3.25.0`
- 用于验证 Volcano 原生作业对象和基础生命周期

执行命令：

```bash
kubectl create ns volcano-single --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f ./examples/volcano-vcjob-sleep.yaml
kubectl -n volcano-single wait --for=jsonpath='{.status.state.phase}'=Completed \
  job.batch.volcano.sh/vcjob-sleep --timeout=180s
```

检查项：

```bash
kubectl -n volcano-single get job.batch.volcano.sh vcjob-sleep -o wide
kubectl -n volcano-single logs -l volcano.sh/job-name=vcjob-sleep --tail=20
```

通过标准：

- `VCJob` 状态最终为 `Completed`
- 日志包含 `vcjob-ok`

场景说明：

- 这条用例已经在 `VM104` 上通过
- 通过这条用例可以证明 Volcano 原生 `VCJob` 基础链路正常

### 用例 9：Volcano capability 队列上限

测试内容：

- 创建带 `capability.cpu=8` 的 queue
- 部署 4 个副本、每个副本申请 `4 CPU`
- 验证 queue capability 把总运行副本数压到 2

测试场景：

- 单节点 `VM104`
- `schedulerName=volcano`
- 自动 `PodGroup`
- 用于验证 queue capability 的资源上限生效

执行命令：

```bash
kubectl apply -f ./examples/volcano-capability-queue.yaml
kubectl -n volcano-single apply -f ./examples/volcano-capability-demo.yaml
```

检查项：

```bash
kubectl get queue cap-small -o yaml
kubectl -n volcano-single get pods -l app=capability-demo -o wide
```

通过标准：

- `cap-small.spec.capability.cpu=8`
- 4 个副本里只有 2 个 `Running`
- 另外 2 个保持 `Pending`

场景说明：

- 这条用例已经在 `VM104` 上通过
- 当前证据是 `2 Running + 2 Pending`

### 用例 10：Volcano reclaim 单节点试验

测试内容：

- 创建两个带 `deserved.cpu` 的 queue
- 先让 `queue-a` 占用 CPU
- 再向 `queue-b` 提交新 workload
- 观察 `reclaim` 是否会从 `queue-a` 回收资源给 `queue-b`

测试场景：

- 单节点 `VM104`
- scheduler 测试配置切到 `allocate, backfill, reclaim, preempt`
- `queue-a.deserved.cpu=8`
- `queue-b.deserved.cpu=24`

执行命令：

```bash
kubectl apply -f ./examples/volcano-capacity-queue-a.yaml
kubectl apply -f ./examples/volcano-capacity-queue-b.yaml
kubectl -n volcano-single apply -f ./examples/volcano-capacity-demo-a.yaml
kubectl -n volcano-single apply -f ./examples/volcano-capacity-demo-b.yaml
```

检查项：

```bash
kubectl get queue queue-a queue-b -o yaml
kubectl -n volcano-single get pods -l app=capacity-demo-a -o wide
kubectl -n volcano-single get pods -l app=capacity-demo-b -o wide
kubectl -n volcano-system logs deploy/volcano-scheduler --since=5m | grep -Ei 'reclaim|queue-a|queue-b'
```

当前结果：

- 调度器已经进入 `reclaim` 代码路径
- 但在当前环境和参数组合下，还没有得到正向的资源回收结果
- 当前日志关键证据是：
  - `Queue <queue-b> can not reclaim`

场景说明：

- 这条目前还是试验项，不算通过
- 后续需要继续收参数和 queue 配置

### 用例 11：Volcano preempt 单节点试验

测试内容：

- 创建高低优先级 `PriorityClass`
- 先提交低优先级 workload
- 再提交高优先级 workload
- 观察是否产生稳定的抢占行为

测试场景：

- 单节点 `VM104`
- 先试原生 `Deployment` 路径，后试 `VCJob` 路径
- scheduler 测试配置切到 `allocate, backfill, reclaim, preempt`

执行命令：

```bash
kubectl apply -f ./examples/volcano-priorityclass-low.yaml
kubectl apply -f ./examples/volcano-priorityclass-high.yaml
kubectl -n volcano-single apply -f ./examples/volcano-preempt-low.yaml
kubectl -n volcano-single apply -f ./examples/volcano-preempt-high.yaml
```

检查项：

```bash
kubectl -n volcano-single get pods -l app=preempt-low -o wide
kubectl -n volcano-single get pods -l app=preempt-high -o wide
kubectl -n volcano-system logs deploy/volcano-scheduler --since=5m | grep -Ei 'preempt|victim|priority'
```

当前结果：

- 原生 `Deployment` 路径下，scheduler 日志出现了：
  - `task ... has null jobID`
- 改成 `VCJob` 路径后，高优先级作业可以正常进入调度
- 但还没有得到稳定、可重复的“低优先级任务被驱逐”的正向证据

场景说明：

- 这条目前也是试验项，不算通过
- 下一步应继续按 Volcano 原生作业模型收敛

### 用例 12：SGLang 单卡基础 Smoke

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

### 用例 13：llama.cpp 单卡基础 Smoke

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

### 用例 14：Volcano 两节点 VCJob Gang

测试内容：

- 在 `vm104 + worker-1` 两节点环境中提交一个 `VCJob`
- 设置 `minAvailable=3`
- 每个 task 请求 `15 CPU`
- 验证单节点无法容纳全部 task 时，Volcano 仍能把整个 gang 一次性拉起
- 验证 3 个 task 会实际分布到两台节点

测试场景：

- 两节点集群
- `vm104` 已有持续运行的 GPU 推理工作负载
- `worker-1` 为纯 CPU worker
- 用于验证多节点场景下的 `gang scheduling` 不只是状态变化，而是真正跨节点整组启动

执行命令：

```bash
kubectl apply -f ./examples/volcano-multi-node-gang-vcjob.yaml
```

检查项：

```bash
kubectl -n volcano-single get job.batch.volcano.sh multi-gang-vcjob -o wide
kubectl -n volcano-single get pods -l volcano.sh/job-name=multi-gang-vcjob -o wide
kubectl -n volcano-system logs deploy/volcano-scheduler --since=10m | grep multi-gang-vcjob
```

通过标准：

- `Job.status.phase=Running`
- `RUNNINGS=3`
- 3 个 pod 全部 `1/1 Running`
- 至少 1 个 pod 落在 `worker-1`
- 至少 1 个 pod 落在 `vm104`

### 用例 15：Volcano 两节点 Binpack 观察

测试内容：

- 在两节点环境中提交 `2 replicas` 的普通 Deployment
- 每个 pod 请求 `6 CPU`
- 观察 Volcano 在现有节点负载下如何放置新 pod
- 收集 scheduler 日志和最终节点分布

测试场景：

- 两节点集群
- `vm104` 上已有较多常驻工作负载
- `worker-1` 负载较轻
- 用于验证 `binpack` 插件是否在当前版本和当前负载模型下给出稳定、可重复的正向证据

执行命令：

```bash
kubectl apply -f ./examples/volcano-multi-node-binpack-demo.yaml
```

检查项：

```bash
kubectl -n volcano-single get pods -l app=binpack-demo -o wide
kubectl -n volcano-system logs deploy/volcano-scheduler --since=10m | grep binpack-demo
```

通过标准：

- 当前不定义为正式通过项
- 需要在重复实验下得到稳定、可解释的节点聚集行为后，才升级为正式回归

### 用例 16：Volcano 两节点 Preempt

测试内容：

- 在 `vm104 + worker-1` 两节点环境中先启动低优先级 `VCJob`
- 让低优先级任务分别占住两台节点上的 CPU
- 再提交高优先级 `VCJob`
- 验证 Volcano 会驱逐低优先级 victim，并让高优先级任务最终落地运行

测试场景：

- 两节点集群
- 使用 `PriorityClass`：
  - `volcano-low=1000`
  - `volcano-high=100000`
- 低优先级作业：`2 replicas x 30 CPU`
- 高优先级作业：`1 replica x 20 CPU`
- 用于验证多节点场景下的真实 `preempt` 行为，而不是只看 Pending/Running 状态变化

执行命令：

```bash
kubectl apply -f ./examples/volcano-priorityclass-low.yaml
kubectl apply -f ./examples/volcano-priorityclass-high.yaml
kubectl -n volcano-single apply -f ./examples/volcano-multi-node-preempt-low.yaml
kubectl -n volcano-single apply -f ./examples/volcano-multi-node-preempt-high.yaml
```

检查项：

```bash
kubectl -n volcano-single get job.batch.volcano.sh preempt-low preempt-high -o wide
kubectl -n volcano-single get pods -l volcano.sh/job-name=preempt-low -o wide
kubectl -n volcano-single get pods -l volcano.sh/job-name=preempt-high -o wide
kubectl -n volcano-single get events --sort-by=.lastTimestamp | tail -n 30
kubectl -n volcano-system logs deploy/volcano-scheduler --since=10m | grep -Ei 'preempt|evict|victim|preempt-high|preempt-low'
```

通过标准：

- `preempt-low` 先达到 `Running`
- 提交 `preempt-high` 后，至少 1 个低优先级 pod 被 `Evict`
- scheduler 日志出现：
  - `Try to preempt`
  - `Evicting pod ... because of preempt`
- `preempt-high-runner-0` 最终 `1/1 Running`

场景说明：

- 这条用例已在 `VM104 + worker-1` 上通过
- 当前采集到的硬证据包括：
  - 调度器日志中的 `Try to preempt Task <volcano-single/preempt-low-runner-1> for Task <volcano-single/preempt-high-runner-0>`
  - pod 事件中的 `Evict`
  - `preempt-high-runner-0` 最终在 `worker-1` 成功运行

### 用例 17：Volcano VCJob TaskCompleted -> CompleteJob

测试内容：

- 创建包含 `ps` 和 `worker` 两类 task 的 `VCJob`
- `worker` task 配置：
  - `event: TaskCompleted`
  - `action: CompleteJob`
- 验证两个 worker 完成后，整个 `VCJob` 会直接进入 `Completed`
- 验证仍在运行的 `ps` task 会被终止

测试场景：

- 单节点 `VM104`
- `schedulerName=volcano`
- 使用 `docker.io/calico/node:v3.25.0`
- 用于验证 `tasks.policies` 在 `TaskCompleted` 事件上的真实生效

执行命令：

```bash
kubectl -n volcano-single apply -f ./examples/volcano-vcjob-taskcompleted.yaml
kubectl -n volcano-single wait --for=jsonpath='{.status.state.phase}'=Running \
  job.batch.volcano.sh/vcjob-taskcompleted --timeout=120s
sleep 10
```

检查项：

```bash
kubectl -n volcano-single get job.batch.volcano.sh vcjob-taskcompleted -o wide
kubectl -n volcano-single get pods -l volcano.sh/job-name=vcjob-taskcompleted -o wide
kubectl -n volcano-single logs -l volcano.sh/job-name=vcjob-taskcompleted --tail=20
```

通过标准：

- `vcjob-taskcompleted` 最终状态为 `Completed`
- 两个 `worker` pod 为 `Completed`
- `ps` pod 被转入 `Terminating`
- 日志包含：
  - `ps-start`
  - `worker-ok`

### 用例 18：Volcano VCJob PodFailed -> RestartJob

测试内容：

- 创建一个必然失败的 `VCJob`
- 在 job 级别配置：
  - `event: PodFailed`
  - `action: RestartJob`
- 验证失败后会执行 `RestartJob`
- 验证在 `maxRetry=1` 下，最终会进入 `Failed`

测试场景：

- 单节点 `VM104`
- `schedulerName=volcano`
- 使用 `docker.io/calico/node:v3.25.0`
- 用于验证 job 级 `policies` 在 `PodFailed` 事件上的真实生效

执行命令：

```bash
kubectl -n volcano-single apply -f ./examples/volcano-vcjob-restartjob.yaml
sleep 20
```

检查项：

```bash
kubectl -n volcano-single get job.batch.volcano.sh vcjob-restartjob -o yaml
kubectl -n volcano-single get pods -l volcano.sh/job-name=vcjob-restartjob -o wide
kubectl -n volcano-single get events --sort-by=.lastTimestamp | grep vcjob-restartjob | tail -n 20
kubectl -n volcano-single logs -l volcano.sh/job-name=vcjob-restartjob --tail=20
```

通过标准：

- `status.conditions` 中出现 `Restarting`
- 事件包含 `Start to execute action RestartJob`
- `status.retryCount=1`
- 最终 `status.state.phase=Failed`
- 日志包含 `restart-me`

## ENV-27 / VM104 Kthena

### 用例 19：Kthena 控制面安装与资源链 Smoke

测试内容：

- 安装 Kthena 控制面
- 验证 `kthena-router` 与 `kthena-controller-manager` Running
- 提交一条 `ModelBooster`
- 验证自动生成：
  - `ModelServing`
  - `ModelServer`
  - `ModelRoute`

测试场景：

- 两节点集群：`vm104 + worker-1`
- 真实 `kthena-install.yaml`
- 当前环境对大 CRD 不适合直接 `kubectl apply`
- 用于验证 Kthena 控制面和 CRD / controller 资源链是否可用

执行命令：

```bash
kubectl create namespace kthena-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create -f ./kthena-install.yaml
kubectl create namespace kthena-demo --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f ./examples/kthena/tiny-gpt2-modelbooster.yaml
```

检查项：

```bash
kubectl -n kthena-system get deploy,pods,svc -o wide
kubectl -n kthena-demo get modelbooster,modelserving,modelserver,modelroute
kubectl -n kthena-demo get pods -o wide
```

通过标准：

- `kthena-router` Running
- `kthena-controller-manager` Running
- `ModelBooster` 触发生成 `ModelServing`、`ModelServer`、`ModelRoute`
- 至少有 1 个由 `ModelBooster` 派生出来的 Pod 被创建

场景说明：

- 当前环境里大 CRD 直接 `kubectl apply` 会因 `last-applied` 注解过大失败
- 这条用例验证的是安装链路和控制器联动，不是最终 serving 稳定性

### 用例 20：Kthena tiny-gpt2 downloader / runtime Smoke

测试内容：

- 提交 `tiny-gpt2` 的 `ModelBooster`
- 验证 downloader 完成模型下载
- 验证 runtime 启动并通过 `/health`

测试场景：

- 两节点集群：`vm104 + worker-1`
- 使用 `sshleifer/tiny-gpt2` 缩小模型体积
- 用于隔离 Kthena 本身链路，不被大模型下载时间主导

执行命令：

```bash
kubectl -n kthena-demo apply -f ./examples/kthena/tiny-gpt2-modelbooster.yaml
```

检查项：

```bash
kubectl -n kthena-demo get pods -o wide
kubectl -n kthena-demo logs <pod-name> -c downloader --tail=100
kubectl -n kthena-demo logs <pod-name> -c runtime --tail=100
kubectl -n kthena-demo describe pod <pod-name>
```

通过标准：

- downloader 日志里模型文件下载完成
- runtime 日志里出现服务启动
- runtime `/health` 返回 `200`

场景说明：

- 这条用例当前已经拿到 downloader 和 runtime 的正向证据
- 当前还没有把 `engine` 长时间稳定收敛到完整 Ready，因此不把它标记为“完整 serving 通过”
