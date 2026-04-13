# HAMi 测试整理（中文）

更新时间：2026-04-12

适用仓库：`helm-llm-repo`

目标：把当前仓库里关于 `vLLM / llama.cpp / SGLang` 与 HAMi 的真实验证情况、现有阻塞点，以及它和 Volcano 的边界关系整理清楚。

---

## 1. 先讲结论

当前结论分三层：

1. **Chart 层已经支持 HAMi**
   - 三个推理 Chart 都支持 `scheduler.type=hami`
2. **真实运行层已有正向证据**
   - `llama.cpp + HAMi` 有真实成功证据
   - `vLLM + HAMi` 在 `ENV-27 / VM104` 上已拿到真实调度、GPU UUID 分配、`/v1/models` 和 `/v1/chat/completions` 证据
   - 但这条通过路径目前仍是**有条件通过**，依赖显式绑定空闲 GPU UUID 和更保守的运行参数
3. **HAMi 和 Volcano 不是简单“完全冲突”**
   - 但在同一条 GPU 虚拟化路径上，HAMi vGPU 和 Volcano vGPU 不能简单叠加

---

## 2. 当前仓库里 HAMi 到了哪一步

### 2.1 已有能力

- `scheduler.type=hami` 已进入三个推理 Chart
- `vllm-inference` 已额外渲染：
  - `hami.io/node-scheduler-policy`
  - `hami.io/gpu-scheduler-policy`
  - `nvidia.com/gpumem-percentage`

### 2.2 已有实证

- `llama.cpp + HAMi`：已通过
- `vLLM + HAMi`：未通过

### 2.3 当前最关键的阻塞

`vLLM + HAMi` 的阻塞不是一个点，而是两层：

1. **环境层**
   - 当前 `ENV-27 / VM104` 上，原先的 `hami-device-plugin` 和注册链问题已经修好
   - 修复点包括：
     - `hami-device-plugin` DaemonSet 启动命令恢复
     - `runtimeClassName: nvidia`
     - `ClusterRoleBinding hami-device-plugin-node`
     - `ClusterRole hami-device-plugin` 的 `patch` 权限
   - 现在 `hami-scheduler` 和 device plugin 能把 Pod 正常调度并分配到 `vm104`

2. **应用层**
   - HAMi 默认仍然只注入 `NVIDIA_VISIBLE_DEVICES`
   - 不注入 `CUDA_VISIBLE_DEVICES`
   - 在 `ENV-27` 上，如果让 HAMi 自己挑卡，`vLLM` 会被分到一张已经被 Volcano workload 占了约 `42GiB` 的卡上，最终在 `KV cache` 初始化时触发真实 `CUDA out of memory`
   - 当前可行路径是显式绑定空闲 GPU UUID，并把 `maxModelLen/gpuMemoryUtilization` 收小

---

## 3. 为什么 llama.cpp 能过，vLLM 过不去

这是当前最重要的行为差异。

### llama.cpp

- 更接近直接走 CUDA
- 对 `CUDA_VISIBLE_DEVICES` 的依赖没那么强
- 所以在 HAMi 只注入 `NVIDIA_VISIBLE_DEVICES` 的情况下，仍然能形成真实成功案例

### vLLM

- 启动时会更依赖 PyTorch / NVML 的 GPU 可见性语义
- HAMi 当前默认只给 UUID 形式的 `NVIDIA_VISIBLE_DEVICES`
- 不给 `CUDA_VISIBLE_DEVICES`
- 这会让 vLLM 的 GPU 选择和预期不一致

因此，当前结论不是“Chart 不支持 HAMi”，而是：

- **HAMi 对 vLLM 的运行时注入语义还不够**

---

## 4. ENV-27 / VM104 这次的最新结果

### 4.1 当前环境状态

- `hami-scheduler`：Running
- `hami-device-plugin`：Running
- 节点仍显示：
  - `nvidia.com/gpu: 8`
  - 已分配 `7`

### 4.2 最新 `vLLM + HAMi` smoke

已执行：

