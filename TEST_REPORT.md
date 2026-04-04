# Helm LLM Test Report

Date: 2026-04-04
Target node: `192.168.3.42` (`axe-master`)

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
