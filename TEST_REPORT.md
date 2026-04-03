# Helm LLM Repo - Integration Test Report

**Date:** 2026-04-03 18:30 UTC
**Environment:** axe-master (192.168.3.42) - 8× RTX 2080 Ti
**Engineer:** 35号技师 (Codex Agent)
**Repo:** https://github.com/axeprpr/helm-llm-repo

---

## Executive Summary

Real deployment tests of helm-llm-repo charts (vllm-inference, sglang-inference, llamacpp-inference) on live Kubernetes cluster with GPU hardware. Tests were conducted on axe-master (192.168.3.42) with 8× RTX 2080 Ti.

**Key Finding:** Real model inference tests are blocked by an infrastructure constraint: the Kubernetes node has no external network access, preventing vLLM from downloading model metadata from HuggingFace during initialization.

---

## Environment

| Item | Value |
|------|-------|
| Node | axe-master |
| Host | 192.168.3.42 |
| GPUs | 8× NVIDIA GeForce RTX 2080 Ti (22GB each) |
| NVLink | GPU pairs (0,3), (1,2), (4,7), (5,6) via NVLink |
| Kubernetes | v1.28.9 |
| Volcano | Installed (volcano-system) |
| Hami | Installed (hami-system) |
| Test Image | docker.io/vllm/vllm-openai:v0.11.0-x86_64 |
| Scheduler Used | hami-scheduler (native scheduler causes UnexpectedAdmissionError) |
| Free GPUs | GPU 6, 7 (used for test deployments) |
| Existing Deployment | qwen35-35b (port 8000, Running, Inference OK) |

---

## Test Results

| ID | Test | Result | Notes |
|----|------|--------|-------|
| T01 | Helm template vllm-inference (native scheduler) | ✅ PASS | Template renders correctly |
| T02 | Helm template vllm-inference (volcano scheduler) | ✅ PASS | PodGroup rendered |
| T03 | Helm template vllm-inference (hami scheduler) | ✅ PASS | schedulerName set |
| T04 | Helm template sglang-inference | ✅ PASS | |
| T05 | Helm template llamacpp-inference | ✅ PASS | |
| T06 | Volcano PodGroup creation | ✅ PASS | createPodGroup=true creates PodGroup |
| T07 | Volcano schedulerName injection | ✅ PASS | schedulerName: volcano |
| T08 | Hami schedulerName injection | ✅ PASS | schedulerName: hami-scheduler |
| T09 | vLLM helm install | ✅ PASS | Deploys without error |
| T10 | vLLM pod starts | ❌ FAIL | Pod starts but crashes: vLLM v0.11.0 tries HuggingFace verification |
| T11 | vLLM /health endpoint | ❌ FAIL | Blocked by T10 |
| T12 | vLLM inference | ❌ FAIL | Blocked by T10 |
| T13 | Volcano real pod scheduling | ⚠️ NOT TESTED | Blocked by infrastructure |
| T14 | Hami real pod scheduling | ⚠️ NOT TESTED | Blocked by infrastructure |
| T15 | Pytest suite | ✅ PASS | 146 template tests pass |

---

## Bug Fixes Applied

### Bug 1: vLLM v0.11.0 CLI - model as positional arg
- **File:** `charts/vllm-inference/templates/_helpers.tpl`
- **Problem:** vLLM v0.11.0 changed CLI: model must be positional argument, not `--model` flag
- **Fix:** Removed `--model` flag from engineArgs, model name now passed as positional argument
- **Commit:** `94293be`

### Bug 2: sglang/llamacpp podgroup nil pointer
- **File:** `charts/sglang-inference/templates/podgroup.yaml`, `charts/llamacpp-inference/templates/podgroup.yaml`
- **Problem:** `hasKey` check on nil value caused template error
- **Fix:** Added proper nil check before hasKey call
- **Commit:** `f765299`