- 部署 `vllm-hami-smoke`
- 使用：
  - `scheduler.type=hami`
  - `runtimeClassName: nvidia`
  - `Qwen/Qwen2.5-0.5B-Instruct`
  - `v0.17.1-x86_64`

结果一：默认 HAMI smoke

- Pod 被 `hami-scheduler` 成功调度到 `vm104`
- Pod 注解出现：
  - `hami.io/bind-phase=success`
  - `hami.io/vgpu-node=vm104`
  - `hami.io/vgpu-devices-allocated=GPU-...`
- 容器环境里能看到：
  - `NVIDIA_VISIBLE_DEVICES=GPU-...`
  - `CUDA_DEVICE_MEMORY_LIMIT_0=88452m`
- `vLLM` 实际启动到模型加载和引擎初始化阶段
- 最终在 `KV cache` 初始化时崩溃，核心错误是：
  - `torch.OutOfMemoryError: CUDA out of memory`

这说明默认 smoke 已经越过了节点注册和设备分配阶段，当前阻塞点是运行时显存行为，不再是调度入口。

结果二：绑定空闲 GPU UUID 的 smoke

- 使用：
  - `hami.io/gpu-scheduler-policy=spread`
  - `nvidia.com/use-gpuuuid=GPU-6bdf3c51-3f69-1053-a1f3-7752226ef945`
  - `maxModelLen=2048`
  - `gpuMemoryUtilization=0.6`
- Pod 最终达到：
  - `1/1 Running`
  - `deployment successfully rolled out`
- 通过 `kubectl port-forward` 的真实验证结果：
  - `/v1/models` 正常返回 `Qwen/Qwen2.5-0.5B-Instruct`
  - `/v1/chat/completions` 返回真实 completion

这说明 `vLLM + HAMi` 在 `ENV-27 / VM104` 上已经有一条可复现的通过路径。

### 4.3 自动选卡实验

为了把 “HAMI 到底会不会自动避开重载卡” 这件事说清楚，我又做了两条最小化 Pod 实验：

- Pod A：
  - `hami.io/gpu-scheduler-policy=spread`
- Pod B：
  - `hami.io/gpu-scheduler-policy=binpack`

两条 Pod 都只做：

- `registry.k8s.io/pause:3.10`
- `nvidia.com/gpu=1`
- `nvidia.com/gpumem-percentage=10`

当时节点上的真实显存占用快照是：

- GPU 1：约 `1477 MiB`
- GPU 6：约 `30353 MiB`
- GPU 0/2/4/5/7：约 `42169 MiB`
- GPU 3：约 `42555 MiB`

但两条 Pod 最终都被分到了：

- `GPU-043d3a28-f108-fc7b-6e70-cb84285332f9`（GPU 7）

也就是说，在这套混合 `HAMI + Volcano` 负载环境里：

- `spread` 没有把 Pod 放到更空的 GPU 1
- `binpack` 和 `spread` 在这轮实验里的结果一致

再结合节点注解：

- `hami.io/node-nvidia-register`

里面每张卡呈现出来的资源视图几乎一样，**没有体现出当前真实的 `nvidia-smi` 显存占用差异**。

这里需要明确：

- 上面这句是**基于当前集群实测的工程推断**
- 不是官方文档原话

但这还不能说明 `spread/binpack` 本身失效，只能说明：在当前单 Pod 混合负载实验里，**默认自动选卡不可靠，不能假定它会自动避开被 Volcano 重压的 GPU。**

### 4.4 HAMI 账本内的 spread / binpack 行为

为了继续区分“策略失效”还是“账本视角不对”，我又做了一轮只看 HAMI 自己分配行为的实验：

- 连续创建 3 个 `spread` Pod
- 连续创建 3 个 `binpack` Pod
- 都只用最小化 `pause` Pod

实测结果：

- `spread`
  - Pod 1 -> GPU 3
  - Pod 2 -> GPU 2
  - Pod 3 -> GPU 0
- `binpack`
  - Pod 1 -> GPU 0
  - Pod 2 -> GPU 0
  - Pod 3 -> GPU 0

