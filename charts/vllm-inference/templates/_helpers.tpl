{{/*
Expand the name of the chart.
*/}}
{{- define "vllm-inference.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "vllm-inference.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "vllm-inference.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "vllm-inference.labels" -}}
helm.sh/chart: {{ include "vllm-inference.chart" . }}
{{ include "vllm-inference.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "vllm-inference.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vllm-inference.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "vllm-inference.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "vllm-inference.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "vllm-inference.schedulerName" -}}
{{- if .Values.scheduler.name }}
{{- .Values.scheduler.name }}
{{- else if eq .Values.scheduler.type "hami" }}
hami-scheduler
{{- else if eq .Values.scheduler.type "volcano" }}
volcano
{{- end }}
{{- end }}

{{- define "vllm-inference.podAnnotations" -}}
{{- $annotations := dict -}}
{{- if .Values.podAnnotations }}
{{- range $k, $v := .Values.podAnnotations }}
{{- $_ := set $annotations $k $v }}
{{- end }}
{{- end }}
{{- if .Values.scheduler.annotations }}
{{- range $k, $v := .Values.scheduler.annotations }}
{{- $_ := set $annotations $k $v }}
{{- end }}
{{- end }}
{{- if and (eq .Values.scheduler.type "volcano") .Values.scheduler.volcano.queueName }}
{{- $_ := set $annotations "scheduling.volcano.sh/queue-name" .Values.scheduler.volcano.queueName }}
{{- end }}
{{- if and (eq .Values.scheduler.type "volcano") .Values.scheduler.volcano.createPodGroup }}
{{- $_ := set $annotations "scheduling.k8s.io/group-name" (include "vllm-inference.fullname" .) }}
{{- end }}
{{- if and (eq .Values.scheduler.type "hami") .Values.scheduler.hami.nodeSchedulerPolicy }}
{{- $_ := set $annotations "hami.io/node-scheduler-policy" .Values.scheduler.hami.nodeSchedulerPolicy }}
{{- end }}
{{- if and (eq .Values.scheduler.type "hami") .Values.scheduler.hami.gpuSchedulerPolicy }}
{{- $_ := set $annotations "hami.io/gpu-scheduler-policy" .Values.scheduler.hami.gpuSchedulerPolicy }}
{{- end }}
{{- if gt (len $annotations) 0 }}
{{- toYaml $annotations }}
{{- end }}
{{- end }}

{{/*
GPU tolerations based on gpuType
*/}}
{{- define "vllm-inference.gpuTolerations" -}}
{{- if eq .Values.gpuType "nvidia" }}
- key: "nvidia.com/gpu"
  operator: "Exists"
  effect: "NoSchedule"
{{- else if eq .Values.gpuType "ascend" }}
- key: "Ascend.com/gpu"
  operator: "Exists"
  effect: "NoSchedule"
{{- else if eq .Values.gpuType "amd" }}
- key: "amd.com/gpu"
  operator: "Exists"
  effect: "NoSchedule"
{{- end }}
{{- end }}

{{/*
Build vLLM command arguments
*/}}
{{- define "vllm-inference.engineArgs" -}}
{{- $args := list }}
{{- $args = append $args (printf "--model %s" .Values.model.name) }}
{{- $args = append $args (printf "--trust-remote-code") }}
{{- if .Values.model.hfToken }}
{{- $args = append $args (printf "--hf-token %s" .Values.model.hfToken) }}
{{- end }}
{{- if .Values.engine.tensorParallelSize }}
{{- $args = append $args (printf "--tensor-parallel-size %d" (int .Values.engine.tensorParallelSize)) }}
{{- end }}
{{- if .Values.engine.pipelineParallelSize }}
{{- $args = append $args (printf "--pipeline-parallel-size %d" (int .Values.engine.pipelineParallelSize)) }}
{{- end }}
{{- $args = append $args (printf "--gpu-memory-utilization %.2f" .Values.engine.gpuMemoryUtilization) }}
{{- $args = append $args (printf "--max-model-len %d" (int .Values.engine.maxModelLen)) }}
{{- if .Values.engine.enablePrefixCaching }}
{{- $args = append $args "--enable-prefix-caching" }}
{{- end }}
{{- $args = append $args (printf "--port %d" (int .Values.engine.port)) }}
{{- if .Values.engine.extraArgs }}
{{- $args = append $args .Values.engine.extraArgs }}
{{- end }}
{{- join " " $args }}
{{- end }}
