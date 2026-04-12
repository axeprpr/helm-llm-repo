# Volcano 测试覆盖指南（中文）

更新时间：2026-04-12

适用仓库：`helm-llm-repo`

目标：把 Volcano 官方文档提到的核心能力拆成一套可执行、可验收、可分阶段推进的测试矩阵，而不是只停留在“Pod 能跑起来”。

---

## 1. 先讲结论

如果你要“覆盖 Volcano 官方提到的所有功能”，不能只测一条 `vllm + schedulerName=volcano`。

至少要覆盖 5 层：

1. 控制面可用性  
2. PodGroup / gang / queue 这些核心对象行为  
3. 调度动作与调度策略  
4. 官方高级能力  
5. 与真实业务工作负载的集成

对这个仓库来说，测试应该分成两部分：

- **仓库级回归**
  - 证明 chart 把 Volcano 需要的字段正确渲染出去
  - 证明真实集群里能跑通最小 smoke
- **能力级验收**
  - 证明 Volcano 的队列、公平性、抢占、回收、层级队列、Gang、VCJob 等机制真的按官方语义工作

这两部分不能混为一谈。

---

## 2. Volcano 官方能力清单

Volcano 官方介绍页把能力分成几大类：

- Unified Scheduling
- Rich Scheduling Policies
- Queue Resource Management
- Multi-architecture computing
- Network Topology-aware Scheduling
- Online and Offline Workloads Colocation
- Multi-cluster Scheduling
- Descheduling
- Monitoring and Observability

官方来源：

- Introduction  
  https://volcano.sh/en/docs/v1-12-0/
- Actions  
  https://volcano.sh/en/docs/v1-12-0/actions/
- Plugins  
  https://volcano.sh/en/docs/v1-10-0/plugins/
- Queue  
  https://volcano.sh/en/docs/queue/
- Queue Resource Management  
  https://volcano.sh/en/docs/queue_resource_management/
- PodGroup  
  https://volcano.sh/en/docs/podgroup/
- Tutorials  
  https://volcano.sh/en/docs/v1-12-0/tutorials/
- Hierarchical Queue  
  https://volcano.sh/en/docs/v1-12-0/hierarchical_queue/
- VolcanoJob  
  https://volcano.sh/en/docs/v1-9-0/vcjob/

---

## 3. 本仓库应该覆盖到什么程度

### 3.1 必测

这部分是 `helm-llm-repo` 必须负责的。

1. `scheduler.type=volcano` 能让工作负载真正交给 Volcano
2. PodGroup 能被正确创建并被 pod 正确引用
3. queue 能被正确引用
4. gang 约束能生效
5. 基础的队列能力至少要验证：
   - default queue
   - custom queue
   - queue Open / Closed 行为
6. 至少一条真实推理链路要通过 Volcano 调度成功

### 3.2 建议测

这部分不一定全写进 chart，但必须有环境级验收。

1. preempt
2. reclaim
3. proportion / capacity / DRF
4. hierarchical queue
5. vcjob 生命周期

### 3.3 可选增强

这部分属于 Volcano 高级能力，不适合阻塞本仓库 MVP，但后续应该规划。

1. NUMA aware scheduling
2. task-topology
3. node group scheduling
4. SLA
5. online/offline colocation
6. DRA / 更细粒度设备调度
7. multi-cluster
8. descheduling
9. observability

---

## 4. 测试分层

建议把 Volcano 测试拆成 4 层。

### L1. Chart 渲染正确性

目标：证明 chart 把 Volcano 所需字段渲染对。

关注点：

- `schedulerName: volcano`
- `scheduling.volcano.sh/group-min-member`
- `scheduling.k8s.io/group-name`
- queue 相关 annotation 或 PodGroup 字段
- `PodGroup` 资源对象本身

这层只防模板回归，不证明功能真正可用。

### L2. 单集群单节点 smoke

目标：证明 Volcano 控制面是活的、调度链路是通的。

关注点：

- Volcano scheduler / controller 运行正常
- Pod 事件里 `Scheduled` 来源是 `volcano`
- `PodGroup` 状态进入 `Running`
- 至少一条真实 HTTP 推理请求成功

这层是当前 `VM104` 最适合持续回归的层。

### L3. 调度机制验收

目标：证明队列、公平性、抢占、回收这些机制真的按官方语义工作。

关注点：

- 队列资源上限
- deserved / capability / guarantee
- reclaim / preempt
- 多队列竞争
- gang 阻塞与释放

这层比 smoke 更重要，但环境要求更高。

### L4. 高级特性验收

目标：覆盖官方高级能力。

