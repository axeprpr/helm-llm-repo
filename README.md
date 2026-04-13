# helm-llm-repo

一个只围绕 **vLLM 推理服务** 的 Helm 仓库。

仓库只保留一个 chart：

- `charts/vllm-inference`

这个 chart 通过同一份 `values.yaml` 覆盖四类部署方式：

1. 原生 Kubernetes Deployment
2. Volcano 调度
3. HAMi 调度
4. Kthena ModelBooster

目标很简单：

- 不再拆多个推理 chart
- 不再散落多份专题文档
- 所有场景、示例、配置入口都收在这份 `README.md`

## 仓库结构

```text
.
├── charts/
│   └── vllm-inference/
├── examples/
│   ├── native/
│   ├── volcano/
│   ├── hami/
│   └── kthena/
└── README.md
```

## Chart 设计

这个仓库只做 `vLLM`。

- `workload.mode=deployment`
  - 渲染原生 `Deployment/Service/Ingress`
- `workload.mode=kthena-modelbooster`
  - 渲染 `ModelBooster`
  - 不再渲染原生 `Deployment/Service`

在 `deployment` 模式下，再通过 `scheduler.type` 切换：

- `native`
- `volcano`
- `hami`

## 快速开始

### 原生单卡对话

```bash
helm install qwen ./charts/vllm-inference \
  -f examples/native/single-gpu-chat.values.yaml
```

### Volcano

```bash
helm install qwen-volcano ./charts/vllm-inference \
  -f examples/volcano/basic.values.yaml
```

### HAMi

```bash
helm install qwen-hami ./charts/vllm-inference \
  -f examples/hami/basic.values.yaml
```

### Kthena

```bash
helm install qwen-kthena ./charts/vllm-inference \
  -f examples/kthena/modelbooster-cpu.values.yaml
```

## 场景索引

| 场景标题 | 测试内容 | 测试场景 | 示例 |
|---|---|---|---|
| 原生单卡对话服务 | 原生 `Deployment + Service`，OpenAI 兼容 API | 单机单卡、最小上线 | [examples/native/single-gpu-chat.values.yaml](examples/native/single-gpu-chat.values.yaml) |
| 原生 embedding 服务 | `model.type=embedding`，下发 `--task embed` | 向量化、重排 | [examples/native/embedding.values.yaml](examples/native/embedding.values.yaml) |
| 原生多卡推理 | 单节点多 GPU，`tensorParallelSize > 1` | 单节点多卡 7B+ 模型 | [examples/native/multi-gpu.values.yaml](examples/native/multi-gpu.values.yaml) |
| Volcano 基础调度 | 使用 Volcano schedulerName | 需要 queue / PodGroup / gang 能力 | [examples/volcano/basic.values.yaml](examples/volcano/basic.values.yaml) |
| Volcano custom queue | 配 queue + PodGroup | 在线/离线队列隔离 | [examples/volcano/custom-queue.values.yaml](examples/volcano/custom-queue.values.yaml) |
| Volcano gang | 多副本整组调度 | worker 必须同时起 | [examples/volcano/gang.values.yaml](examples/volcano/gang.values.yaml) |
| HAMi 基础调度 | vGPU 调度与显存分享 | GPU 共享、vGPU 场景 | [examples/hami/basic.values.yaml](examples/hami/basic.values.yaml) |
| HAMi 卡池隔离 | 通过 UUID 排除 Volcano 卡池 | HAMI 与 Volcano 混跑 | [examples/hami/pool-isolation.values.yaml](examples/hami/pool-isolation.values.yaml) |
| Kthena CPU ModelBooster | 渲染 `ModelBooster` | 先验证 Kthena 控制链 | [examples/kthena/modelbooster-cpu.values.yaml](examples/kthena/modelbooster-cpu.values.yaml) |
| Kthena GPU ModelBooster | GPU 后端 `ModelBooster` | 上层编排、后续接路由/弹性 | [examples/kthena/modelbooster-gpu.values.yaml](examples/kthena/modelbooster-gpu.values.yaml) |

## values 设计

### 1. 工作负载模式

```yaml
workload:
  mode: deployment           # deployment / kthena-modelbooster
```

### 2. 调度器切换

```yaml
scheduler:
  type: native               # native / volcano / hami
```

### 3. 关键参数

