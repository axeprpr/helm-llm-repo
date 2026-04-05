# ENV-27 (192.168.23.27) 详细测试过程

> 机器: VM104 / 192.168.23.27
> 更新时间: 2026-04-05 UTC

---

## 一、机器环境信息

| 项目 | 值 |
|------|-----|
| 主机名 | vm104 |
| 系统 | Ubuntu 22.04.3 LTS (Jammy) |
| Kernel | 5.15.0-141-generic |
| GPU | 8× NVIDIA GeForce RTX 4090 (49140 MiB each) |
| NVIDIA Driver | 570.211.01 |
| Kubernetes | v1.32.13 (kubeadm 单节点) |
| CNI | Calico |

---

## 二、环境准备过程

### 2.1 安装 NVIDIA Driver

```bash
# 安装驱动
apt-get install -y nvidia-driver-570-server

# 重启后验证
nvidia-smi
# 输出: NVIDIA GeForce RTX 4090, 49140 MiB
```

### 2.2 安装 NVIDIA Container Toolkit + 配置 runtime

```bash
# 1. 添加 NVIDIA container toolkit 仓库
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit.gpg
echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/nvidia-container-toolkit.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/amd64/ /' > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update -qq
apt-get install -y nvidia-container-toolkit

# 2. 配置 containerd 使用 nvidia runtime
nvidia-ctk runtime configure --runtime=containerd --config=/etc/containerd/config.toml

# 3. 重启 containerd 和 kubelet
systemctl restart containerd
systemctl restart kubelet

# 4. 创建 RuntimeClass
cat > /tmp/nvidia-runtimeclass.yaml << 'EOF'
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nvidia
handler: nvidia
EOF
kubectl apply -f /tmp/nvidia-runtimeclass.yaml
```

### 2.3 安装 Calico CNI

Flannel 与 Volcano admission webhook 存在冲突，改用 Calico：

```bash
curl -x http://127.0.0.1:7890 -fsSL https://docs.projectcalico.org/archive/v3.25/manifests/calico.yaml -o /tmp/calico.yaml
kubectl apply -f /tmp/calico.yaml
```

---

## 三、Volcano 调度器安装与测试

### 3.1 安装 Volcano

```bash
# 下载 Volcano 清单
curl -x http://127.0.0.1:7890 -L -o /tmp/volcano.tar.gz https://github.com/volcano-sh/volcano/archive/refs/tags/v1.10.0.tar.gz
tar -xzf /tmp/volcano.tar.gz -C /tmp

# 应用清单（volcano-development 包含所有组件）
kubectl apply -f /tmp/volcano-1.10.0/installer/volcano-development.yaml

# 去除 master taint（单节点环境需要）
kubectl taint nodes vm104 node-role.kubernetes.io/control-plane:NoSchedule- || true
kubectl taint nodes vm104 node-role.kubernetes.io/master:NoSchedule- || true

# 等待 pods Ready
kubectl get pods -n volcano-system
```

**注意**: volcano-development.yaml 的 admission webhook 在某些环境下会崩溃，如果不需要 PodGroup CRD 的 admission 校验，可直接删除：
```bash
kubectl delete deployment volcano-admission -n volcano-system
kubectl delete mutatingwebhookconfigurations.admissionregistration.k8s.io volcano-admission-service-pods-mutate volcano-admission-service-podgroups-mutate volcano-admission-service-queues-mutate volcano-admission-service-jobs-mutate
```

### 3.2 Volcano Gang Scheduling 测试

```bash
# 创建 Queue
kubectl apply -f - << 'EOF'
apiVersion: scheduling.volcano.sh/v1beta1
kind: Queue
metadata:
  name: default
spec:
  weight: 1
  capability:
    cpu: "64"
    nvidia.com/gpu: "8"
EOF

# 创建 Volcano Job（3 pods，minAvailable: 2）
kubectl apply -f - << 'EOF'
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata:
  name: volcano-gpu-test
spec:
  minAvailable: 2
  queue: default
  schedulerName: volcano
  plugins:
    ssh: []
    env: []
  tasks:
    - replicas: 3
      name: gpu-worker
      policies:
      - event: TaskFailed
        action: RestartJob
      template:
        spec:
          runtimeClassName: nvidia
          containers:
          - name: gpu-test
            image: nvidia/cuda:12.0.0-runtime-ubuntu22.04
            command: ["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv"]
            resources:
              limits:
                nvidia.com/gpu: "1"
          restartPolicy: Never
EOF

# 验证结果
kubectl get vcjob
kubectl logs volcano-gpu-test-gpu-worker-0
```