关注点：

- hierarchical queue
- vcjob policies
- task-topology
- NUMA aware
- node group
- colocation
- observability

---

## 5. 详细测试矩阵

下面这张表是建议的正式覆盖面。

| 编号 | 官方能力 | 是否必须 | 当前环境能否做 | 验收标准 |
|---|---|---:|---:|---|
| V-01 | Volcano 控制面可用 | 是 | 能 | `volcano-scheduler` / `volcano-controllers` Running |
| V-02 | native workload 走 Volcano 调度 | 是 | 能 | Pod 事件 `Scheduled` 来源为 `volcano` |
| V-03 | 自动 PodGroup（annotation 驱动） | 是 | 能 | `group-min-member` 可生成 PodGroup，资源不足时 Pending |
| V-04 | 显式 PodGroup | 是 | 能 | chart 创建的 PodGroup 被 pod 正确引用 |
| V-05 | default queue | 是 | 能 | 未指定 queue 时进入 `default` |
| V-06 | custom queue | 是 | 能 | 指定 queue 后 PodGroup 进入对应 queue |
| V-07 | queue Closed | 是 | 能 | 新任务不可入队或不可被调度 |
| V-08 | gang scheduling | 是 | 能 | `minMember` 不满足时全部不启动；满足后整体推进 |
| V-09 | single-replica vLLM + Volcano smoke | 是 | 能 | `/health`、`/v1/models`、completion 成功 |
| V-10 | multi-replica vLLM gang smoke | 建议 | 部分能 | `replicas=2` 且 `groupMinMember=2` 成功或按预期 Pending |
| V-11 | vcjob quickstart | 建议 | 能 | VCJob 成功从 Pending->Running->Completed |
| V-12 | vcjob task policy | 建议 | 能 | `TaskCompleted` / `PodFailed` policy 生效 |
| V-13 | priority / preempt | 建议 | 需要压力场景 | 高优先级任务抢占低优先级资源 |
| V-14 | reclaim（跨队列） | 建议 | 需要多队列 | 超过 deserved 的资源可被回收 |
| V-15 | proportion plugin | 建议 | 需要多队列 | 多队列资源分配符合比例预期 |
| V-16 | capacity plugin | 建议 | 能 | capability / deserved / guarantee 生效 |
| V-17 | hierarchical queue | 建议 | 能 | 父子队列资源继承、回收符合预期 |
| V-18 | DRF | 建议 | 需要混合资源竞争 | 多维资源公平性符合预期 |
| V-19 | binpack | 可选 | 需要多节点 | pod 更集中地落到少数节点 |
| V-20 | task-topology | 可选 | 需要多任务 VCJob | 亲和/反亲和策略生效 |
| V-21 | NUMA aware | 可选 | 需特定硬件 | NUMA 资源绑定符合预期 |
| V-22 | node group scheduling | 可选 | 需多节点分组 | queue / task 与 node group 绑定正确 |
| V-23 | online/offline colocation | 可选 | 需混部节点 | 离线业务与在线业务共存且受策略约束 |
| V-24 | monitoring / observability | 可选 | 能 | metrics 暴露、关键对象状态可观测 |
| V-25 | multi-cluster scheduling | 可选 | 不能 | 需额外集群 |
| V-26 | descheduling | 可选 | 需对应组件 | 迁移/驱逐策略按预期执行 |

---

## 6. 当前 `VM104` 上应该先做的测试顺序

### P0：立刻纳入回归

1. Volcano 控制面健康检查
2. `vllm + volcano` 单副本 smoke
3. Deployment/StatefulSet 基于 `group-min-member` 的自动 PodGroup
4. custom queue smoke
5. `queue Closed` 行为验证

### P1：下一阶段

1. `vllm replicas=2 + groupMinMember=2`
2. `vcjob` quickstart
3. `vcjob` policy（PodFailed / TaskCompleted）
4. `capacity` + `deserved` + `capability`
5. `priority/preempt`
6. `reclaim`

### P2：高级能力

1. hierarchical queue
2. DRF
3. binpack
4. task-topology
5. observability

---

## 7. 当前仓库已经验证到的 Volcano 能力

截至当前，已经真实验证过：

1. `vllm + volcano` 单副本 smoke 成功
2. `vllm + volcano + custom queue` 成功
3. `vllm + volcano + auto PodGroup` 成功
4. `vllm replicas=2 + groupMinMember=2` gang 成功
5. pod 事件来自 `volcano`
6. 显式 `PodGroup` 与自动 `PodGroup` 都已收集到真实证据
7. `/health`
8. `/v1/models`
9. `/v1/chat/completions`
10. `vcctl` 已完成 `queue close/open` 状态切换实测

