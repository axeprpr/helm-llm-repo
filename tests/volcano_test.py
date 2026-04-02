#!/usr/bin/env python3
"""Volcano scheduler comprehensive tests."""
import pytest
from conftest import helm_template, parse_yaml_docs, find_doc, find_containers

class TestVolcanoSchedulerName:
    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_volcano_scheduler_name(self, chart, base_sets):
        stdout, _ = helm_template(chart, {**base_sets, "scheduler.type": "volcano"})
        docs = parse_yaml_docs(stdout)
        deployment = find_doc(docs, "Deployment")
        assert deployment["spec"]["template"]["spec"]["schedulerName"] == "volcano"

    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_hami_scheduler_name(self, chart, base_sets):
        stdout, _ = helm_template(chart, {**base_sets, "scheduler.type": "hami"})
        docs = parse_yaml_docs(stdout)
        deployment = find_doc(docs, "Deployment")
        assert deployment["spec"]["template"]["spec"]["schedulerName"] == "hami-scheduler"

    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_native_no_scheduler_name(self, chart, base_sets):
        stdout, _ = helm_template(chart, {**base_sets, "scheduler.type": "native"})
        docs = parse_yaml_docs(stdout)
        deployment = find_doc(docs, "Deployment")
        spec = deployment["spec"]["template"]["spec"]
        assert not spec.get("schedulerName") or spec.get("schedulerName") == ""

class TestVolcanoPodGroupCreation:
    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_podgroup_created_when_volcano_and_createpodgroup(self, chart, base_sets):
        stdout, _ = helm_template(chart, {**base_sets, "scheduler.type": "volcano", "scheduler.volcano.createPodGroup": "true"})
        docs = parse_yaml_docs(stdout)
        pg = find_doc(docs, "PodGroup")
        assert pg is not None
        assert pg["apiVersion"] == "scheduling.volcano.sh/v1beta1"

    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_no_podgroup_when_native(self, chart, base_sets):
        stdout, _ = helm_template(chart, {**base_sets, "scheduler.type": "native", "scheduler.volcano.createPodGroup": "true"})
        docs = parse_yaml_docs(stdout)
        pgs = [d for d in docs if d and d.get("kind") == "PodGroup"]
        assert len(pgs) == 0

    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_no_podgroup_when_volcano_createpodgroup_false(self, chart, base_sets):
        stdout, _ = helm_template(chart, {**base_sets, "scheduler.type": "volcano", "scheduler.volcano.createPodGroup": "false"})
        docs = parse_yaml_docs(stdout)
        pgs = [d for d in docs if d and d.get("kind") == "PodGroup"]
        assert len(pgs) == 0

class TestVolcanoGroupMinMember:
    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    @pytest.mark.parametrize("min_member,replicas,expected", [(3,2,3),(5,3,5),(1,1,1)])
    def test_min_member_value(self, chart, base_sets, min_member, replicas, expected):
        sets = {**base_sets, "scheduler.type": "volcano", "scheduler.volcano.createPodGroup": "true",
                "scheduler.volcano.groupMinMember": str(min_member), "replicaCount": str(replicas)}
        stdout, _ = helm_template(chart, sets)
        docs = parse_yaml_docs(stdout)
        pg = find_doc(docs, "PodGroup")
        assert pg["spec"]["minMember"] == expected

    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_deployment_annotation_group_min_member(self, chart, base_sets):
        sets = {**base_sets, "scheduler.type": "volcano", "scheduler.volcano.groupMinMember": "3",
                "scheduler.volcano.createPodGroup": "false"}
        stdout, _ = helm_template(chart, sets)
        docs = parse_yaml_docs(stdout)
        deployment = find_doc(docs, "Deployment")
        annotations = deployment.get("metadata", {}).get("annotations", {})
        assert "scheduling.volcano.sh/group-min-member" in annotations
        assert annotations["scheduling.volcano.sh/group-min-member"] == "3"

    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_no_annotation_when_native(self, chart, base_sets):
        sets = {**base_sets, "scheduler.type": "native", "scheduler.volcano.groupMinMember": "3"}
        stdout, _ = helm_template(chart, sets)
        docs = parse_yaml_docs(stdout)
        deployment = find_doc(docs, "Deployment")
        annotations = deployment.get("metadata", {}).get("annotations", {})
        assert "scheduling.volcano.sh/group-min-member" not in annotations

class TestVolcanoQueueName:
    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    @pytest.mark.parametrize("queue", ["default", "gpu-queue", "production", "test-queue"])
    def test_queue_name_rendered(self, chart, base_sets, queue):
        sets = {**base_sets, "scheduler.type": "volcano", "scheduler.volcano.createPodGroup": "true", "scheduler.volcano.queueName": queue}
        stdout, _ = helm_template(chart, sets)
        docs = parse_yaml_docs(stdout)
        pg = find_doc(docs, "PodGroup")
        assert pg["spec"]["queue"] == queue

    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_queue_name_empty_no_field(self, chart, base_sets):
        sets = {**base_sets, "scheduler.type": "volcano", "scheduler.volcano.createPodGroup": "true", "scheduler.volcano.queueName": ""}
        stdout, _ = helm_template(chart, sets)
        docs = parse_yaml_docs(stdout)
        pg = find_doc(docs, "PodGroup")
        assert "queue" not in pg["spec"]

