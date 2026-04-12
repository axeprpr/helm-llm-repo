# Helm LLM Test Report

Date: 2026-04-12
Target node: `192.168.23.27` (`vm104`)

## 2026-04-12 ENV-27 / VM104 SGLang Smoke

What was verified:

- `charts/sglang-inference` now starts the server with `python3 -m sglang.launch_server`
- the chart now maps SGLang-specific arguments correctly:
  - `--model-path`
  - `--context-length`
  - `--mem-fraction-static`
- the chart now uses `/model_info` for startup, readiness, and liveness probes
- `latest-runtime` is the validated image tag on this node

Real evidence collected:

- pod reached `1/1 Ready` and remained `1/1 Running`
- `/model_info` returned `200`
- `/v1/models` returned `Qwen/Qwen2.5-0.5B-Instruct`
- real `/v1/chat/completions` returned a completion payload

Working values file:

- `examples/vm104-sglang-smoke-values.yaml`

Operational notes:

- the containerd daemon on this node cannot reach `registry-1.docker.io:443` directly; first pull may require proxy-assisted pre-pull
- `/health` still returns `503` on this tested SGLang build even after the server is usable, so probe path must not use `/health`
- with `max_tokens=8`, the completion returned a truncated but valid response payload; service health was verified by endpoint success, not by exact-string matching

---

## 2026-04-12 ENV-27 / VM104 llama.cpp Smoke

What was verified:

- `charts/llamacpp-inference` starts correctly against local GGUF files on this node
- `initContainers.env` support was required to pass proxy variables into the prefetch step
- the validated path on this node is `initContainer + curl -L` into a shared volume, then local `-m /models/...`

Real evidence collected:

- pod reached `1/1 Ready`
- `/health` returned `{"status":"ok"}`
- `/v1/models` listed `qwen2.5-0.5b-instruct-q4_k_m.gguf`
- real `/v1/chat/completions` returned `llamacpp-ok`

Working values file:

- `examples/vm104-llamacpp-smoke-values.yaml`

Operational notes:

- the direct `--hf-repo/--hf-file` path was not reliable here and logged `common_download_file_single_online: HEAD failed`
- GHCR image pulls also need the same proxy-assisted pre-pull strategy when containerd cannot reach `ghcr.io` directly

---

## 2026-04-12 ENV-27 / VM104 vLLM Smoke

What was verified:

- host driver upgraded and active: `580.126.09`
- `runtimeClassName: nvidia` required
- `VLLM_ENABLE_CUDA_COMPATIBILITY` must stay unset on GeForce / RTX
- `charts/vllm-inference` with `v0.17.1-x86_64` now serves real traffic

Real evidence collected:

- `/health` returned `200`
- `/v1/models` returned `Qwen/Qwen2.5-0.5B-Instruct`
- real `/v1/chat/completions` returned a completion
- deleting the serving pod caused a successful Deployment self-heal and service recovery

Working values file:

- `examples/vm104-vllm-smoke-values.yaml`

Key operational note:

- enabling `VLLM_ENABLE_CUDA_COMPATIBILITY` on this GeForce RTX 4090 node caused `Error 803`
- removing it was required for the successful smoke deployment

---

## 2026-04-12 ENV-27 / VM104 vLLM + Volcano Smoke

What was verified:

- `charts/vllm-inference` works with `scheduler.type=volcano` on `VM104`
- the chart now sets `scheduling.k8s.io/group-name` automatically when `scheduler.volcano.createPodGroup=true`
- the explicit `PodGroup` created by the chart is the one actually used by the pod

Real evidence collected:

- pod event `Scheduled` came from `volcano`
- `PodGroup` `vllm-volcano-smoke-vllm-inference` reached `Running`
- pod reached `1/1 Ready`
- `/health` returned `200`
- `/v1/models` returned `Qwen/Qwen2.5-0.5B-Instruct`
- real `/v1/chat/completions` returned a completion payload through the Volcano-scheduled pod

Working values file:

- `examples/vm104-vllm-volcano-smoke-values.yaml`

Operational notes:

- before the chart fix, Volcano auto-created an anonymous PodGroup because the pod was missing `scheduling.k8s.io/group-name`
- the explicit chart-created `PodGroup` stayed `Inqueue` while the anonymous one ran; that was a real chart bug
- this smoke uses a single replica and validates Volcano scheduling integration, not multi-replica gang scheduling

---

## 2026-04-12 ENV-27 / VM104 vLLM + Volcano custom queue smoke

What was verified:

- `smoke-queue` can be referenced by `charts/vllm-inference`
- the explicit `PodGroup` correctly records `spec.queue=smoke-queue`
- the workload is scheduled by `volcano` from the custom queue and serves real traffic

Real evidence collected:

- `Queue smoke-queue` remained `Open` during the positive-path smoke
- `PodGroup vllm-volcano-queue-vllm-inference` reached `Running`
- `PodGroup.spec.queue` was `smoke-queue`
- pod event `Scheduled` came from `volcano`
- service IP: `10.105.125.196`
- `/health` returned `200`
- `/v1/models` returned `Qwen/Qwen2.5-0.5B-Instruct`
- real `/v1/chat/completions` returned `queue-ok`

Working values file:

- `examples/vm104-vllm-volcano-custom-queue-values.yaml`

---

## 2026-04-12 ENV-27 / VM104 vLLM + Volcano auto PodGroup smoke

What was verified:

- `scheduler.volcano.createPodGroup=false` works with `charts/vllm-inference`
- Volcano auto-creates an anonymous `podgroup-<uid>` and schedules the workload successfully

Real evidence collected:

- the workload reached `1/1 Ready`
- Volcano auto-created `podgroup-43aa6b5d-d6de-49bc-b032-a0a846426b5b`
- pod event `Scheduled` came from `volcano`
- service IP: `10.103.232.16`
- `/health` returned `200`
- `/v1/models` returned `Qwen/Qwen2.5-0.5B-Instruct`
- real `/v1/chat/completions` returned `auto-ok`

Working values file:

- `examples/vm104-vllm-volcano-auto-pg-values.yaml`

---

## 2026-04-12 ENV-27 / VM104 vLLM + Volcano gang smoke

What was verified:

- `replicaCount=2` with `scheduler.volcano.groupMinMember=2` works on `VM104`
- both replicas are coordinated by the explicit chart-created `PodGroup`
- the resulting deployment serves real traffic

Real evidence collected:

