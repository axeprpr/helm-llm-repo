# Helm LLM Test Scenarios

Date: 2026-04-03

## Scope

This plan covers real deployment validation for `charts/vllm-inference` on `192.168.3.42` (`axe-master`) with:

- Kubernetes `v1.28.9`
- `volcano` installed
- `hami-scheduler` installed
- Image `docker.io/vllm/vllm-openai:v0.11.0-x86_64`
- Local model path `/opt/models/qwen3.5-35b` exposed in-cluster via PVC `qwen35-35b-model-pvc`

## Environment Facts Observed Before Testing

- Node: `axe-master`
- GPU inventory: `8 x RTX 2080 Ti (22 GiB)`
- Actual `nvidia-smi topo -m` result:
  - `GPU0 <-> GPU3 = NV1`
  - `GPU6 <-> GPU7 = PIX`
  - `GPU5 <-> GPU6 = PHB`
  - `GPU4 <-> GPU7 = PHB`
- This means the requested `GPU6/GPU7 NVLink` assumption is not true on this host.
- The only pre-existing local model on-host was `/opt/models/qwen3.5-35b`.
- External download from `huggingface.co` timed out from this environment during testing.

## Scenarios

### SCN-01 Baseline model/runtime sanity check

Goal:
- Prove the image, model files, and cluster can serve a real request in this environment.

Method:
- Validate the already-running `llm-serving/qwen35-35b-predictor` deployment.
- Run `/health`.
- Run a real `/v1/chat/completions` request against the live pod.

Success criteria:
- Existing service is healthy.
- Existing service returns a non-empty completion payload.

### SCN-02 HAMI scheduler single-GPU deployment

Goal:
- Verify Helm can create a real HAMI-scheduled pod and bind it to an explicit GPU.
- Attempt single-GPU inference with the only local model available.

Method:
- `helm upgrade --install` using:
  - `scheduler.type=hami`
  - `nvidia.com/use-gpuuuid=GPU-e099b988-e339-e561-2506-0bd2b99201b3`
  - wrapper entrypoint `python3 /scripts/start_vllm.py`
  - local PVC-mounted model `/mnt/models`
- Observe pod scheduling, HAMI binding annotations, container logs, and load result.

Success criteria:
- Pod is scheduled by `hami-scheduler`.
- HAMI binding annotation shows the requested GPU UUID.
- If model fits, `/health` and `/v1/chat/completions` succeed.

Known risk:
- Available local model is `Qwen3.5-35B-A3B`, which is far too large for a plain 1x2080 Ti path unless wrapper patches and offload are enough.

### SCN-03 HAMI scheduler TP=2 deployment

Goal:
- Verify Helm can create a real HAMI-scheduled TP=2 deployment.
- Prefer explicit use of the free GPUs if HAMI accounting allows it.

Method:
- `helm upgrade --install` using:
  - `scheduler.type=hami`
  - tensor parallel size `2`
  - wrapper entrypoint `python3 /scripts/start_vllm.py`
  - PVC-mounted local model
  - explicit GPU UUID selection attempt for GPUs `6` and `7`
- Observe HAMI scheduling events and allocation errors.

Success criteria:
- Pod is scheduled by `hami-scheduler`.
- HAMI allocates two GPUs.
- Pod becomes healthy and serves a real completion.

Blocking condition to record:
- If a second full GPU is not actually free in HAMI accounting, document that instead of pretending TP=2 succeeded.

### SCN-04 Volcano PodGroup creation

Goal:
- Verify the chart creates a real `PodGroup` and that Volcano sees it.

Method:
- `helm upgrade --install` using:
  - `scheduler.type=volcano`
  - `scheduler.volcano.createPodGroup=true`
  - `scheduler.volcano.groupMinMember=1`
  - `scheduler.volcano.queueName=default`
- Inspect `PodGroup` YAML and status.

Success criteria:
- `PodGroup` exists in `llm-serving`.
- `PodGroup` status changes are observable from Volcano.

### SCN-05 Volcano real pod scheduling behavior

Goal:
- Validate what really happens when the same chart is scheduled by Volcano on this cluster.

Method:
- Run two Volcano variants:
  - Volcano + HAMI-style UUID/full-memory constraints
  - Volcano + plain `nvidia.com/gpu: 1`
- Inspect pod events, `UnexpectedAdmissionError`, and `PodGroup` status.

Success criteria:
- Either the pod schedules and runs, or the exact failure mode is captured with real cluster events.

Expected observation from task background:
- Non-HAMI scheduling paths can hit `UnexpectedAdmissionError` on this node.

### SCN-06 llama.cpp HAMI single-GPU deployment

Goal:
- Verify `charts/llamacpp-inference` can perform real single-GPU inference on the free RTX 2080 Ti.

Method:
- Use HAMI scheduler with explicit GPU UUID pin to GPU `7`.
- Use image `ghcr.io/ggerganov/llama.cpp:server-cuda-b4719`.
- Use model `Qwen/Qwen2.5-0.5B-Instruct-GGUF`.
- Use GGUF quant `qwen2.5-0.5b-instruct-q4_k_m.gguf`.
- Inject proxy env vars for Hugging Face download.
- Validate `/health` and send a real `/v1/chat/completions` request.

Success criteria:
- Pod binds to the requested GPU.
- Model downloads and loads.
- `/health` is healthy.
- Completion request returns a non-empty response.

### SCN-07 sglang HAMI single-GPU deployment

Goal:
- Verify `charts/sglang-inference` can create a real HAMI-bound pod on the same free GPU path.

Method:
- Use HAMI scheduler with explicit GPU UUID pin to GPU `7`.
- Use image `lmsysorg/sglang:latest`.
- Use model `Qwen/Qwen2.5-0.5B-Instruct`.
- Inject proxy env vars.
- Observe image pull, scheduler events, and runtime logs.

Success criteria:
- Pod binds to the requested GPU.
- Image pulls successfully.
- Container starts and reaches health endpoint.

Blocking condition to record:
- If the node's registry mirror path fails before container start, record the exact pull error instead of pretending the chart itself is broken.

## Reference Links

- vLLM serve CLI: <https://docs.vllm.ai/en/latest/cli/serve.html>
- HAMi scheduler docs: <https://project-hami.io/docs/userguide/scheduler/scheduler/>
- HAMi specific GPU selection: <https://project-hami.io/docs/userguide/nvidia-device/examples/specify-certain-card/>
- Volcano PodGroup docs: <https://volcano.sh/en/docs/podgroup/>
