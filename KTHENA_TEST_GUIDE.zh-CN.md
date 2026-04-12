# Kthena 测试整理（中文）

更新时间：2026-04-12

适用仓库：`helm-llm-repo`

目标：把 `ENV-27 / VM104` 上对 Kthena 的真实安装与验证结果整理成可复现记录，明确它当前适合放在什么位置，以及已经验证到哪一层。

---

## 1. 先讲结论

当前判断：

1. **Kthena 不适合现在替代本仓库的 Helm Chart 主线**
2. **Kthena 适合作为上层编排能力继续跟进**
3. 当前环境已经验证到：
   - 控制面可安装
   - CRD / controller 资源链可工作
   - `downloader` 可完成模型下载
   - `runtime` 能启动并通过 `/health`
4. 但还没有把一条 `ModelBooster` 路径稳定收敛到“最终服务完全 Ready 且长期稳定”

所以更合理的定位是：

- `helm-llm-repo` 继续承载底层推理引擎 Chart
- Kthena 作为上层编排集成对象，单独维护示例和测试记录

---

## 2. Kthena 是什么

Kthena 不是 `vLLM / SGLang / llama.cpp` 的替代物。它更像上层的推理编排面，核心对象包括：

- `ModelBooster`
- `ModelServing`
- `ModelServer`
- `ModelRoute`

它解决的问题是：

- 模型服务统一编排
- 路由
- 副本管理
- 推理后端抽象
- 进一步扩展到更复杂的推理服务形态

这和当前仓库做的事情不同。当前仓库做的是：

- 推理引擎 Helm Chart
- Volcano / HAMi 调度适配
- 真实部署 smoke

---

## 3. 官方资料

- Kthena 介绍  
  https://kthena.volcano.sh/docs/intro
- 安装文档  
  https://kthena.volcano.sh/docs/getting-started/installation
- GitHub 仓库  
  https://github.com/volcano-sh/kthena
- `v0.3.0` 发布说明  
  https://kthena.volcano.sh/blog/release-v0.3.0
- ModelBooster 用户文档  
  https://kthena.volcano.sh/docs/user-guide/model-booster
- Ascend / Mooncake 文档  
  https://kthena.volcano.sh/docs/user-guide/prefill-decode-disaggregation/vllm-ascend-mooncake

---

## 4. 国产化支持怎么判断

当前能明确说的只有这些：

1. 官方文档明确强调异构硬件方向，写到了 `GPU / NPU`
2. 官方文档明确给了 **Ascend NPU** 的页面

但当前官方公开材料还不足以支持这种说法：

- “所有国产 GPU / NPU 都已经正式验证”

因此更严谨的结论是：

- **可以说 Kthena 有国产化方向支持**
- **可以重点关注昇腾**
- **不能直接宣称对全部国产芯片已经成熟支持**

---

## 5. ENV-27 / VM104 真实安装过程

### 5.1 基本环境

- 控制平面节点：`vm104` / `192.168.23.27`
- Worker 节点：`worker-1` / `192.168.23.242`
- Kubernetes：`v1.32.13`

### 5.2 官方安装清单的真实问题

官方 release 清单：

- `https://github.com/volcano-sh/kthena/releases/latest/download/kthena-install.yaml`

直接 `kubectl apply -f kthena-install.yaml` 在本环境里会踩到一个真实问题：

- `modelservings.workload.serving.volcano.sh` 这个大 CRD 因为 `last-applied-configuration` 注解过大失败

典型错误：

```text
CustomResourceDefinition.apiextensions.k8s.io "modelservings.workload.serving.volcano.sh" is invalid:
metadata.annotations: Too long: may not be more than 262144 bytes
```

本环境可用的处理方式是：

1. 先确保 `kthena-system` 命名空间存在
2. 用 `kubectl create -f kthena-install.yaml`
3. 避免 `kubectl apply` 给超大 CRD 补 `last-applied` 注解

这说明：

- 官方安装清单不是“拿来即用”
- 至少在这套环境下，需要对安装方式做约束