| 参数 | 作用 |
|---|---|
| `model.*` | 模型名、模型类型、量化格式、思维链解析器 |
| `engine.*` | 上下文长度、显存利用率、并行度、额外 vLLM 参数 |
| `scheduler.volcano.*` | queue、PodGroup、gang |
| `scheduler.hami.*` | 节点策略、选卡策略、显存分享比例 |
| `scheduler.gpuPool.*` | 通过 GPU UUID 控制卡池 |
| `kthena.*` | `ModelBooster` 的 backend/server 配置 |
| `proxy.*` | 统一代理环境变量 |
| `resources.*` | CPU / 内存 / GPU 请求与限制 |

## 场景说明

### 场景标题：原生 Deployment

**测试内容**

- 使用标准 Kubernetes `Deployment`
- 不引入 Volcano / HAMi / Kthena
- 直接暴露 OpenAI 兼容 API

**测试场景**

- 单卡推理
- embedding 服务
- 单节点多卡张量并行

**示例**

- [examples/native/single-gpu-chat.values.yaml](examples/native/single-gpu-chat.values.yaml)
- [examples/native/embedding.values.yaml](examples/native/embedding.values.yaml)
- [examples/native/multi-gpu.values.yaml](examples/native/multi-gpu.values.yaml)

### 场景标题：Volcano 调度

**测试内容**

- `scheduler.type=volcano`
- 支持 `queueName`
- 支持 `createPodGroup`
- 支持 `groupMinMember`

**测试场景**

- 需要 queue 治理
- 需要 gang 调度
- 希望把在线推理放进 Volcano 调度体系

**示例**

- [examples/volcano/basic.values.yaml](examples/volcano/basic.values.yaml)
- [examples/volcano/custom-queue.values.yaml](examples/volcano/custom-queue.values.yaml)
- [examples/volcano/gang.values.yaml](examples/volcano/gang.values.yaml)

### 场景标题：HAMi 调度

**测试内容**

- `scheduler.type=hami`
- 支持 `hami.io/node-scheduler-policy`
- 支持 `hami.io/gpu-scheduler-policy`
- 支持 `nvidia.com/gpumem-percentage`
- 支持 `nvidia.com/use-gpuuuid`
- 支持 `nvidia.com/nouse-gpuuuid`

**测试场景**

- GPU 分享
- vGPU
- HAMI 与 Volcano 混跑

**示例**

- [examples/hami/basic.values.yaml](examples/hami/basic.values.yaml)
- [examples/hami/pool-isolation.values.yaml](examples/hami/pool-isolation.values.yaml)

### 场景标题：Kthena ModelBooster

**测试内容**

- `workload.mode=kthena-modelbooster`
- chart 不再渲染原生 Deployment
- 直接渲染 `ModelBooster`

**测试场景**

- 需要 Kthena 控制面
- 计划后续接入 ModelRoute、扩缩容、PD 分离

**示例**

- [examples/kthena/modelbooster-cpu.values.yaml](examples/kthena/modelbooster-cpu.values.yaml)
- [examples/kthena/modelbooster-gpu.values.yaml](examples/kthena/modelbooster-gpu.values.yaml)

## GPU 调度治理建议

### 1. 节点池隔离优先

如果有多台 GPU 节点，先做节点池：

- `gpu-pool=volcano`
- `gpu-pool=hami`

然后通过：

- `nodeSelector`
- `tolerations`

把不同 workload 固定到不同节点池。

### 2. 单节点多卡时做卡池隔离

如果是单节点多卡，或者节点池不够细，再用：

- `scheduler.gpuPool.includeUUIDs`
- `scheduler.gpuPool.excludeUUIDs`

chart 会自动渲染成：

- `nvidia.com/use-gpuuuid`
- `nvidia.com/nouse-gpuuuid`

### 3. HAMI 与 Volcano 混跑的结论

- HAMI 和 Volcano 可以共存
- 但默认自动选卡不能被当成强保证
- 混跑时更稳的路径是：
  - 先做节点池隔离
  - 再做 GPU UUID 卡池隔离
  - 必要时 pin 单张 UUID

## 当前示例的工程含义

- `examples/volcano/*`
  - 解决的是 Volcano 调度、队列、PodGroup、gang
- `examples/hami/basic.values.yaml`
  - 解决的是 HAMI 基础路径
- `examples/hami/pool-isolation.values.yaml`
  - 解决的是 HAMI 与 Volcano 混跑时的卡池隔离
- `examples/kthena/*`
  - 解决的是如何用同一 chart 直接切 Kthena 资源模式

## 仓库边界

这个仓库现在不再做：

- `sglang` chart
- `llama.cpp` chart
- Volcano / HAMi 自身安装 chart
- 分散的测试档案式文档

它只做：

1. 单一 `vllm` 推理 chart
2. 覆盖多场景 values
3. 对应的 examples
4. 一份能读完的 `README.md`