**预期输出**: 3 个 pod 同时调度并完成gang semantics（minAvailable=2 全部满足后整体推进）

---

## 四、HAMi 调度器安装与测试

### 4.1 安装 HAMi

```bash
# 下载 HAMi chart
curl -x http://127.0.0.1:7890 -L -o /tmp/hami.tgz https://github.com/Project-HAMi/HAMi/releases/download/v2.7.1/hami-2.7.1.tgz

# 使用 helm template 配合 kubectl apply（避免 helm 安装阻塞问题）
helm template hami /tmp/hami.tgz 2>/dev/null | kubectl apply -f -
```

### 4.2 修复 HAMi RBAC 权限问题（关键步骤）

HAMi 包含多个组件，每个都需要正确的 RBAC 权限。以下是需要手动修复的问题：

#### 问题 1: HAMi device plugin 无法读取节点信息

**错误日志**:
```
failed to get node vm104: nodes "vm104" is forbidden: User "system:serviceaccount:default:hami-device-plugin" cannot get resource "nodes"
```

**解决方案**:
```bash
# 修复 device plugin: 需要 GET/LIST/WATCH/PATCH nodes
kubectl create clusterrole hami-device-plugin-node --verb=get,list,watch,patch --resource=nodes
kubectl create clusterrolebinding hami-device-plugin-node --clusterrole=hami-device-plugin-node --serviceaccount=default:hami-device-plugin
```

#### 问题 2: HAMi device plugin 无法访问 pods

**错误日志**:
```
pods "hami-test" is forbidden: User "system:serviceaccount:default:hami-device-plugin" cannot patch resource "pods"
```

**解决方案**:
```bash
# 修复 device plugin: 需要 GET/LIST/WATCH/PATCH pods
kubectl create role hami-device-plugin-pods --verb=get,list,watch,patch --resource=pods --namespace=default
kubectl create rolebinding hami-device-plugin-pods --role=hami-device-plugin-pods --serviceaccount=default:hami-device-plugin --namespace=default
```

#### 问题 3: HAMi scheduler 无法调度 pods

**错误日志**:
```
0/1 nodes are available: 1 node unregistered.
```

**解决方案**:
```bash
# 修复 scheduler: 需要完整 ClusterRole
kubectl create clusterrole hami-scheduler-full --verb=* --resource=*
kubectl create clusterrolebinding hami-scheduler-full --clusterrole=hami-scheduler-full --serviceaccount=default:hami-scheduler
```

#### 问题 4: HAMi device plugin 找不到 libnvidia-ml.so

**错误日志**:
```
could not load NVML library: libnvidia-ml.so.1: cannot open shared object file
```

**解决方案**: 给 device plugin 添加驱动库挂载:
```bash
# 给 device plugin daemonset 打补丁，添加驱动库挂载
kubectl patch daemonset hami-device-plugin -n default --type=json -p '[
  {"op":"add","path":"/spec/template/spec/volumes/0","value":{"hostPath":{"path":"/usr/lib/x86_64-linux-gnu"},"name":"nvidia-libs"}},
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/0","value":{"name":"nvidia-libs","mountPath":"/usr/lib/x86_64-linux-gnu"}},
  {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"LD_LIBRARY_PATH","value":"/usr/lib/x86_64-linux-gnu:/usr/local/cuda/lib64:/usr/local/cuda/compat/lib64:"}}
]'
```

### 4.3 HAMi 基础 GPU 调度测试

