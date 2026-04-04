#!/usr/bin/env python3
"""Regression and feature coverage tests for the vLLM chart."""
from conftest import helm_template, parse_yaml_docs, find_doc


def _sets(**overrides):
    base = {"image.repository": "test/vllm", "image.tag": "latest"}
    base.update(overrides)
    return base


def _deployment(extra_sets=None):
    sets = _sets()
    sets.update(extra_sets or {})
    stdout, _ = helm_template("vllm-inference", sets)
    docs = parse_yaml_docs(stdout)
    return find_doc(docs, "Deployment"), docs


def test_vllm_serve_passes_model_as_positional_argument():
    deployment, _ = _deployment({"model.name": "Qwen/Qwen2.5-7B-Instruct"})
    command = deployment["spec"]["template"]["spec"]["containers"][0]["command"][-1]
    assert "vllm serve Qwen/Qwen2.5-7B-Instruct" in command
    assert "--model " not in command


def test_vllm_embedding_task_and_pooler_render():
    deployment, _ = _deployment(
        {
            "model.type": "embedding",
            "engine.embeddingTask": "embed",
            "engine.poolerType": "mean",
        }
    )
    command = deployment["spec"]["template"]["spec"]["containers"][0]["command"][-1]
    assert "--task embed" in command
    assert "--pooler-output-fn mean" in command


def test_vllm_rerank_task_does_not_render_pooler_fn():
    deployment, _ = _deployment(
        {
            "model.type": "embedding",
            "engine.embeddingTask": "rank",
            "engine.poolerType": "mean",
        }
    )
    command = deployment["spec"]["template"]["spec"]["containers"][0]["command"][-1]
    assert "--task rank" in command
    assert "--pooler-output-fn" not in command


def test_vllm_reasoning_prefix_and_chunked_prefill_render():
    deployment, _ = _deployment(
        {
            "model.reasoningParser": "deepseek_r1",
            "engine.enablePrefixCaching": "true",
            "engine.enableChunkedPrefill": "true",
        }
    )
    command = deployment["spec"]["template"]["spec"]["containers"][0]["command"][-1]
    assert "--reasoning-parser deepseek_r1" in command
    assert "--enable-prefix-caching" in command
    assert "--enable-chunked-prefill" in command


def test_vllm_hami_policy_annotations_render():
    deployment, _ = _deployment(
        {
            "scheduler.type": "hami",
            "scheduler.hami.nodeSchedulerPolicy": "binpack",
            "scheduler.hami.gpuSchedulerPolicy": "spread",
        }
    )
    annotations = deployment["spec"]["template"]["metadata"]["annotations"]
    assert annotations["hami.io/node-scheduler-policy"] == "binpack"
    assert annotations["hami.io/gpu-scheduler-policy"] == "spread"


def test_vllm_hami_gpu_share_percent_maps_to_resource_limit():
    deployment, _ = _deployment(
        {
            "scheduler.type": "hami",
            "scheduler.hami.gpuSharePercent": "50",
        }
    )
    limits = deployment["spec"]["template"]["spec"]["containers"][0]["resources"]["limits"]
    assert limits["nvidia.com/gpumem-percentage"] == "50"


def test_vllm_startup_probe_renders():
    deployment, _ = _deployment(
        {
            "startupProbe.httpGet.path": "/health",
            "startupProbe.httpGet.port": "8000",
            "startupProbe.failureThreshold": "60",
        }
    )
    probe = deployment["spec"]["template"]["spec"]["containers"][0]["startupProbe"]
    assert probe["httpGet"]["path"] == "/health"
    assert probe["failureThreshold"] == 60


def test_vllm_command_and_args_override_default_launcher():
    deployment, _ = _deployment(
        {
            "command[0]": "python3",
            "command[1]": "/scripts/start_vllm.py",
            "args[0]": "--port",
            "args[1]": "8000",
        }
    )
    container = deployment["spec"]["template"]["spec"]["containers"][0]
    assert container["command"] == ["python3", "/scripts/start_vllm.py"]
    assert container["args"] == ["--port", "8000"]