- deployment reached `2/2 Available`
- both pods reached `1/1 Running`
- `PodGroup vllm-volcano-gang-vllm-inference` reached `Running`
- `MINMEMBER=2`
- `RUNNINGS=2`
- service IP: `10.98.28.21`
- `/health` returned `200`
- `/v1/models` returned `Qwen/Qwen2.5-0.5B-Instruct`
- real `/v1/chat/completions` returned `gang-ok`

Working values file:

- `examples/vm104-vllm-volcano-gang-values.yaml`

---

## 2026-04-12 ENV-27 / VM104 Volcano queue close/open

What was verified:

- the official `vcctl` CLI can operate `smoke-queue`
- queue state transitions `Open -> Closing -> Closed -> Open` succeed on this cluster

Real evidence collected:

- `vcctl queue operate -n smoke-queue -a close` changed the queue from `Open` to `Closing`
- after existing running workloads on `smoke-queue` were removed, the queue became `Closed`
- a new release created while the queue was `Closed` still entered `smoke-queue`
- once GPU resources were released, the workload was eventually scheduled and its `PodGroup` reached `Running`
- `vcctl queue operate -n smoke-queue -a open` returned the queue to `Open`

Operational conclusion:

- on this tested `Volcano v1.10.0` environment, `Closed` was confirmed as a state transition, but it was **not** confirmed as a hard block that prevents all newly created workloads from eventually being scheduled
- this result should be treated as observed version behavior, not as proof of stronger queue admission semantics

---

## 2026-04-12 ENV-27 / VM104 Volcano VCJob quickstart

What was verified:

- Volcano native `batch.volcano.sh/v1alpha1 Job` works on `VM104`
- the job progressed through `Pending -> Running -> Completed`
- the job log was collected successfully

Real evidence collected:

- `vcjob-sleep` reached `Completed`
- `kubectl logs` returned `vcjob-ok`

Working file:

- `examples/volcano-vcjob-sleep.yaml`

Operational notes:

- the first image choice `busybox:1.36` was blocked by Docker Hub `EOF`
- the validated path on this node uses the already-present `docker.io/calico/node:v3.25.0`

---

## 2026-04-12 ENV-27 / VM104 Volcano VCJob policy

What was verified:

- `tasks.policies` with `TaskCompleted -> CompleteJob` works on a real `VCJob`
- job-level `policies` with `PodFailed -> RestartJob` also trigger correctly
- `maxRetry=1` is enforced and the failing job ends in `Failed`

Real evidence collected:

- `vcjob-taskcompleted` reached `Completed`
- both worker pods reached `Completed`
- the still-running `ps` pod entered `Terminating`
- logs contained:
  - `ps-start`
  - `worker-ok`
- `vcjob-restartjob` status contained:
  - `Restarting`
  - `Failed`
  - `retryCount: 1`
- events contained:
  - `Start to execute action RestartJob`

Working assets:

- `examples/volcano-vcjob-taskcompleted.yaml`
- `examples/volcano-vcjob-restartjob.yaml`

Operational notes:

- the `RestartJob` case is validated as a lifecycle/action result, not as an eventually successful retry workload
- with `maxRetry=1`, the correct expected end state is `Failed`, not `Completed`

---

## 2026-04-12 ENV-27 / VM104 Volcano capability queue

What was verified:

- `Queue.spec.capability` works on `VM104`
- `cap-small` with `cpu=8` limits a `4 x 4CPU` deployment to two running pods

Real evidence collected:

- `cap-small.spec.capability.cpu` was `8`
- `capability-demo` produced `2 Running + 2 Pending`

Working files:

- `examples/volcano-capability-queue.yaml`
- `examples/volcano-capability-demo.yaml`

---

## 2026-04-12 ENV-27 / VM104 Volcano multi-node gang

What was verified:

- `worker-1` was recovered from an old cluster state, reset, and re-joined to `vm104`
- the worker was upgraded to `v1.32.13` to match the control plane
- a two-node Volcano cluster now exists on `vm104 + worker-1`
- a `VCJob` with `minAvailable=3` and `3 x 15CPU` can start as a single gang only when both nodes participate

Real evidence collected:

- `worker-1` joined and reached `Ready`
- `multi-gang-vcjob` reached `Running`
- `RUNNINGS=3`
- `multi-gang-vcjob-runner-0` landed on `vm104`
- `multi-gang-vcjob-runner-1` landed on `worker-1`
- `multi-gang-vcjob-runner-2` landed on `vm104`

Working file:

- `examples/volcano-multi-node-gang-vcjob.yaml`

Operational notes:

- `worker-1` initially could not pull `kube-proxy` / `calico` images reliably from the public registry
- the validated recovery path was:
  - reset and join the node
  - stream required images from `vm104`
  - restart the system pods
- `nvidia-device-plugin` also had to be restricted to `gpu=on` nodes to avoid crash noise on the CPU-only worker

---

## 2026-04-12 ENV-27 / VM104 Volcano binpack exploration

What was attempted:

- a two-node `Deployment` with `2 x 6CPU` pods was submitted under `schedulerName=volcano`
- scheduler logs and final pod placement were collected to look for stable `binpack` evidence

Real evidence collected:

- `binpack-demo-c88c86f7c-d5lwj` landed on `vm104`
- `binpack-demo-c88c86f7c-h2ggc` landed on `worker-1`
- the current result does not prove a stable node-packing preference

Conclusion:

- this remains an exploratory case
- it should not yet be treated as a passing `binpack` validation

Working file:

- `examples/volcano-multi-node-binpack-demo.yaml`

---

## 2026-04-12 ENV-27 / VM104 Volcano reclaim exploration

What was attempted:

- scheduler test config was switched to `allocate, backfill, reclaim, preempt`
- two reclaimable queues were created:
  - `queue-a.deserved.cpu=8`
  - `queue-b.deserved.cpu=24`
- `capacity-demo-a` first occupied CPU
- `capacity-demo-b` was then submitted to trigger reclaim from `queue-a`

Observed result:

- scheduler logs confirmed the reclaim path was entered
- queue state and pod state remained:
  - `queue-a allocated cpu=32`
  - `queue-b allocated cpu=4`
  - `capacity-demo-a = 8 Running`
  - `capacity-demo-b = 1 Running + 7 Pending`
- key scheduler evidence:
  - `Queue <queue-b> can not reclaim`

Conclusion:

- this is not yet a passing reclaim smoke
- it is a reproducible single-node reclaim experiment with captured scheduler evidence

Files prepared for continued work:

- `examples/volcano-capacity-queue-a.yaml`
- `examples/volcano-capacity-queue-b.yaml`
- `examples/volcano-capacity-demo-a.yaml`
- `examples/volcano-capacity-demo-b.yaml`

---

