#!/usr/bin/env python3
"""Regression tests for chart rendering issues found during real deployments."""
import pytest
from conftest import helm_template, parse_yaml_docs, find_doc


def _image_sets(chart):
    return {"image.repository": f"test/{chart}", "image.tag": "latest"}


@pytest.mark.parametrize("chart", ["sglang-inference", "llamacpp-inference"])
def test_service_account_create_renders(chart):
    stdout, _ = helm_template(chart, {**_image_sets(chart), "serviceAccount.create": "true"})
    docs = parse_yaml_docs(stdout)
    sa = find_doc(docs, "ServiceAccount")
    deployment = find_doc(docs, "Deployment")
    assert sa is not None
    assert deployment["spec"]["template"]["spec"]["serviceAccountName"] == sa["metadata"]["name"]


def test_sglang_scheduler_annotations_stay_in_pod_metadata():
    stdout, _ = helm_template(
        "sglang-inference",
        {
            **_image_sets("sglang-inference"),
            "scheduler.type": "hami",
            "scheduler.annotations.test-key": "test-value",
        },
    )
    docs = parse_yaml_docs(stdout)
    deployment = find_doc(docs, "Deployment")
    pod_meta = deployment["spec"]["template"]["metadata"]
    pod_spec = deployment["spec"]["template"]["spec"]
    assert pod_meta["annotations"]["test-key"] == "test-value"
    assert "test-key" not in pod_spec


def test_sglang_shm_mount_renders():
    stdout, _ = helm_template("sglang-inference", {**_image_sets("sglang-inference"), "shm.enabled": "true"})
    docs = parse_yaml_docs(stdout)
    deployment = find_doc(docs, "Deployment")
    container = deployment["spec"]["template"]["spec"]["containers"][0]
    mounts = {mount["mountPath"]: mount["name"] for mount in container["volumeMounts"]}
    volumes = {volume["name"] for volume in deployment["spec"]["template"]["spec"]["volumes"]}
    assert mounts["/dev/shm"] == "dshm"
    assert "dshm" in volumes


def test_llamacpp_uses_llama_server_binary():
    stdout, _ = helm_template("llamacpp-inference", _image_sets("llamacpp-inference"))
    docs = parse_yaml_docs(stdout)
    deployment = find_doc(docs, "Deployment")
    command = deployment["spec"]["template"]["spec"]["containers"][0]["command"][-1]
    assert "/app/llama-server" in command


@pytest.mark.parametrize("chart", ["sglang-inference", "llamacpp-inference"])
def test_extra_env_renders(chart):
    stdout, _ = helm_template(
        chart,
        {
            **_image_sets(chart),
            "extraEnv[0].name": "HTTPS_PROXY",
            "extraEnv[0].value": "http://192.168.3.42:7890",
        },
    )
    docs = parse_yaml_docs(stdout)
    deployment = find_doc(docs, "Deployment")
    env = deployment["spec"]["template"]["spec"]["containers"][0]["env"]
    assert {"name": "HTTPS_PROXY", "value": "http://192.168.3.42:7890"} in env


def test_llamacpp_explicit_image_tag_not_overridden():
    stdout, _ = helm_template(
        "llamacpp-inference",
        {
            **_image_sets("llamacpp-inference"),
            "image.tag": "server-cuda-b4719",
            "image.autoBackend": "true",
        },
    )
    docs = parse_yaml_docs(stdout)
    deployment = find_doc(docs, "Deployment")
    image = deployment["spec"]["template"]["spec"]["containers"][0]["image"]
    assert image == "test/llamacpp-inference:server-cuda-b4719"


def test_llamacpp_download_on_startup_uses_hf_repo():
    stdout, _ = helm_template(
        "llamacpp-inference",
        {
            **_image_sets("llamacpp-inference"),
            "model.name": "Qwen/Qwen2.5-0.5B-Instruct-GGUF",
            "model.ggufFile": "qwen2.5-0.5b-instruct-q4_k_m.gguf",
            "model.downloadOnStartup": "true",
        },
    )
    docs = parse_yaml_docs(stdout)
    deployment = find_doc(docs, "Deployment")
    command = deployment["spec"]["template"]["spec"]["containers"][0]["command"][-1]
    assert "-hf Qwen/Qwen2.5-0.5B-Instruct-GGUF:Q4_K_M" in command


@pytest.mark.parametrize("chart", ["sglang-inference", "llamacpp-inference"])
def test_startup_probe_renders(chart):
    stdout, _ = helm_template(
        chart,
        {
            **_image_sets(chart),
            "startupProbe.httpGet.path": "/health",
            "startupProbe.httpGet.port": "8000",
            "startupProbe.failureThreshold": "60",
            "startupProbe.periodSeconds": "10",
        },
    )
    docs = parse_yaml_docs(stdout)
    deployment = find_doc(docs, "Deployment")
    probe = deployment["spec"]["template"]["spec"]["containers"][0]["startupProbe"]
    assert probe["failureThreshold"] == 60
    assert probe["periodSeconds"] == 10