class TestVolcanoMinResources:
    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_minresources_memory_cpu(self, chart, base_sets):
        sets = {**base_sets, "scheduler.type": "volcano", "scheduler.volcano.createPodGroup": "true",
                "scheduler.volcano.minResources.memory": "16Gi",
                "scheduler.volcano.minResources.cpu": "8"}
        stdout, _ = helm_template(chart, sets)
        docs = parse_yaml_docs(stdout)
        pg = find_doc(docs, "PodGroup")
        mr = pg["spec"]["minResources"]
        assert mr["memory"] == "16Gi"
        assert mr["cpu"] == 8

    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_minresources_empty_no_field(self, chart, base_sets):
        sets = {**base_sets, "scheduler.type": "volcano", "scheduler.volcano.createPodGroup": "true"}
        stdout, _ = helm_template(chart, sets)
        docs = parse_yaml_docs(stdout)
        pg = find_doc(docs, "PodGroup")
        assert "minResources" not in pg["spec"]

class TestVolcanoPriorityClassName:
    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    @pytest.mark.parametrize("pc", ["high-priority", "system-cluster-critical", "default"])
    def test_priority_class_name(self, chart, base_sets, pc):
        sets = {**base_sets, "scheduler.type": "volcano", "scheduler.volcano.createPodGroup": "true", "priorityClassName": pc}
        stdout, _ = helm_template(chart, sets)
        docs = parse_yaml_docs(stdout)
        pg = find_doc(docs, "PodGroup")
        assert pg["spec"]["priorityClassName"] == pc

    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_priority_class_name_absent(self, chart, base_sets):
        sets = {**base_sets, "scheduler.type": "volcano", "scheduler.volcano.createPodGroup": "true"}
        stdout, _ = helm_template(chart, sets)
        docs = parse_yaml_docs(stdout)
        pg = find_doc(docs, "PodGroup")
        assert "priorityClassName" not in pg["spec"]

class TestVolcanoAnnotations:
    @pytest.mark.parametrize("chart", ["vllm-inference", "sglang-inference", "llamacpp-inference"])
    def test_scheduler_annotations_renders(self, chart, base_sets):
        sets = {**base_sets, "scheduler.type": "volcano", "scheduler.volcano.createPodGroup": "true",
                "scheduler.annotations.test-key": "test-value"}
        stdout, _ = helm_template(chart, sets)
        docs = parse_yaml_docs(stdout)
        pg = find_doc(docs, "PodGroup")
        assert pg is not None

class TestVolcanoCrossChartConsistency:
    def test_all_charts_podgroup_same_api_version(self):
        for chart in ["vllm-inference", "sglang-inference", "llamacpp-inference"]:
            sets = {"image.repository": f"test/{chart}", "image.tag": "latest",
                    "scheduler.type": "volcano", "scheduler.volcano.createPodGroup": "true",
                    "scheduler.volcano.groupMinMember": "2", "scheduler.volcano.queueName": "prod-queue",
                    "priorityClassName": "high-priority"}
            stdout, _ = helm_template(chart, sets)
            docs = parse_yaml_docs(stdout)
            pg = find_doc(docs, "PodGroup")
            assert pg["apiVersion"] == "scheduling.volcano.sh/v1beta1"
            assert pg["spec"]["minMember"] == 2
            assert pg["spec"]["queue"] == "prod-queue"
            assert pg["spec"]["priorityClassName"] == "high-priority"

    def test_all_charts_volcano_scheduler_name(self):
        for chart in ["vllm-inference", "sglang-inference", "llamacpp-inference"]:
            sets = {"image.repository": f"test/{chart}", "image.tag": "latest", "scheduler.type": "volcano"}
            stdout, _ = helm_template(chart, sets)
            docs = parse_yaml_docs(stdout)
            deployment = find_doc(docs, "Deployment")
            assert deployment["spec"]["template"]["spec"]["schedulerName"] == "volcano"

    def test_all_charts_deployment_annotation(self):
        for chart in ["vllm-inference", "sglang-inference", "llamacpp-inference"]:
            sets = {"image.repository": f"test/{chart}", "image.tag": "latest",
                    "scheduler.type": "volcano", "scheduler.volcano.groupMinMember": "3",
                    "scheduler.volcano.createPodGroup": "false"}
            stdout, _ = helm_template(chart, sets)
            docs = parse_yaml_docs(stdout)
            deployment = find_doc(docs, "Deployment")
            ann = deployment.get("metadata", {}).get("annotations", {})
            assert "scheduling.volcano.sh/group-min-member" in ann
            assert ann["scheduling.volcano.sh/group-min-member"] == "3"