## 2026-04-12 ENV-27 / VM104 Volcano preempt exploration

What was attempted:

- scheduler test config was switched to `allocate, backfill, reclaim, preempt`
- both native `Deployment` and native `VCJob` paths were tested
- low-priority and high-priority workloads were created with separate `PriorityClass`

Observed result:

- native `Deployment` path produced scheduler evidence that is not suitable as the main verification path:
  - `task ... has null jobID`
- switching to `VCJob` improved behavior:
  - high-priority `VCJob` entered scheduling normally
- however, no stable positive proof of victim eviction was collected in this session
- key scheduler evidence:
  - `Queue <default> can not reclaim by preempt others`

Conclusion:

- this is not yet a passing preempt smoke
- continued work should stay on the `VCJob` path instead of using `Deployment` as the primary preempt verification object

Files prepared for continued work:

- `examples/volcano-priorityclass-low.yaml`
- `examples/volcano-priorityclass-high.yaml`
- `examples/volcano-preempt-low.yaml`
- `examples/volcano-preempt-high.yaml`

---

## 2026-04-04 Current Session Status

This session was intended to re-run a real deployment validation for
`charts/vllm-inference` with:

- scheduler: `hami-scheduler`
- model: `Qwen/Qwen2.5-0.5B-Instruct-GPTQ` (single GPU)
- required proof: `helm install`, `kubectl get pods`, and real
  `/v1/chat/completions` success

What was attempted from the current Codex workspace:

- direct SSH to `root@192.168.3.42` using the provided password
- fallback check for local `kubectl` / `helm` access from this machine

What blocked execution in this session:

- sandbox network policy rejects outbound sockets, including SSH, with:
  `socket: Operation not permitted`
- the local workspace does not have usable `kubectl` or `helm` binaries/config

Result for this session:

- real deployment on `192.168.3.42`: NOT EXECUTED from this environment
- fallback deployment on `192.168.23.27`: NOT EXECUTED from this environment

Reason:

- the current execution environment cannot reach either target host or cluster,
  so it cannot produce the required real evidence (`Running` pod and live HTTP
  inference)

Repo fix prepared in this session:

- `charts/vllm-inference` now renders `--quantization gptq|awq` when
  `model.format` is set, which is required for the requested GPTQ deployment

## Executive Summary

This report now includes the original 2026-04-03 pass plus 2026-04-04 follow-up reruns for `sglang` and `llama.cpp` on the same node.

What was confirmed:

- The chart had real deployment bugs and was fixed in-repo.
- The environment can serve the local `Qwen3.5-35B-A3B` model with the provided image, but only through the existing compatibility wrapper path.
- HAMI real pod binding works.
- Volcano `PodGroup` creation works.
- Volcano on this node reproduces the expected `UnexpectedAdmissionError` behavior when not using `hami-scheduler`.

What could not be completed as originally requested:

- Real single-GPU inference from Helm did not fit on `1 x RTX 2080 Ti`, even after wrapper patches, CPU offload, tiny context, and single-sequence settings.
- Real TP=2 inference from Helm could not be scheduled without disturbing an existing running service, because HAMI accounting did not actually have two full free GPUs available.
- `GPU6` and `GPU7` are not an NVLink pair on this host. The real topology is `PIX`, not `NV1`.
- The current `sglang` default tag `v0.5.9-cu129-amd64-runtime` is still incompatible with this node's NVIDIA runtime and fails before process start with `cuda>=12.9`.
- A `cu124` retry (`lmsysorg/sglang:v0.4.6.post5-cu124`) is the first tested tag that gets past the NVIDIA prestart hook and starts a real image pull on this node, but the pull did not finish within this session.
- A fresh `llama.cpp` rerun with the known-good chart config again reached real runtime and started downloading the GGUF model through the proxy, but current transfer speed was too slow to wait through full startup in this session.

## Chart Bugs Fixed

### 1. vLLM CLI invocation was wrong for the deployed image

Observed failure:

- `ValueError: With vllm serve, you should provide the model as a positional argument`

Fix:

- Changed the generated command from `vllm serve --model ...` to `vllm serve <model> ...`.

### 2. Chart did not expose HAMI policy fields

Observed problem:

- `scheduler.hami.nodeSchedulerPolicy` and `scheduler.hami.gpuSchedulerPolicy` existed in values but were not rendered into pod annotations.

Fix:

- Wired them into pod annotations as:
  - `hami.io/node-scheduler-policy`
  - `hami.io/gpu-scheduler-policy`

### 3. Chart needed command/args override support

Observed problem:

- The only local model on this host requires the existing wrapper script `python3 /scripts/start_vllm.py`.
- The chart hard-coded `/bin/bash -c "vllm serve ..."`, so there was no way to reuse the only working runtime path.

Fix:

- Added `command` and `args` value overrides.

### 4. Chart lacked `startupProbe` support

Observed problem:

- Large model startup needs a long startup window.

Fix:

- Added optional `startupProbe` rendering.

### 5. `enableChunkedPrefill` key typo

Observed problem:

- Values file had `enableChunkedPrell`.

Fix:

- Renamed to `enableChunkedPrefill`.

### 6. Metadata `podLabels` placement bug

Observed problem:

- `podLabels` were rendered at the wrong metadata level in the Deployment manifest.

Fix:

- Moved them under `metadata.labels`.

## Environment Validation

### Cluster

- `kubectl version`: `v1.28.9`
- Runtime: `containerd://1.7.27`

### GPU topology actually observed

`nvidia-smi topo -m` showed:

- `GPU0 <-> GPU3 = NV1`
- `GPU6 <-> GPU7 = PIX`

This is the opposite of the original request assumption for `GPU6/GPU7`.

### Model/runtime baseline

The existing deployment `llm-serving/qwen35-35b-predictor` was used as a baseline sanity check:

- Health check succeeded.
- Real `/v1/chat/completions` request returned a completion payload.

That proves:

- the model files in `/opt/models/qwen3.5-35b` are valid,
- the image `docker.io/vllm/vllm-openai:v0.11.0-x86_64` can work here,
- the wrapper script path is required for this model/image combination.

## Real Test Results

