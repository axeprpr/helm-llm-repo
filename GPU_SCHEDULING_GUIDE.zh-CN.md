# GPU 调度治理指南（中文）

更新时间：2026-04-13

适用仓库：`helm-llm-repo`

目标：把当前仓库里与 `Volcano`、`HAMi`、`vLLM`、`SGLang`、`llama.cpp` 相关的 GPU 调度经验固化成一套可执行的治理方案，而不是继续依赖默认行为。

---

## 1. 先讲结论

当前环境里，最重要的结论有 4 条：

1. **`Volcano` 和 `HAMi` 可以共存**
2. **`vLLM + HAMi` 可以跑通**
3. **混合负载下不要信任默认自动选卡**
4. **要把“卡池隔离”或“节点池隔离”当成正式设计**

也就是说：

- 不要把 “默认 `spread/binpack` 应该会自动避开重载 GPU” 当成前提
- 要显式告诉集群：
  - 哪些 GPU 给 `Volcano`
  - 哪些 GPU 给 `HAMi`
  - 哪些节点给在线服务
  - 哪些节点给实验/批处理

---

## 2. 为什么需要治理

这个仓库已经拿到的真实证据说明：

- `Volcano` 路径稳定
- `HAMi` 路径也可用
- 但默认自动选卡在混合 `HAMi + Volcano` 负载里不可靠

实测里出现过：

- `Volcano` 的 vLLM 已经把某张 4090 占了约 `42 GiB`
- 新的 `HAMi` workload 仍然被放到同一张卡
- 最终 `KV cache` 初始化时 `CUDA out of memory`

所以问题不在“能不能调度”，而在：

- **调度输入与真实显存压力不一致**

---

## 3. 推荐的治理分层

建议按两层来设计：

### 3.1 第一层：节点池隔离

这是优先级最高的一层。

按节点做隔离，例如：

- `gpu-pool=volcano`
- `gpu-pool=hami`
- `gpu-pool=general`

再配 taint：

- `gpu-pool=volcano:NoSchedule`
- `gpu-pool=hami:NoSchedule`

意义：

- 先把大类 workload 分到不同节点
- 避免不同调度路径先在节点级别打架

适合：

- 多节点环境
- 生产环境
- 长期运行的在线服务

### 3.2 第二层：GPU 卡池隔离

当你还在单节点，或者多个 workload 仍需共用一个节点时，再做这层。

卡池隔离有两种实现：

1. **精确 pin GPU UUID**
   - `nvidia.com/use-gpuuuid`
2. **排除 GPU 池**
   - `nvidia.com/nouse-gpuuuid`

意义：

- 不靠“默认自动选卡”
- 把显卡池边界变成显式规则

适合：

- 单节点
- 临时共用一台大 GPU 机器
- 过渡期环境

---

## 4. 推荐使用顺序

### 场景 A：多节点生产环境

优先：

1. 节点池隔离
2. 队列/优先级/配额
3. 必要时再做卡池隔离

### 场景 B：单节点或临时混跑环境

优先：

1. GPU 卡池隔离
2. 保守 runtime 参数
3. 再看是否允许自动选卡

---

## 5. 当前建议的调度规则

### 5.1 `Volcano`

适合：

- 在线推理主线
- Gang scheduling
- Queue / Priority / Preempt
- 多副本 / 多节点调度

建议：

- 生产流量优先走 `Volcano`
- 大模型、多副本、需要队列治理的服务优先走 `Volcano`

### 5.2 `HAMi`

适合：

- GPU 共享
- vGPU / 显存百分比
- 单卡切分
- 同节点多轻量 workload

建议：

- 对小模型和共享卡场景使用 `HAMi`
- 不要在混合负载下盲信默认自动选卡

---

## 6. 什么时候必须 pin UUID

建议直接 `use-gpuuuid` 的场景：

1. 单节点混跑
2. 某些 GPU 已经被重载服务长期占用
3. 你只需要一两张固定卡
4. 当前环境还没做好正式卡池治理

优点：

- 行为确定
- 最容易复现

缺点：

- 运维成本更高
- 不够弹性

---

## 7. 什么时候适合用 `nouse-gpuuuid`

适合：

1. 你已经知道一组 GPU 是 `Volcano` 池
2. 想让 `HAMi` 在剩余池里自动选
3. 想避免单卡硬编码

这是当前 `ENV-27 / VM104` 上已经验证通过的路线。

已验证组合：

- `hami.io/gpu-scheduler-policy=spread`
- `scheduler.hami.gpuSharePercent=90`
- `nvidia.com/nouse-gpuuuid=<Volcano 池>`
- `maxModelLen=2048`
- `gpuMemoryUtilization=0.6`

---

## 8. 节点池治理建议

### 8.1 节点打标

```bash
kubectl label node vm104 gpu-pool=hami --overwrite
kubectl label node worker-1 gpu-pool=volcano --overwrite
```

### 8.2 节点打 taint

```bash
kubectl taint node vm104 gpu-pool=hami:NoSchedule --overwrite
kubectl taint node worker-1 gpu-pool=volcano:NoSchedule --overwrite
```

### 8.3 workload 选择对应池

示意：

```yaml
nodeSelector:
  gpu-pool: hami

tolerations:
  - key: gpu-pool
    operator: Equal
    value: hami
    effect: NoSchedule
```

---

## 9. 单节点卡池治理建议

### 9.1 `Volcano` 固定池

例如固定给：

- GPU 0
- GPU 2
- GPU 3
- GPU 4
- GPU 5
- GPU 7

### 9.2 `HAMi` 固定池

例如固定给：

- GPU 1
- GPU 6

### 9.3 `HAMi` workload 做法

优先级：

1. `nouse-gpuuuid` 排除 Volcano 池
2. `gpuSchedulerPolicy=spread`
3. `gpuSharePercent`
4. 仍不稳定时再 `use-gpuuuid`

---

## 10. 参数建议

### 10.1 `vLLM + HAMi`

初始保守值：

```yaml
engine:
  maxModelLen: 2048
  gpuMemoryUtilization: 0.6

scheduler:
  type: hami
  hami:
    gpuSchedulerPolicy: spread
    gpuSharePercent: 90
```

### 10.2 `vLLM + Volcano`

建议：

- 把 `Volcano` 放在固定 GPU 池
- 用 queue / priority / preempt 控制工作负载

---

## 11. 当前仓库对应示例

### `HAMi` 精确 pin 单卡

- `examples/vm104-vllm-hami-smoke-values.yaml`

### `HAMi` 卡池隔离

- `examples/vm104-vllm-hami-pool-values.yaml`

### `Volcano` 基础 smoke

- `examples/vm104-vllm-volcano-smoke-values.yaml`

### `Volcano` custom queue

- `examples/vm104-vllm-volcano-custom-queue-values.yaml`

### `Volcano` gang

- `examples/vm104-vllm-volcano-gang-values.yaml`

---

## 12. 建议落地顺序

1. 先确定业务分层：
   - 在线推理
   - 共享推理
   - 研究/实验
2. 做节点池隔离
3. 做卡池隔离
4. 再启用自动选卡策略
5. 最后才考虑更复杂的自动放置

---

## 13. 当前推荐

对当前 `ENV-27 / VM104`，推荐顺序是：

1. 先用 `Volcano` 跑主线服务
2. `HAMi` 只跑共享/轻量 workload
3. `HAMi` 和 `Volcano` 做显式卡池隔离
4. 不要继续依赖默认全局自动选卡

这个结论已经有真实 smoke 和真实 completion 证据支撑。
