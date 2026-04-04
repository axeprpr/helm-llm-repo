# Volcano & HAMi Scheduler Guide

> Created: 2026-04-04
> Based on: [Volcano Official Docs](https://volcano.sh/en/docs/), [HAMi Official Docs](https://project-hami.io/), [Project-HAMi/HAMi](https://github.com/Project-HAMi/HAMi), [volcano-vgpu-device-plugin](https://github.com/Project-HAMi/volcano-vgpu-device-plugin)

---

## 一、概念速览

| | Volcano | HAMi |
|---|---|---|
| **定位** | Kubernetes 批处理/AI/HPC 调度器 | 异构设备虚拟化与调度中间件 |
| **核心能力** | Gang scheduling、队列、公平调度、VolcanoJob CRD | vGPU 共享、显存/算力硬隔离、设备选择 |
| **资源名** | `volcano.sh/vgpu-*`（搭配 volcano-vgpu 时） | `nvidia.com/gpu/gpumem/gpucores` |
| **调度方式** | `deviceshare` 插件 + Volcano scheduler | `hami-scheduler`（extender 模式） |
| **依赖组件** | Volcano scheduler + 可选 device plugin | HAMi-core + device plugin + MutatingWebhook |
| **典型场景** | 分布式训练gang、作业队列、多租户资源管控 | GPU 共享、细粒度显存限制、固定 GPU 卡 |

---

## 二、Volcano 调度器

### 2.1 安装

```bash
#Helm 安装 Volcano
helm repo add volcano-sh https://volcano-sh.github.io/helm-charts
helm repo update
helm install volcano volcano-sh/volcano -n volcano-system --create-namespace
```

### 2.2 核心概念

**PodGroup**
Volcano 的作业抽象，对象是一组需要整体调度的 Pod：

```yaml
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  name: my-job
spec:
  minMember: 3          # 至少要调度成功的 Pod 数量（全或无）
  minResources:         # 最小资源门槛
    nvidia.com/gpu: 1
  queue: default       # 所属队列
```

**Gang Scheduling**
"all or nothing"语义：PodGroup 的 `minMember` 达到后才整体调度，避免分布式训练只起一半造成资源浪费。

**Queue**
多租户资源队列，支持权重和资源上限：

```yaml
apiVersion: scheduling.volcano.sh/v1beta1
kind: Queue
metadata:
  name: production
spec:
  weight: 10
  reclaimable: false
  capability:
    cpu: 64
    nvidia.com/gpu: 8
```

**关键插件**

| 插件 | 作用 |
|------|------|
| `gang` | 全或无调度，PodGroup 级别 |
| `drf` | Dominant Resource Fairness，多资源公平分配 |
| `binpack` | 资源压实，减少碎片 |
| `deviceshare` | vGPU 异构设备共享（需开启 `VGPUEnable: true`） |
| `predicates` | 基础资源过滤、亲和性、拓扑 |
| `proportion` | 队列资源比例分配 |

### 2.3 Volcano 配置（启用 vGPU）

编辑 `volcano-scheduler-configmap`：

```yaml
kubectl edit cm volcano-scheduler-configmap -n volcano-system
```

在 `volcano-scheduler.conf` 中加入：

```conf
actions: "enqueue, allocate, backfill"
tiers:
- plugins:
  - name: priority
  - name: gang
  - name: conformance
- plugins:
  - name: drf
  - name: deviceshare
    arguments:
      deviceshare.VGPUEnable: true
  - name: predicates
  - name: binpack
```

### 2.4 在 helm-llm-repo 中使用 Volcano

```yaml
scheduler:
  type: volcano                    # 使用 Volcano 调度器
  volcano:
    createPodGroup: true           # 自动创建 PodGroup
    groupMinMember: 1              # gang 最小成员数
    queueName: default             # 队列名
    minResources:                  # 可选：最小资源门槛
      nvidia.com/gpu: 1
```

---

## 三、HAMi 调度器

### 3.1 安装

```bash
# Helm 安装 HAMi
helm repo add.ham i https://project-hami.github.io/helm-charts
helm repo update
helm install hami project-hami/hami -n hami-system --create-namespace
```

### 3.2 核心概念

**四层架构**

1. **MutatingWebhook** — 检查 Pod 是否只申请 HAMi 资源，如果是则注入 `schedulerName: hami-scheduler`
2. **scheduler-extender** — 处理 `filter` 和 `bind` verb，实现 GPU 设备选择
3. **device-plugin** — 向 kubelet 注册 GPU 资源，将调度结果映射进容器
4. **HAMi-core** — 通过 hook `libcudart.so`/`libcuda.so` 做显存/算力虚拟化与硬隔离

**vGPU 机制**
HAMi-core 是 CUDA API hook 库，不是硬件切片（MIG），是软件层限制：
- 劫持 CUDA Runtime 和 Driver 调用
- 实现显存和计算单元的配额控制
- 几乎所有 NVIDIA GPU 都支持

**调度策略**

| 策略 | 说明 |
|------|------|
| `binpack` | GPU 尽量集中到少数节点 |
| `spread` | GPU 尽量分散到不同节点 |
| `topology-aware` | 感知 NVLink/NVSwitch 拓扑优先调度 |

### 3.3 在 helm-llm-repo 中使用 HAMi

```yaml
scheduler:
  type: hami
  hami:
    gpuSharePercent: 50           # 每卡分给 50% 显存（可按需调整）
    nodeSchedulerPolicy: spread   # 节点级调度策略
    gpuSchedulerPolicy: binpack   # GPU 级调度策略
```

GPU 卡固定（通过 annotation）：

```yaml
scheduler:
  type: hami
  annotations:
    nvidia.com/use-gpuuuid: "GPU-e099b988-e339-e561-2506-0bd2b99201b3"
```

---

## 四、volcano-vgpu-device-plugin

### 4.1 是什么

`volcano-vgpu-device-plugin` 是 Project-HAMi 维护的、面向 Volcano 调度器的 NVIDIA vGPU 设备插件。

**不是独立 HAMi**，内部复用 HAMi-core 做容器内硬隔离。

官方明确：**用 volcano-vgpu 时不需要装完整 HAMi**。

### 4.2 安装

```bash
kubectl apply -f https://raw.githubusercontent.com/Project-HAMi/volcano-vgpu-device-plugin/main/volcano-vgpu-device-plugin.yml
```

### 4.3 架构

```
Volcano scheduler（deviceshare 插件）
    ↓ volcano.sh/vgpu-number, volcano.sh/vgpu-memory
volcano-vgpu-device-plugin（DaemonSet）
    ↓ 三个独立 device plugin 实例
kubelet 注册 volcano.sh/vgpu-* 资源
    ↓
HAMi-core（容器内 hook，显存/SM 硬限制）
```

### 4.4 与独立 HAMi 的区别

| 维度 | volcano-vgpu | 独立 HAMi |
|------|-------------|-----------|
| 调度器 | Volcano `deviceshare` | 自带 `hami-scheduler`（extender） |
| 资源名 | `volcano.sh/vgpu-*` | `nvidia.com/gpu/gpumem/gpucores` |
| MutatingWebhook | ❌ 不需要 | ✅ 有 |
| HAMi-core | ✅ 复用 | ✅ 完整集成 |
| 需要完整 HAMi 安装 | ❌ 不需要 | ✅ 需要 |

**重要**：每节点只能保留一种 GPU 管理插件，volcano-vgpu 和独立 HAMi/NVIDIA 官方 device plugin **不能同时跑**。

---

## 五、测试场景

### 5.1 Volcano 测试场景

**场景 V1：基础 gang scheduling**
- 目标：验证 `minMember` 全或无语义
- 操作：部署 `replicas: 3`，`minMember: 3`，观察是否同时调度

**场景 V2：Queue 队列调度**
- 目标：验证多队列权重和资源配额
- 操作：创建两个 Queue（weight 1:2），分别提交作业，观察资源分配比例

**场景 V3：binpack 资源压实**
- 目标：验证资源尽量集中在少数节点
- 操作：提交多个小作业，检查调度结果是否集中在少量节点

### 5.2 HAMi 测试场景

**场景 H1：基础 vGPU 共享**
- 目标：验证一张卡可共享给多个 Pod
- 操作：提交两个 Pod，各请求 `nvidia.com/gpumem: 10000`（10G），观察是否调度到同一卡

**场景 H2：GPU UUID 固定**
- 目标：验证 `nvidia.com/use-gpuuuid` annotation 生效
- 操作：提交 Pod 并指定特定 GPU UUID，检查调度到的卡是否匹配

**场景 H3：节点/GPU 级调度策略**
- 目标：验证 `nodeSchedulerPolicy` 和 `gpuSchedulerPolicy` 生效
- 操作：分别设 `spread` 和 `binpack`，检查调度分布是否符合预期

### 5.3 volcano-vgpu 组合测试场景

**场景 C1：Volcano gang + vGPU 共享**
- 目标：gang 调度语义 + vGPU 细粒度资源限制同时生效
- 操作：启用 `deviceshare.VGPUEnable: true`，提交带 `volcano.sh/vgpu-number` 的 PodGroup

**场景 C2：队列优先级 + GPU 隔离**
- 目标：Volcano 队列负责优先级，HAMi-core 负责 GPU 隔离
- 操作：配置 Queue 权重，Pod 使用 `volcano.sh/vgpu-memory` 限制

---

## 六、已知限制与坑

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| `UnexpectedAdmissionError` | 网络/DNS 不通、webhook 证书未 patch、调度器服务挂了 | 检查 apiserver 和调度器连通性 |
| 资源 overcommit 记账不准 | `deviceMemoryScaling` 配置错误，节点级配置优先于全局 | 确认节点级配置 |
| 调度节点和实际绑定不一致 | 异常路径下 annotation 和 runtime 状态分裂 | 重启相关 Pod |
| vLLM + HAMi 兼容性 | HAMi 2.7.1 前有已知 bug | 升级到 HAMi ≥ 2.7.1 |
| 每节点多 GPU 管理插件冲突 | volcano-vgpu 和 HAMi 同时跑 | 二选一，HAMi FAQ 明确建议 |

---

## 七、节点上下文

### ENV-42（192.168.3.42）
- **GPU**: 8× RTX 2080 Ti（21.5GB 显存）
- **现状**: Hami-scheduler 已部署并正常工作，Clash 代理在 `http://192.168.3.42:7890`
- **NVLink**: `GPU0 <-> GPU3 = NV1`，`GPU6 <-> GPU7 = PIX`（无 NVLink）
- **适用测试**: HAMi vGPU 共享、vGPU 限制精度验证

### ENV-27（192.168.23.27）
- **GPU**: 8× NVIDIA H100
- **现状**: 单节点 kubeadm Kubernetes v1.32.13 已运行；Volcano v1.10.0 已通过 `kubectl apply -f volcano-development.yaml` 安装，scheduler / controllers / admission 均正常；HAMi v2.7.1 已通过 Helm 安装，`hami-scheduler` 为 Running
- **适用测试**: 大显存模型推理、Volcano 调度器安装和 gang scheduling、HAMi 安装
- **备注**:
  - `hami-device-plugin` DaemonSet 当前 `DESIRED=0`，原因是节点缺少 `gpu=on` label；更关键的是该节点尚未安装 NVIDIA driver
  - 节点 allocatable 当前没有 `nvidia.com/gpu`，说明 kubelet 未发现可用 GPU 资源
  - 结论：ENV-27 上 Volcano 和 HAMi 控制面已安装完成，但在 NVIDIA driver 安装前，H100 相关真实 GPU 工作负载无法运行

---

## 八、参考链接

- Volcano 官方文档: https://volcano.sh/en/docs/
- Volcano GitHub: https://github.com/volcano-sh/volcano
- HAMi 官方文档: https://project-hami.io/
- HAMi GitHub: https://github.com/Project-HAMi/HAMi
- volcano-vgpu-device-plugin: https://github.com/Project-HAMi/volcano-vgpu-device-plugin
- HAMi-core 设计: https://project-hami.io/docs/developers/hami-core-design
- HAMi 调度机制: https://project-hami.io/docs/developers/scheduling/
- HAMi vGPU 集成: https://project-hami.io/docs/installation/how-to-use-volcano-vgpu
- HAMi 博客（UnexpectedAdmissionError 说明）: https://project-hami.io/blog/2024/12/31/post/