| ID | Scenario | Result | Evidence |
|---|---|---|---|
| SCN-01 | Existing baseline inference | PASS | Live completion returned from `qwen35-35b-predictor` |
| SCN-02 | HAMI single-GPU scheduling | PASS | Pod scheduled by `hami-scheduler`, bound to GPU UUID `GPU-e099...` |
| SCN-02 | HAMI single-GPU inference | BLOCKED by hardware/model limit | Wrapper path still failed with `torch.OutOfMemoryError`, missing `512 MiB` on 1x2080 Ti |
| SCN-03 | HAMI TP=2 scheduling | BLOCKED by live cluster allocation | HAMI reported `AllocatedCardsInsufficientRequest`, `CardInsufficientMemory`, `CardUuidMismatch` |
| SCN-04 | Volcano PodGroup creation | PASS | `PodGroup` created in `llm-serving` and entered `Inqueue` |
| SCN-05 | Volcano real pod scheduling | PASS for failure reproduction | Volcano scheduled pods to `axe-master`, kubelet rejected them with `UnexpectedAdmissionError` |
| SCN-06 | llama.cpp HAMI single-GPU inference | PASS | Real `/v1/chat/completions` returned `HELM_LLAMACPP_OK` on GPU `7` |
| SCN-07 | sglang HAMI single-GPU deployment | BLOCKED by image compatibility / pull time | `latest` and `v0.5.9-cu129-amd64-runtime` both fail the NVIDIA prestart hook (`cuda>=12.9`); `v0.4.6.post5-cu124` binds GPU `7` and starts pulling |

## Detailed Findings

### HAMI single-GPU result

Release used:

- `vllm-hami-1gpu`
- explicit GPU UUID pin to GPU `7`
- wrapper command `python3 /scripts/start_vllm.py`
- CPU offload enabled

Observed:

- HAMI scheduling and binding worked exactly as expected.
- Pod annotation showed:
  - `hami.io/vgpu-devices-allocated: GPU-e099b988-e339-e561-2506-0bd2b99201b3,...`
- The model still failed to load on a single 2080 Ti.

Final error:

- `torch.OutOfMemoryError`
- still short by `512 MiB`
- reproduced even after reducing:
  - `max_model_len` to `256`
  - `max_num_batched_tokens` to `64`
  - `max_num_seqs` to `1`
  - `cpu_offload_gb` to `80`

Conclusion:

- With the only available local model, real single-GPU inference is not feasible on this hardware.

### HAMI TP=2 result

Release used:

- `vllm-hami-tp2`

Observed blockers:

- One stale failed KServe pod was holding a HAMI allocation and was deleted.
- After cleanup, the still-running KServe service continued to hold two HAMI GPUs.
- HAMI scheduling for the Helm TP=2 release still failed.

Representative scheduler errors:

- `AllocatedCardsInsufficientRequest`
- `CardInsufficientMemory`
- `CardUuidMismatch`

Conclusion:

- A second full HAMI-allocatable GPU was not actually free at test time.
- Real TP=2 inference could not be completed without disturbing an existing live service.

### Volcano result

Release used:

- `vllm-volcano-1gpu`

Observed:

- `PodGroup` was created correctly.
- With HAMI-like UUID/full-memory constraints, the `PodGroup` remained `Inqueue`.
- With plain `nvidia.com/gpu: 1`, Volcano did schedule the pod to `axe-master`, but kubelet rejected it with:

`Allocate failed due to rpc error: code = Unknown desc = no binding pod found on node axe-master, which is unexpected`

Conclusion:

- The cluster behavior matches the task background: non-HAMI scheduling paths reproduce `UnexpectedAdmissionError` on this node.

### llama.cpp result

Release used:

- `llamacpp-smoke`
- HAMI scheduler with explicit GPU UUID pin to GPU `7`
- image `ghcr.io/ggerganov/llama.cpp:server-cuda-b4719`
- model `Qwen/Qwen2.5-0.5B-Instruct-GGUF`
- GGUF file `qwen2.5-0.5b-instruct-q4_k_m.gguf`

Observed chart bugs before the final PASS:

- `image.tag` was ignored when `image.autoBackend=true`, so the chart kept rendering the broken default `server-cuda` tag.
- The chart invoked `llama-server` from `PATH`, but the real binary inside the tested image is `/app/llama-server`.
- The chart passed a Hugging Face repo/file pair to `-m` as if it were a local filesystem path. The correct runtime path for download-on-startup is `-hf <repo>:<quant>`.
- Cold-start model download exceeded the default health-check window, so `startupProbe` support was required for real-world deployments.

Final verified behavior:

- HAMI scheduled and bound the pod to GPU UUID `GPU-e099b988-e339-e561-2506-0bd2b99201b3`.
- The image started successfully on RTX 2080 Ti (`compute capability 7.5`).
- The GGUF file downloaded from Hugging Face and loaded into `/root/.cache/llama.cpp/...`.
- `/health` returned `{"status":"ok"}`.
- Real inference succeeded:
  - request asked for exact reply `HELM_LLAMACPP_OK`
  - response content was `HELM_LLAMACPP_OK`

Conclusion:

- `charts/llamacpp-inference` now works for real single-GPU HAMI deployments on this node once the correct image tag and runtime flags are rendered.
- A 2026-04-04 rerun with the same image and HAMI UUID pin again passed scheduling, reached `Running`, and started a real GGUF download through the proxy.
- That rerun did not finish within the session because the current download rate dropped to roughly a few hundred KB/s, so `/health` remained `503` during model fetch rather than exposing a new chart/runtime regression.

### sglang result

Release used:

- `sglang-smoke`
- HAMI scheduler with explicit GPU UUID pin to GPU `7`
- proxy envs `http_proxy` and `https_proxy` set to `http://192.168.3.42:7890`
- image `lmsysorg/sglang:latest`, then compatibility retry with `lmsysorg/sglang:v0.5.9-cu129-amd64-runtime`
- model `Qwen/Qwen2.5-0.5B-Instruct`

Observed chart/runtime behavior:

- After chart fixes, HAMI scheduling and GPU UUID binding worked correctly.
- The pod was created and assigned to `axe-master`.
- Lowercase proxy env injection rendered correctly in the live pod spec.
- `lmsysorg/sglang:latest` now pulls on this host, but crashes before process start.
- A pinned `v0.5.9-cu129-amd64-runtime` image does not solve the node compatibility problem on this host.

Final observed `latest` error:

- `nvidia-container-cli: requirement error: unsatisfied condition: cuda>=12.9`
- host driver on `axe-master` is `570.211.01`
- result: container never reaches the `python -m sglang ...` process when using `latest`

Pinned-image follow-up:

- Re-test on 2026-04-04 with `model=sshleifer/tiny-gpt2` confirmed that `lmsysorg/sglang:v0.5.9-cu129-amd64-runtime` still fails before process start with:
  - `nvidia-container-cli: requirement error: unsatisfied condition: cuda>=12.9`