这条实验很关键，因为它说明：

- `spread/binpack` **本身是生效的**
- HAMI 并不是完全忽略调度策略
- 问题在于它生效时参考的是 **HAMI 自己的账本视角**
- 不是宿主机 `nvidia-smi` 上那种“哪张卡当前真实更空”的视角

所以现在更准确的判断是：

- **策略逻辑存在且工作**
- **但在混合 `HAMI + Volcano` 负载环境里，策略输入不等于真实显存占用**

### 4.5 卡池隔离实验

最后我做了一条更接近生产做法的实验：

- 不再用 `nvidia.com/use-gpuuuid` 精确 pin 一张卡
- 改成用 `nvidia.com/nouse-gpuuuid` 把 Volcano 正在使用的 GPU 整体排除掉
- 再配：
  - `hami.io/gpu-scheduler-policy=spread`
  - `scheduler.hami.gpuSharePercent=90`
  - `maxModelLen=2048`
  - `gpuMemoryUtilization=0.6`

这条实验的真实结果：

- `vllm-hami-pool` 被自动分配到了 GPU 1
- `GPU 1` 当时没有被 Volcano 的大显存 workload 占满
- Pod 完成了：
  - 权重加载
  - `torch.compile`
  - `KV cache` 初始化
  - API server 启动
- 通过 `kubectl port-forward` 的真实验证：
  - `/v1/models` 正常
  - `/v1/chat/completions` 正常

这说明：

- **卡池隔离是当前环境下的可行正解**
- 不一定要精确 pin 单张 UUID
- 也可以通过“排除 Volcano 卡池 + HAMI 自己在剩余池内自动选卡”的方式跑通

---

## 5. HAMi 和 Volcano 到底是什么关系

### 5.1 不冲突的部分

如果只是：

- Volcano 负责普通调度、队列、Gang、VCJob
- HAMi 负责另一套 workload 的 GPU 调度

那么在同一集群里可以共存。

当前仓库和当前集群就处在这种状态：

- Volcano 调度链路真实可用
- HAMi 组件也同时存在

### 5.2 不能简单叠加的部分

如果你说的是：

- **HAMi vGPU**
- **Volcano vGPU / deviceshare**

这两条就不是一回事，不能直接混着上。

原因很直接：

1. HAMi 走：
   - `hami-scheduler`
   - HAMi device plugin
   - `nvidia.com/gpu`
2. Volcano vGPU 走：
   - `volcano`
   - `deviceshare` plugin
   - Volcano vGPU device plugin
   - `volcano.sh/vgpu-*`

所以：

- **同一个 workload 不会同时走 HAMi 和 Volcano**
- **同一批 GPU 也不该同时挂两套 vGPU device plugin**

---

## 6. 当前最合理的测试顺序

如果继续推进 HAMi，这条顺序最合理：

1. 保持 `hami-device-plugin` 的修复状态可持久复现
2. 把“空闲 GPU UUID 绑定”的通过路径固化成示例和文档
3. 继续验证是否可以在不显式 pin UUID 的情况下，让 HAMi 自动避开被 Volcano 占满的 GPU
4. 再评估 `CUDA_VISIBLE_DEVICES` / GPU index 语义是否会在更复杂模型上放大偏差
5. 如果自动选卡在混合负载里仍然不稳定，就要考虑给 HAMI 和 Volcano 做明确的 GPU 卡池隔离
6. 当前 `ENV-27 / VM104` 的正向证据已经说明：卡池隔离路线可行，应优先于“盲信默认自动选卡”

在此之前，不应该把 `vLLM + HAMi` 写成“无条件已支持”。

---

## 7. 当前建议

对这个仓库，当前更合理的策略是：

1. **Volcano 继续作为主要调度验证主线**
2. **HAMi 保持“已接入、部分验证、继续收敛”**
3. `vLLM + HAMi` 在没有稳定实证前，不升级为通过项

---

## 8. 相关文件

- `examples/vm104-vllm-hami-smoke-values.yaml`
- `TEST_REPORT.md`
- `README.md`