### Bug 3: llamacpp volcano group-min-member annotation missing
- **File:** `charts/llamacpp-inference/templates/deployment.yaml`
- **Problem:** When createPodGroup=false, groupMinMember annotation was not set
- **Fix:** Added annotation regardless of createPodGroup setting
- **Commit:** `f765299`

---

## Known Issues

### Issue 1: Native scheduler - UnexpectedAdmissionError
- **Severity:** High
- **Symptom:** Pod scheduled by default-scheduler but kubelet rejects with "no binding pod found"
- **Root cause:** Incompatibility between default scheduler and Hami device plugin on this node
- **Workaround:** Use hami-scheduler for all deployments

### Issue 2: vLLM v0.11.0 requires HuggingFace network
- **Severity:** Critical (blocks inference)
- **Symptom:** Pod crashes with `LocalEntryNotFoundError: Cannot find cached snapshot` then attempts to download from HuggingFace, failing with `Network is unreachable`
- **Root cause:** vLLM v0.11.0 calls `snapshot_download` which requires HuggingFace network access even for fully local models. The `vllm serve` CLI (vs programmatic API) enforces this.
- **Workaround:** Use `start_vllm.py` custom startup script (as in existing qwen35-35b deployment) or mount `/opt/py-extras` with patched transformers

### Issue 3: ghcr.io image not accessible
- **Severity:** High
- **Workaround:** Use `docker.io/vllm/vllm-openai:v0.11.0-x86_64` (already cached on node)

---

## Existing qwen35-35b Deployment (Working Reference)

The existing qwen35-35b deployment **works correctly** and serves inference at port 8000. Key differences from helm chart:

| Aspect | Existing Deployment | Helm Chart |
|--------|-------------------|------------|
| Startup | Custom `start_vllm.py` script | `vllm serve` CLI |
| Transformers | Patched `/opt/py-extras/transformers` | Stock vLLM image |
| HuggingFace hub | Patched `huggingface_hub` | Standard |
| Offline mode | Enabled via `is_offline_mode` stub | Not available |
| Inference | ✅ Working | ❌ Blocked |

Existing deployment command (working):
```
python3 /scripts/start_vllm.py \
  --model=/mnt/models \
  --served-model-name=Qwen3.5-35B-A3B \
  --dtype=float16 \
  --tensor-parallel-size=2 \
  --gpu-memory-utilization=0.97 \
  --max-model-len=4096 \
  --enable-chunked-prefill \
  --tokenizer-mode=slow \
  --trust-remote-code \
  --host=0.0.0.0 --port=8000
```

---

## Test Scenarios Written

Complete test scenarios are documented in `TEST_SCENARIOS.md`, covering:
- Template rendering (146 test cases)
- Volcano PodGroup, queueName, minMember, minResources
- Hami GPU sharing: gpuMemoryFraction, nodeSchedulerPolicy, gpuSchedulerPolicy, migStrategy
- vLLM engine args: TP/PP, maxModelLen, gpuMemoryUtilization, extraArgs, reasoning parser
- NVLink: TP=2/4 on RTX 2080 Ti paired GPUs
- Multi-node tests (hardware limited - requires 2+ GPU nodes)

---

## Multi-Node Test (Hardware Limited)

> ⚠️ **NOTE:** Multi-node tests (PP>1 or multi-node TP) require at least 2 GPU nodes.
> Current environment has only 1 node (axe-master).
> For multi-node testing, use:
> ```bash
> helm install test charts/vllm-inference \
>   --set distributed.enabled=true \
>   --set distributed.nodeList=node2,node3 \
>   --set distributed.masterAddr=node2 \
>   --set engine.tensorParallelSize=2 \
>   --set engine.pipelineParallelSize=2
> ```

---

## Commit History

| Commit | Description |
|--------|-------------|
| `94293be` | fix: vllm v0.11.0 CLI - model as positional arg not --model flag |
| `f765299` | fix: add llamacpp volcano group-min-member annotation and hasKey check |
| `db93101` | feat: add volcano and hami scheduler comprehensive test suite |

---

_Generated by 35号技师 (Codex Agent) on 2026-04-03_