- Compatibility retry `lmsysorg/sglang:v0.4.6.post5-cu124` was the first image that:
  - passed HAMI scheduling,
  - bound GPU UUID `GPU-e099b988-e339-e561-2506-0bd2b99201b3`,
  - avoided the immediate CUDA prestart rejection,
  - and entered real image pull (`Pulling image "lmsysorg/sglang:v0.4.6.post5-cu124"`).
- The `cu124` image had not finished pulling by the end of the session, so `/health` and `/v1/completions` were not yet verified.

Conclusion:

- The remaining `sglang` failure is not a Helm template failure.
- The chart now reaches the real scheduler and runtime boundary cleanly.
- Both the floating `latest` tag and the current pinned `v0.5.9-cu129-amd64-runtime` default are incompatible with this node's CUDA/driver combination.
- The first tested candidate that passes the runtime compatibility gate here is `lmsysorg/sglang:v0.4.6.post5-cu124`.
- The chart should not default to a `cu129` image on this host class without verifying the node driver/runtime first.

## What This Means

The repo is now materially better than before:

- it can target the real wrapper command path,
- it renders HAMI policy knobs correctly,
- it no longer emits an invalid `vllm serve --model` invocation for the deployed image,
- it supports `startupProbe` for long model startup.
- it renders working llama.cpp image/tag overrides instead of forcing a broken floating CUDA tag,
- it uses the real `/app/llama-server` binary path,
- it uses the correct llama.cpp Hugging Face startup flags for GGUF download-on-startup,
- it uses the correct SGLang upstream image repository and a pinned non-`latest` default tag,
- it exposes proxy env injection for real environments that need outbound model/image access.

The remaining failures are not fake-test failures. They are real environment constraints:

- no smaller downloadable model was reachable,
- the only local model is too large for single-GPU 2080 Ti inference,
- TP=2 was blocked by current HAMI allocations on the live node,
- `GPU6/GPU7` are not an NVLink pair on this host,
- Volcano plus this node configuration reproduces `UnexpectedAdmissionError`.

## Recommended Next Actions

To finish the originally requested PASS matrix, one of these must change:

1. Provide a smaller local model or restore outbound access to download one.
2. Free a second HAMI-allocatable GPU by scaling down or moving the existing `qwen35-35b-predictor` service.
3. If NVLink is mandatory, free the actual NVLink-connected pair on this host instead of targeting `GPU6/GPU7`.
4. Verify whether `lmsysorg/sglang:v0.4.6.post5-cu124` fully starts after the image pull completes, then promote that tag only if `/health` and a real completion succeed.
5. Stop using `v0.5.9-cu129-amd64-runtime` as the assumed-compatible default for this node until the driver/runtime is upgraded.
6. If operators need a newer SGLang image than a `cu124`-class tag, upgrade the node driver/runtime first and only then override `image.tag`.

## References

- vLLM serve CLI: <https://docs.vllm.ai/en/latest/cli/serve.html>
- HAMi scheduler docs: <https://project-hami.io/docs/userguide/scheduler/scheduler/>
- HAMi specific GPU selection: <https://project-hami.io/docs/userguide/nvidia-device/examples/specify-certain-card/>
- Volcano PodGroup docs: <https://volcano.sh/en/docs/podgroup/>
- SGLang Docker install docs: <https://docs.sglang.ai/start/install.html>
- llama.cpp container package tags: <https://github.com/ggerganov/llama.cpp/pkgs/container/llama.cpp>

---

## 2026-04-04 Afternoon Session — vLLM Chart Fixes + Real Deployment Attempts

### Bugs Fixed in This Session

#### Bug 1: `gpuMemoryUtilization` format string broken with integer helm values
- **File**: `charts/vllm-inference/templates/_helpers.tpl`
- **Symptom**: `helm install --set engine.gpuMemoryUtilization=50` rendered as `--gpu-memory-utilization %!f(int64=50)`
- **Root cause**: `printf "%.2f"` template fails when helm passes an integer instead of float
- **Fix**: Changed to `printf "%v"` which accepts both int and float

#### Bug 2: `extraArgs` elements rendered as single string instead of separate args
- **File**: `charts/vllm-inference/templates/_helpers.tpl`
- **Symptom**: `--set engine.extraArgs[0]=--dtype --set engine.extraArgs[1]=half` rendered as `--dtype half` as a single concatenated string, causing `vllm: error: unrecognized arguments: [--dtype half]`
- **Root cause**: `append $args .Values.engine.extraArgs` appends the list as one element
- **Fix**: Changed to `concat $args .Values.engine.extraArgs`

#### Bug 3: `startupProbe: {}` caused nil probe on GPU 2080 Ti
- **File**: `charts/vllm-inference/values.yaml`
- **Symptom**: Large model startup > startupProbe's default 10s × 3 = 30s timeout
- **Fix**: Replaced with proper `httpGet` probe at `/health:8000` with 30s initialDelay, 30s period, 30× failureThreshold

#### Bug 4: `volumes: []` / `volumeMounts: []` were empty in values.yaml
- **Symptom**: Model cache from hostPath not accessible inside container
- **Fix**: Added `volumes` with `hostPath: /mnt/models` and `volumeMounts` at `/HF_cache`

### Real Deployment Attempt — 192.168.3.42 (8× RTX 2080 Ti)

**Model**: `Qwen/Qwen2.5-0.5B-Instruct` (pre-downloaded at `/mnt/models`)
**Image**: `vllm/vllm-openai:v0.8.5.post1`

#### Attempt 1: Hami scheduler + `--dtype half`
- **Status**: CrashLoopBackOff
- **Error**: `torch.OutOfMemoryError` on GPU 0 (vLLM saw all 8 GPUs, not just the Hami-assigned one)
- **Root cause**: Hami webhook injects `NVIDIA_VISIBLE_DEVICES=GPU-UUID` but NOT `CUDA_VISIBLE_DEVICES`. PyTorch sees all GPUs and defaults to GPU 0, which has other processes using ~17 GiB → OOM on KV cache allocation.

#### Attempt 2: Default scheduler + `CUDA_VISIBLE_DEVICES=6` extraEnv
- **Status**: `UnexpectedAdmissionError` (Hami device plugin rejects pods with manually set CUDA_VISIBLE_DEVICES)
- **Note**: Hami device plugin requires pods to NOT set CUDA_VISIBLE_DEVICES manually; it injects it automatically

#### Attempt 3: KServe InferenceService (reference deployment)
- Existing pod `llm-serving/qwen35-35b-predictor` has `CUDA_VISIBLE_DEVICES=1,0` injected
- **How**: KServe's own mutating webhook (not Hami's) injects `CUDA_VISIBLE_DEVICES` based on `nvidia.com/gpu` resource requests
- This means: **vLLM deployments through this helm chart need either KServe runtime or manual CUDA_VISIBLE_DEVICES injection**