```bash
# 创建测试 Pod（使用 hami-scheduler）
cat > /tmp/hami-test.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: hami-test
spec:
  schedulerName: hami-scheduler
  runtimeClassName: nvidia
  containers:
  - name: gpu-test
    image: nvidia/cuda:12.0.0-runtime-ubuntu22.04
    command: ["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv"]
    resources:
      limits:
        nvidia.com/gpu: "1"
  restartPolicy: Never
EOF
kubectl apply -f /tmp/hami-test.yaml
kubectl get pod hami-test
kubectl logs hami-test
```

**预期输出**: STATUS=Completed，nvidia-smi 显示 RTX 4090

### 4.4 HAMi vGPU 共享测试

```bash
# 创建 vGPU 共享 Pod（申请 10GB 显存限制）
cat > /tmp/hami-vgpu-test.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: hami-vgpu-test
spec:
  schedulerName: hami-scheduler
  runtimeClassName: nvidia
  containers:
  - name: gpu-test
    image: nvidia/cuda:12.0.0-runtime-ubuntu22.04
    command: ["nvidia-smi", "--query-gpu=name,memory.used,memory.total", "--format=csv"]
    resources:
      limits:
        nvidia.com/gpu: 1
        nvidia.com/gpumem: 10000
  restartPolicy: Never
EOF
kubectl apply -f /tmp/hami-vgpu-test.yaml
kubectl get pod hami-vgpu-test
kubectl logs hami-vgpu-test
```

**预期输出**: 显存上限被限制在 10000 MiB（10GB），实现 vGPU 共享

---

## 五、最终组件状态

| 组件 | 状态 | 备注 |
|------|------|------|
| NVIDIA Driver 570 | ✅ Running | RTX 4090 × 8 |
| nvidia-container-toolkit | ✅ Configured | runtime: nvidia |
| RuntimeClass nvidia | ✅ Created | 容器使用 nvidia runtime |
| Calico CNI | ✅ Running | 替代 Flannel |
| Volcano Scheduler v1.10.0 | ✅ Running | gang scheduling 正常 |
| Volcano Controllers | ✅ Running | Job CRD 正常 |
| Volcano Admission | ❌ Deleted | 与 device plugin 冲突 |
| HAMi Scheduler v2.7.1 | ✅ Running | hami-scheduler 正常 |
| HAMi Device Plugin v2.7.1 | ✅ Running | vGPU 共享正常 |

---

## 六、已知问题与解决方案汇总

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| kubelet 重启后 swap 重新启用 | /etc/fstab 包含 swap 记录 | swapoff -a && sed -i '/ swap / d' /etc/fstab |
| device plugin 报 "libnvidia-ml.so not found" | 容器未挂载驱动库 | 添加 hostPath volume mount |
| device plugin 报 "node unregistered" | RBAC 缺少 nodes 权限 | 创建 ClusterRole GET/PATCH nodes |
| scheduler 报 "no available nodes" | device plugin 无法 patch node annotation | 添加 nodes patch 权限 |
| admission 报 pods is forbidden | device plugin 缺少 pods patch | 创建 Role GET/PATCH pods |
| Flannel 与 admission 冲突 | webhook 网络不通 | 改用 Calico CNI |
| volcano-admission 崩溃 | 依赖 kube-apiserver 网络 | 删除或修复 admission |
| helm install hami 卡住 | 可能是网络超时 | 使用 helm template + kubectl apply |

---

## 七、测试命令速查

```bash
# GPU 基础测试（默认调度器 + nvidia runtime）
kubectl run gpu-test --image=nvidia/cuda:12.0.0-runtime-ubuntu22.04 --restart=Never \
  --overrides='{"spec":{"runtimeClassName":"nvidia","containers":[{"name":"gpu-test","image":"nvidia/cuda:12.0.0-runtime-ubuntu22.04","command":["nvidia-smi"],"resources":{"limits":{"nvidia.com/gpu":"1"}}}]}}'

# Volcano gang scheduling 测试
kubectl apply -f /tmp/volcano-gpu-test.yaml

# HAMi GPU 调度测试
kubectl apply -f /tmp/hami-test.yaml

# HAMi vGPU 共享测试
kubectl apply -f /tmp/hami-vgpu-test.yaml

# 查看所有 pods
kubectl get pods -A

# 查看节点 allocatable
kubectl get nodes vm104 -o jsonpath='{.status.allocatable}'
```