### 5.3 镜像获取问题

本环境里还有一个真实网络问题：

- 集群节点对 `ghcr.io` / `public.ecr.aws` 的直连并不稳定

实际处理方式：

1. 在有代理能力的机器上把镜像拉成 tar
2. 再导入各节点 `containerd`

涉及的镜像包括：

- `ghcr.io/volcano-sh/kthena-router:v0.3.0`
- `ghcr.io/volcano-sh/kthena-controller-manager:v0.3.0`
- `ghcr.io/volcano-sh/runtime:v0.3.0`
- `ghcr.io/volcano-sh/downloader:v0.3.0`
- `public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:latest`

所以当前结论很直接：

- Kthena 在这套环境里不是“直接 apply 就结束”
- 它对镜像分发链路有额外要求

---

## 6. 已经验证通过的链路

### 6.1 控制面

已经验证：

- `kthena-router` 正常 Running
- `kthena-controller-manager` 正常 Running

### 6.2 CRD / 控制器资源链

已经验证一条 `ModelBooster` 申请会自动衍生：

- `ModelServing`
- `ModelServer`
- `ModelRoute`

也就是说，Kthena 的控制器链不是空壳，核心对象联动确实工作。

### 6.3 downloader

已经验证：

- `downloader` init container 能从 Hugging Face 下载模型到缓存目录

`tiny-gpt2` 这条的证据最清楚：

- `sshleifer/tiny-gpt2` 成功下载
- 9 个文件全部拉完

### 6.4 runtime

已经验证：

- `runtime` 容器能启动
- 能监听端口
- `/health` 返回 `200`

这说明 Kthena 自己的 runtime 基本链路在本环境是通的。

---

## 7. 还没有完全收敛的部分

当前还没拿到稳定正向证据的是：

- `runtime + engine` 组合长期稳定到完整 Ready
- 最终对外服务稳定可调用，并保持在健康状态

已经定位到的影响因素有：

1. 节点镜像拉取对外网依赖强
2. `public.ecr.aws` 在当前环境下经常需要手工预拉
3. `runtime` 虽然起来了，但 `engine` 和整体 Pod readiness 还没有收敛成稳定的 `Ready`

所以现在不能把 Kthena 写成：

- “已经在 VM104 上完整验证可生产使用”

这不严谨。

---

## 8. 当前最有价值的两条示例

### 8.1 官方 quickstart 归档版

文件：

- `examples/kthena/qwen2.5-0.5b-modelbooster.yaml`

用途：

- 保留官方 `Qwen2.5-0.5B-Instruct` quickstart 思路
- 方便后续回到官方路径继续测试

### 8.2 最小化 tiny 模型验证

文件：

- `examples/kthena/tiny-gpt2-modelbooster.yaml`

用途：

- 降低模型下载体积
- 把问题更聚焦到 Kthena 自身，而不是大模型下载时间

---

## 9. 是否建议现在采用

### 9.1 现在不建议的做法

不建议现在做这些事：

1. 用 Kthena 替代当前 `vllm / sglang / llamacpp` Chart 主线
2. 把当前所有部署工作都切到 Kthena
3. 在没有继续完成最终 serving 稳定验证前，宣称它已满足生产要求

### 9.2 建议的做法

更合理的路线是：

1. 保持 `helm-llm-repo` 作为底层推理部署仓库
2. 在仓库里继续保留 `examples/kthena/`
3. 用独立文档和独立 smoke 逐步推进 Kthena 集成
4. 等 Kthena 最终 serving 稳定后，再考虑是否上升为正式支持项

---

## 10. 下一步建议

如果继续推进 Kthena，这条顺序最合理：

1. 固化节点镜像预拉流程
2. 把 `tiny-gpt2` 路径收敛到稳定 Ready
3. 再回头重跑 `Qwen2.5-0.5B-Instruct`
4. 最后补一条真正的对外 completion 验证

在这之前，Kthena 最适合的定位仍然是：

- **调研中 / 集成试验中**