### RTX 2080 Ti Hardware Compatibility

- GPU compute capability: **sm_75 (7.5)** — does NOT support bfloat16
- vLLM v0.8.5+ requires `dtype=half` or `dtype=float16` on sm_75
- vLLM v0.11+ uses V1 engine which requires compute ≥ 8.0 (sm_80+)
- **Recommendation**: Use `vllm/vllm-openai:v0.8.5.post1` (last version supporting sm_75) + `--dtype half`

### Key Discovery: Hami Device Plugin Limitation

| Injection target | Hami webhook | KServe webhook | Result |
|---|---|---|---|
| `NVIDIA_VISIBLE_DEVICES` | ✅ Injected | ✅ Injected | Sets GPU UUID visibility |
| `CUDA_VISIBLE_DEVICES` | ❌ NOT injected | ✅ Injected | PyTorch GPU selection |

**Impact**: Pure helm + Hami deployments require manual workaround (e.g., initContainer or post-binding script) to set `CUDA_VISIBLE_DEVICES` matching the Hami-assigned GPU.

### Workaround Options

1. **KServe runtime** (already working in cluster): Use `InferenceService` with `runtime: vllm-qwen35-2080ti`
2. **InitContainer workaround**: Pre inject `CUDA_VISIBLE_DEVICES` by reading `NVIDIA_VISIBLE_DEVICES` from downward API
3. **Host path direct** (chosen for this session): nerdctl with `--gpus=X` on host (CNM networking conflict prevents container run)

### 23.27 Environment (8× RTX 4090)

- Not tested in this session — SSH access not confirmed
- RTX 4090 = sm_89, no bfloat16 limitation, much more capable
- **Recommended for future testing** once network/SSH access is resolved

### Commit Summary

```
fix(_helpers.tpl): fix gpuMemoryUtilization format and extraArgs concat
fix(values.yaml): add startupProbe, volumes, volumeMounts for model cache
```


---

## 2026-04-04 Late Morning Session — llama.cpp + Hami 部署实测

### 环境状态
- **192.168.3.42**: GPU 0-5 被占用，GPU 6/7 空闲
- **Hami 调度器**: 正常（Pod 绑定到 GPU 6/7）
- **Hami device plugin**: 注入 `NVIDIA_VISIBLE_DEVICES=GPU-UUID`，不注入 `CUDA_VISIBLE_DEVICES`

### llama.cpp + Hami 部署（进行中）

**Chart**: `charts/llamacpp-inference`
**Values**:
```yaml
gpuType: nvidia
image:
  autoBackend: false
  repository: ghcr.io/ggerganov/llama.cpp
  tag: server-cuda-b4719
model:
  name: Qwen/Qwen2.5-0.5B-Instruct-GGUF
  ggufFile: qwen2.5-0.5b-instruct-q4_k_m.gguf
  downloadOnStartup: true
engine:
  port: 8000
  contextSize: 2048
  gpuLayers: -1
  tensorParallelSize: 1
env:
  - name: http_proxy
    value: http://192.168.3.42:7890
  - name: https_proxy
    value: http://192.168.3.42:7890
scheduler:
  name: hami-scheduler
```

**观察**:
- `helm install` 成功，Pod 在 Running 状态
- llama.cpp 进程已启动（PID 1），检测到 1 个 CUDA 设备（compute 7.5）
- GPU 6/7 显示 0 MiB（模型未加载）
- `/health` 尚未就绪（模型下载中）
- 模型下载速度受限于代理带宽，预计需要数分钟

**渲染的命令**:
```
/app/llama-server -hf Qwen/Qwen2.5-0.5B-Instruct-GGUF:Q4_K_M -fa --host 0.0.0.0 --port 8000 --ctx-size 2048 --n-gpu-layers -1 --batch-size 512 --parallel 4
```

### Hami + vLLM 核心问题（已确认）

**问题**: Hami device plugin 的 MutatingWebhookConfiguration 只注入 `NVIDIA_VISIBLE_DEVICES`（GPU UUID），不注入 `CUDA_VISIBLE_DEVICES`。

| 环境变量 | Hami webhook | KServe webhook | vLLM 行为 |
|---|---|---|---|
| `NVIDIA_VISIBLE_DEVICES` | ✅ 注入 | ✅ 注入 | 控制 nvidia-container-toolkit 可见 GPU |
| `CUDA_VISIBLE_DEVICES` | ❌ 不注入 | ✅ 注入 | 控制 PyTorch GPU 索引选择 |

**结果**: vLLM worker 子进程看到所有 8 张 GPU（因为没有 `CUDA_VISIBLE_DEVICES` 限制），默认选择 GPU 0（已被占用）→ OOM。

**解决方案**:
1. 使用 KServe InferenceService（KServe 的 mutating webhook 额外注入了 `CUDA_VISIBLE_DEVICES`）
2. 给 Pod 加 initContainer，从 downward API 读取 Hami 分配的 GPU UUID 并设置 `CUDA_VISIBLE_DEVICES`
3. 换用默认调度器 + 手动 GPU 分配（Hami device plugin 拒绝已设置 `CUDA_VISIBLE_DEVICES` 的 Pod）

### RTX 2080 Ti (sm_75) 兼容的 vLLM 版本
- **最后支持 sm_75 的版本**: `vllm/vllm-openai:v0.8.5.post1`
- **必须参数**: `--dtype half`（不能用 bfloat16）
- **推荐参数**: `--enforce-eager`（sm_75 不支持 CUDA graph）

### 已提交 Commit
```
bbf37af fix(vllm): gpuMemoryUtilization format, extraArgs concat, startupProbe, volumes
f8ea6f3 fix: add --quantization flag for gptq/awq model formats
```


---

## 2026-04-04 10:06 UTC — llama.cpp + Hami 真实推理 PASS ✅

### 测试结果

| 字段 | 值 |
|------|-----|
| Chart | `llamacpp-inference` |
| 调度器 | `hami-scheduler` |
| GPU | GPU 7 (RTX 2080 Ti) |
| Hami 分配 | `GPU-e099b988-e339-e561-2506-0bd2b99201b3` |
| 模型 | `/llm-model/qwen2.5-0.5b-instruct-q4_k_m.gguf` (469MB, Q4_K_M) |
| GGUF 文件 | 预下载到 `/mnt/models/llama-cache/gguf/` |
| Pod IP | 10.0.0.75 |
| 推理结果 | ✅ 返回正确（Hello / 4）|