并且收到了一个真实 chart bug：

- `scheduler.volcano.createPodGroup=true` 时，没有把 `scheduling.k8s.io/group-name` 写到 pod annotation
- 结果导致 chart 创建的具名 `PodGroup` 没被实际使用，Volcano 自动创建了匿名 `PodGroup`

这类问题说明：

**Volcano 测试不能只看 pod 有没有起来，必须同时看：**

- pod annotation
- `PodGroup` 名称
- `PodGroup` 状态
- `Scheduled` 事件来源

---

## 8. 推荐的正式 smoke 用例

### 用例 A：vLLM + Volcano 单副本 smoke

目标：

- 验证 `scheduler.type=volcano`
- 验证显式 `PodGroup`
- 验证真实 completion

验收：

- deployment `1/1`
- pod `1/1`
- `PodGroup Running`
- `Scheduled` from `volcano`
- `/health=200`
- `/v1/models=200`
- `/v1/chat/completions=200`

### 用例 B：自动 PodGroup smoke

目标：

- 使用标准 `Deployment`
- 通过 `scheduling.volcano.sh/group-min-member` 自动生成 `PodGroup`

验收：

- 自动生成 `podgroup-<uid>`
- 资源不足时 `PodGroup` 为 `Pending/Inqueue`
- 资源满足后转 `Running`

### 用例 C：custom queue smoke

目标：

- 验证 queue 指定与配额约束

验收：

- `Queue` 为 `Open`
- `PodGroup.spec.queue` 正确
- pod 事件 `Scheduled` 来源为 `volcano`

当前状态：

- 已在 `VM104` 上通过

### 用例 D：queue close/open

目标：

- 用官方 `vcctl` 验证 queue 状态切换
- 记录 `Closed` 队列上的真实行为

验收：

- `Open -> Closing -> Closed -> Open` 切换成功
- 在 `Closed` 队列上创建新 workload 后，记录其真实调度行为

当前状态：

- 已在 `VM104` 上实测
- 结果是：`Closed` 状态已确认存在，但没有证明“会硬阻塞所有新 workload”

### 用例 E：gang smoke

目标：

- 验证 `minMember`

验收：

- 当 `groupMinMember=2` 且只能满足 1 个 pod 时，两个都不应启动
- 资源满足 2 个后，整体一起推进

### 用例 F：preempt / reclaim smoke

目标：

- 验证高优先级 / 高权重队列能抢回资源

验收：

- 低优先级工作负载被驱逐或回收
- 高优先级任务得到调度

---

## 9. 你现在这套环境的限制

`VM104` 适合做：

- Volcano 控制面
- 单节点 Volcano 调度
- 单副本 / 小规模 gang
- queue / PodGroup / vcjob 基础能力

`VM104` 不适合直接宣称“已覆盖全部官方能力”：

- 没有多节点拓扑，无法严肃验证：
  - binpack 跨节点效果
  - node group scheduling
  - 网络拓扑感知
  - NUMA / 复杂多节点 gang
  - multi-cluster
  - 大规模 reclaim / preempt

所以“覆盖官方全部功能”必须拆成多环境矩阵，而不是想在一台单节点 4090 VM 上一次做完。

---

## 10. 推荐执行计划

### 第一阶段：仓库必须完成

1. `vllm + volcano` 单副本 smoke
2. 自动 PodGroup smoke
3. custom queue smoke
4. queue Closed smoke
5. `vcjob` quickstart smoke

### 第二阶段：Volcano 核心机制

1. gang smoke（2 副本）
2. priority/preempt
3. reclaim
4. capacity plugin
5. hierarchical queue

### 第三阶段：高级调度能力

1. DRF
2. binpack
3. task-topology
4. observability

### 第四阶段：需要扩环境

1. NUMA
2. node group
3. online/offline colocation
4. multi-cluster
5. descheduling

---

## 11. 我对这个仓库的建议

不要把 Volcano 测试只写成“一个 values 文件 + 一个 smoke”。

应该至少落成 3 份文档/资产：

1. **Smoke values**
   - `examples/vm104-vllm-volcano-smoke-values.yaml`

2. **测试用例文档**
   - 哪些是 P0 / P1 / P2
   - 每条验收标准是什么

3. **环境说明**
   - 哪些用例能在 `VM104` 跑
   - 哪些必须迁到多节点/多集群环境

否则最终你会得到一种假象：  
“Volcano 已支持”，但其实只是 `schedulerName` 没写错。
