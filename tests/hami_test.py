#!/usr/bin/env python3
"""Hami scheduler comprehensive tests."""
import pytest
from conftest import helm_template, parse_yaml_docs, find_doc, find_containers

class TestHamiSchedulerName:
    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_hami_scheduler_name(self, chart, base_sets):
        stdout, _ = helm_template(chart, {**base_sets, "scheduler.type": "hami"})
        docs = parse_yaml_docs(stdout)
        deployment = find_doc(docs, "Deployment")
        assert deployment["spec"]["template"]["spec"]["schedulerName"] == "hami-scheduler"

    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_native_no_hami_scheduler_name(self, chart, base_sets):
        stdout, _ = helm_template(chart, {**base_sets, "scheduler.type": "native"})
        docs = parse_yaml_docs(stdout)
        deployment = find_doc(docs, "Deployment")
        spec = deployment["spec"]["template"]["spec"]
        assert spec.get("schedulerName") != "hami-scheduler"

    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_hami_vs_volcano_different_names(self, chart, base_sets):
        hami_sets = {**base_sets, "scheduler.type": "hami"}
        vol_sets = {**base_sets, "scheduler.type": "volcano"}
        hami_stdout, _ = helm_template(chart, hami_sets)
        vol_stdout, _ = helm_template(chart, vol_sets)
        hami_deploy = find_doc(parse_yaml_docs(hami_stdout), "Deployment")
        vol_deploy = find_doc(parse_yaml_docs(vol_stdout), "Deployment")
        assert hami_deploy["spec"]["template"]["spec"]["schedulerName"] == "hami-scheduler"
        assert vol_deploy["spec"]["template"]["spec"]["schedulerName"] == "volcano"

class TestHamiGpuSharePercent:
    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    @pytest.mark.parametrize("percent", ["10", "50", "100"])
    def test_gpusharepercent_renders(self, chart, base_sets, percent):
        sets = {**base_sets, "scheduler.type": "hami", "scheduler.hami.gpuSharePercent": percent}
        stdout, _ = helm_template(chart, sets)
        docs = parse_yaml_docs(stdout)
        deployment = find_doc(docs, "Deployment")
        assert deployment is not None
        if chart == "vllm-inference":
            limits = deployment["spec"]["template"]["spec"]["containers"][0]["resources"]["limits"]
            assert limits["nvidia.com/gpumem-percentage"] == percent

class TestHamiNodeSchedulerPolicy:
    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    @pytest.mark.parametrize("policy", ["binpack", "spread"])
    def test_nodeschedulerpolicy_renders(self, chart, base_sets, policy):
        sets = {**base_sets, "scheduler.type": "hami", "scheduler.hami.nodeSchedulerPolicy": policy}
        stdout, _ = helm_template(chart, sets)
        docs = parse_yaml_docs(stdout)
        deployment = find_doc(docs, "Deployment")
        assert deployment is not None
        annotations = deployment["spec"]["template"]["metadata"].get("annotations", {})
        if chart == "vllm-inference":
            assert annotations["hami.io/node-scheduler-policy"] == policy

class TestHamiGpuSchedulerPolicy:
    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    @pytest.mark.parametrize("policy", ["binpack", "spread", "topology-aware"])
    def test_gpuschedulerpolicy_renders(self, chart, base_sets, policy):
        sets = {**base_sets, "scheduler.type": "hami", "scheduler.hami.gpuSchedulerPolicy": policy}
        stdout, _ = helm_template(chart, sets)
        docs = parse_yaml_docs(stdout)
        deployment = find_doc(docs, "Deployment")
        assert deployment is not None
        annotations = deployment["spec"]["template"]["metadata"].get("annotations", {})
        if chart == "vllm-inference":
            assert annotations["hami.io/gpu-scheduler-policy"] == policy

class TestHamiContainerAnnotations:
    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_hami_deployment_renders_ok(self, chart, base_sets):
        sets = {**base_sets, "scheduler.type": "hami"}
        stdout, _ = helm_template(chart, sets)
        docs = parse_yaml_docs(stdout)
        deployment = find_doc(docs, "Deployment")
        assert deployment is not None
        pod_spec = deployment["spec"]["template"]["spec"]
        containers = find_containers(pod_spec)
        assert len(containers) > 0

    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_hami_annotations_render(self, chart, base_sets):
        sets = {**base_sets, "scheduler.type": "hami",
                "scheduler.annotations.hami.io/resource-name": "nvidia.com/gpu"}
        stdout, _ = helm_template(chart, sets)
        docs = parse_yaml_docs(stdout)
        deployment = find_doc(docs, "Deployment")
        assert deployment is not None

class TestHamiSchedulerAnnotationsPropagation:
    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_scheduler_annotations(self, chart, base_sets):
        sets = {**base_sets, "scheduler.type": "hami",
                "scheduler.annotations.hami.io/resource-name": "nvidia.com/gpu"}
        stdout, _ = helm_template(chart, sets)
        docs = parse_yaml_docs(stdout)
        deployment = find_doc(docs, "Deployment")
        assert deployment is not None

class TestHamiCrossChartConsistency:
    def test_all_charts_hami_scheduler_name(self):
        for chart in ["vllm-inference", "sglang-inference", "llamacpp-inference"]:
            sets = {"image.repository": f"test/{chart}", "image.tag": "latest", "scheduler.type": "hami"}
            stdout, _ = helm_template(chart, sets)
            docs = parse_yaml_docs(stdout)
            deployment = find_doc(docs, "Deployment")
            assert deployment["spec"]["template"]["spec"]["schedulerName"] == "hami-scheduler"

    def test_all_charts_hami_renders_ok(self):
        for chart in ["vllm-inference", "sglang-inference", "llamacpp-inference"]:
            for policy in ["binpack", "spread"]:
                sets = {"image.repository": f"test/{chart}", "image.tag": "latest",
                        "scheduler.type": "hami", "scheduler.hami.nodeSchedulerPolicy": policy}
                stdout, _ = helm_template(chart, sets)
                docs = parse_yaml_docs(stdout)
                deployment = find_doc(docs, "Deployment")
                assert deployment is not None