### Values 配置
```yaml
gpuType: nvidia
image:
  autoBackend: false
  repository: ghcr.io/ggerganov/llama.cpp
  tag: server-cuda-b4719
model:
  name: /llm-model/qwen2.5-0.5b-instruct-q4_k_m.gguf
  downloadOnStartup: false
engine:
  port: 8000
  contextSize: 2048
  gpuLayers: -1
  tensorParallelSize: 1
volumes:
  - name: llm-model
    hostPath:
      path: /mnt/models/llama-cache/gguf
      type: Directory
volumeMounts:
  - name: llm-model
    mountPath: /llm-model
scheduler:
  name: hami-scheduler
```

### 踩坑记录

1. **GGUF 文件下载慢**: 之前用 `downloadOnStartup: true` 走代理下载，代理速度慢导致 liveness probe 超时重启。解决：先用 `huggingface-cli` 在 host 上下载模型，再通过 `hostPath` 挂载。

2. **volume hostPath type 类型错误**: 第一次用 `type: File`，但挂载路径是目录，kubelet 报错 `hostPath type check failed`。解决：改 `type: Directory`。

3. **镜像 tag 被忽略**: `image.autoBackend: true` 时 chart 会忽略 `image.tag`。解决：设 `autoBackend: false` 强制使用指定 tag。

### 渲染的命令
```
/app/llama-server -m /llm-model/qwen2.5-0.5b-instruct-q4_k_m.gguf -fa --host 0.0.0.0 --port 8000 --ctx-size 2048 --n-gpu-layers -1 --batch-size 512 --parallel 4
```

### 推理验证

```bash
# 请求1
$ curl -X POST http://10.0.0.75:8000/v1/chat/completions \
  -d '{"model":"/llm-model/qwen2.5-0.5b-instruct-q4_k_m.gguf",
       "messages":[{"role":"user","content":"Say hi in one word"}]}'
# 响应: {"content":"Hello"}

# 请求2
$ curl -X POST http://10.0.0.75:8000/v1/chat/completions \
  -d '{"model":"/llm-model/qwen2.5-0.5b-instruct-q4_k_m.gguf",
       "messages":[{"role":"user","content":"What is 2+2? Answer in one number"}]}'
# 响应: {"content":"4"}
```

### GPU 内存使用
```
GPU 7: 595 MiB used (model loaded on RTX 2080 Ti)
```


---

## 2026-04-04 11:00 UTC — vLLM + Hami 核心问题确认

### 问题现象

vLLM Pod 通过 Hami 调度器分配到 GPU 6（或 7），Pod Running 但：
1. Hami device plugin 只注入 `NVIDIA_VISIBLE_DEVICES=GPU-UUID`，不注入 `CUDA_VISIBLE_DEVICES`
2. vLLM 引擎进程启动后，在加载模型阶段 OOM 崩溃（GPU 0 已被 21 GB 占用）
3. Pod 进入 CrashLoopBackOff

### 根本原因

```
Hami device plugin 注入: NVIDIA_VISIBLE_DEVICES=GPU-e099b988-...  (UUID)
vLLM 期望:          CUDA_VISIBLE_DEVICES=6                    (索引)
```

NVIDIA_VISIBLE_DEVICES 控制 nvidia-container-runtime 的 GPU 可见性，但 PyTorch/vLLM 默认使用 GPU 0（索引 0），即使用户分配了 GPU 6。

### 已验证的事实

| 场景 | 结果 | 原因 |
|------|------|------|
| llama.cpp + Hami | ✅ 成功 | llama.cpp 直接调用 CUDA，无 pynvml GPU 检测 |
| vLLM + Hami | ❌ OOM | pynvml 检测 GPU 失败，fallback 到 GPU 0 |
| vLLM + `CUDA_VISIBLE_DEVICES=6` extraEnv | ❌ UnexpectedAdmissionError | Hami device plugin 拒绝已设置 CUDA_VISIBLE_DEVICES 的 Pod |
| vLLM + KServe ISVC | ✅ 成功 | KServe mutating webhook 额外注入了 `CUDA_VISIBLE_DEVICES` |

### RTX 2080 Ti GPU 占用情况（192.168.3.42）
```
GPU 0: 21193 MiB (被占用)
GPU 1: 21655 MiB (被占用)
GPU 2: 17763 MiB (被占用)
GPU 3: 20503 MiB (被占用)
GPU 4: 17763 MiB (被占用)
GPU 5: 17763 MiB (被占用)
GPU 6: 0 MiB (空闲，可用于测试)
GPU 7: 0 MiB (空闲，可用于测试)
```

### vLLM 修复方案（需要修改 Chart）

在 Pod template 中加入 initContainer，从 Hami 分配的 `NVIDIA_VISIBLE_DEVICES` (UUID) 解析出 GPU 索引，并设置 `CUDA_VISIBLE_DEVICES`：

```yaml
initContainers:
  - name: inject-cuda-visible-devices
    image: vllm/vllm-openai:v0.8.5.post1
    command: [sh, -c]
    args:
      - |
        # NVIDIA_VISIBLE_DEVICES is set by Hami device plugin as GPU-UUID
        # Convert UUID to index and export CUDA_VISIBLE_DEVICES
        NVIDIA_VISIBLE_DEVICES="${NVIDIA_VISIBLE_DEVICES:-all}"
        if [ "$NVIDIA_VISIBLE_DEVICES" != "all" ]; then
          GPU_UUID=$(echo $NVIDIA_VISIBLE_DEVICES | cut -d, -f1)
          # Query index via nvidia-smi
          GPU_INDEX=$(nvidia-smi -L | grep $GPU_UUID | sed 's/GPU \([0-9]\).*/\1/')
          echo "GPU UUID=$GPU_UUID -> Index=$GPU_INDEX"
          echo "CUDA_VISIBLE_DEVICES=$GPU_INDEX" > /env-inject/cuda_env
        fi
    env:
    - name: NVIDIA_VISIBLE_DEVICES
      valueFrom:
        fieldRef:
          fieldPath: spec.containers[0].env[?(@.name==\"NVIDIA_VISIBLE_DEVICES\")].value
    volumeMounts:
    - name: env-inject
      mountPath: /env-inject
volumes:
- name: env-inject
  emptyDir: {}
```

然后主容器从 `/env-inject/cuda_env` 读取并 `source` 该文件。

### Chart Bug: `gpuMemoryUtilization` + `extraArgs` 渲染问题

