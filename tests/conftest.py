#!/usr/bin/env python3
"""Pytest fixtures for helm-llm-repo scheduler tests."""
from pathlib import Path
import os
import subprocess

import pytest
import yaml

REPO_ROOT = Path(os.environ.get("REPO_ROOT", Path(__file__).resolve().parents[1]))
CHARTS = ["vllm-inference", "sglang-inference", "llamacpp-inference"]

def helm_template(chart, extra_sets=None, failure_allowed=False):
    cmd = ["helm", "template", chart, str(REPO_ROOT / "charts" / chart)]
    if extra_sets:
        for k, v in extra_sets.items():
            cmd += ["--set", f"{k}={v}"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if not failure_allowed and result.returncode != 0:
        raise RuntimeError(f"helm template failed: {result.stderr}")
    return result.stdout, result.returncode

def parse_yaml_docs(stdout):
    return list(yaml.safe_load_all(stdout))

def find_doc(docs, kind):
    return next((d for d in docs if d and d.get("kind") == kind), None)

def find_containers(pod_spec):
    return pod_spec.get("containers", [])

@pytest.fixture(params=CHARTS)
def chart(request):
    return request.param

@pytest.fixture
def base_sets(chart):
    if chart == "vllm-inference":
        return {"image.repository": "test/vllm", "image.tag": "latest"}
    elif chart == "sglang-inference":
        return {"image.repository": "test/sglang", "image.tag": "latest"}
    else:
        return {"image.repository": "test/llamacpp", "image.tag": "latest"}