#### Bug 1: `%.2f` format string 不兼容整数 helm values
- **症状**: `--set engine.gpuMemoryUtilization=50` → `--gpu-memory-utilization %!f(int64=50)`
- **根因**: `printf "%.2f"` 在 helm 传整数时报错
- **修复**: 改为 `printf "%v"`

#### Bug 2: `extraArgs` 作为单个元素 append
- **症状**: `--set engine.extraArgs[0]=--dtype --set engine.extraArgs[1]=half` → `--dtype half`（拼接成一个字符串）
- **根因**: `append $args .Values.engine.extraArgs` 把列表当单个元素加入
- **修复**: 改为 `concat $args .Values.engine.extraArgs`

#### Bug 3: `startupProbe: {}` 导致 liveness 提前杀死 Pod
- **症状**: 大模型启动 > 30s，liveness probe 失败，Pod 重启
- **修复**: 设置合理的 `startupProbe.initialDelaySeconds=30`, `failureThreshold=30`


---

## 2026-04-04 11:15 UTC — Hami + Volcano 配合方式调研

### 关键发现：Hami 和 Volcano vGPU 是两套独立方案

经过对官方文档的调研，发现 Hami 和 Volcano vGPU 是**两条独立的技术路线**，不能简单叠加使用：

#### 方案 A：Hami vGPU（当前集群已部署）
- **架构**：Hami scheduler（kube-scheduler + Hami extender）+ Hami device plugin
- **调度**：Pod 指定 `schedulerName: hami-scheduler`
- **资源**：使用 `nvidia.com/gpu` 资源
- **GPU 可见性注入**：Hami webhook 只注入 `NVIDIA_VISIBLE_DEVICES`（GPU UUID），**不注入** `CUDA_VISIBLE_DEVICES`
- **现状**：llama.cpp 正常（直接调用 CUDA），vLLM 异常（pynvml 默认选 GPU 0）

#### 方案 B：Volcano vGPU（需额外安装）
- **架构**：Volcano scheduler（配置 `deviceshare` plugin）+ Volcano vGPU device plugin
- **调度**：Pod 指定 `schedulerName: volcano` 或不指定（使用默认 scheduler）
- **资源**：使用 `volcano.sh/vgpu-number`、`volcano.sh/vgpu-memory`、`volcano.sh/vgpu-cores`
- **安装方式**：
  ```bash
  # 1. 更新 Volcano scheduler 配置，启用 deviceshare plugin
  kubectl edit cm -n volcano-system volcano-scheduler-configmap
  # 添加: plugins: - deviceshare (并设置 deviceshare.VGPUEnable: true)

  # 2. 部署 volcano-vgpu-device-plugin
  kubectl create -f https://raw.githubusercontent.com/Project-HAMi/volcano-vgpu-device-plugin/main/volcano-vgpu-device-plugin.yml
  ```
- **Pod 申请示例**：
  ```yaml
  resources:
    limits:
      volcano.sh/vgpu-number: 1
      volcano.sh/vgpu-memory: 3000  # 可选：每个 vGPU 3GB 显存
      volcano.sh/vgpu-cores: 50    # 可选：每个 vGPU 50% 核心
  ```

### 两者能否配合使用？

**答案：不能简单叠加。** 原因：

1. Hami device plugin 使用 `nvidia.com/gpu` 资源；Volcano vGPU device plugin 使用 `volcano.sh/vgpu-*` 资源
2. 如果同时安装两个 device plugin，会产生资源冲突
3. Volcano vGPU 需要 Volcano scheduler 配置 `deviceshare` plugin，这与 Hami 的调度机制完全不同

### 正确的组合方式

| 方案 | Scheduler | Device Plugin | 资源类型 | CUDA_VISIBLE_DEVICES |
|------|-----------|---------------|---------|---------------------|
| A（Hami） | `hami-scheduler` | Hami device plugin | `nvidia.com/gpu` | ❌ 不注入 |
| B（Volcano） | `volcano` | Volcano vGPU device plugin | `volcano.sh/vgpu-*` | ✅ 由 device plugin 注入 |

### 当前集群的实际状态

```
nvidia.com/gpu: 80        # Hami device plugin 提供
volcano.sh/vgpu-*: 无      # Volcano vGPU device plugin 未安装
```

### 如果要用 vLLM + GPU 共享，推荐方案

1. **方案 A（当前 Hami）**：修改 Hami chart，增加 `CUDA_VISIBLE_DEVICES` 注入
   - 在 Pod template 中加入 initContainer，从 downward API 读取 `nvidia.com/gpu` 分配，然后设置 `CUDA_VISIBLE_DEVICES`
   - 这个方案改动最小

2. **方案 B（切换到 Volcano vGPU）**：卸载 Hami，安装 Volcano vGPU device plugin
   - 需要额外部署 `volcano-vgpu-device-plugin`
   - Pod resource 请求格式改变
   - **优点**：Volcano 原生支持 gang scheduling、队列、优先级调度

### 下一步建议

1. **短期**：在 vllm-inference chart 中增加 initContainer workaround，注入 `CUDA_VISIBLE_DEVICES`
2. **中期**：在集群中部署 Volcano vGPU device plugin，切换到方案 B
3. **长期**：将 Hami chart 贡献 `CUDA_VISIBLE_DEVICES` injection 功能到上游

---

## 2026-04-12 ENV-27 / VM104 Volcano multi-node preempt

What was verified:

- a low-priority `VCJob` can first occupy both nodes
- a later high-priority `VCJob` can trigger real Volcano preemption
- the victim pod is evicted and the high-priority pod eventually runs on the reclaimed node

Real evidence collected:

- `preempt-low` first reached `Running` with:
  - `preempt-low-runner-0` on `vm104`
  - `preempt-low-runner-1` on `worker-1`
- scheduler logs contained:
  - `Try to preempt Task <volcano-single/preempt-low-runner-1> for Task <volcano-single/preempt-high-runner-0>`
  - `Evicting pod volcano-single/preempt-low-runner-1, because of preempt`
- pod events contained:
  - `Evict`
  - `Killing`
- `preempt-high-runner-0` finally reached `1/1 Running` on `worker-1`

Working assets:

- `examples/volcano-priorityclass-low.yaml`
- `examples/volcano-priorityclass-high.yaml`
- `examples/volcano-multi-node-preempt-low.yaml`
- `examples/volcano-multi-node-preempt-high.yaml`

Operational notes:

- this is a real positive `preempt` result, not just a pending-state observation
- after preemption, the lower-priority `VCJob` falls back to `Pending` because its `minAvailable=2` can no longer be satisfied
- current `reclaim` tests in the same two-node environment still do not produce positive reclaim evidence
