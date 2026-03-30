{{/*
Expand the name of the chart.
*/}}
{{- define "embedding-inference.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "embedding-inference.fullname" -}}
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

{{- define "embedding-inference.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "embedding-inference.labels" -}}
helm.sh/chart: {{ include "embedding-inference.chart" . }}
{{ include "embedding-inference.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "embedding-inference.selectorLabels" -}}
app.kubernetes.io/name: {{ include "embedding-inference.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "embedding-inference.gpuTolerations" -}}
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
Build vLLM embedding command arguments
*/}}
{{- define "embedding-inference.engineArgs" -}}
{{- $args := list }}
{{- $args = append $args (printf "--model %s" .Values.model.name) }}
{{- $args = append $args "--trust-remote-code" }}
{{- if .Values.model.hfToken }}
{{- $args = append $args (printf "--hf-token %s" .Values.model.hfToken) }}
{{- end }}
{{- $args = append $args (printf "--task %s" .Values.engine.task) }}
{{- $args = append $args (printf "--gpu-memory-utilization %.2f" .Values.engine.gpuMemoryUtilization) }}
{{- $args = append $args (printf "--max-model-len %d" (int .Values.engine.maxModelLen)) }}
{{- $args = append $args (printf "--max-batch-size %d" (int .Values.engine.maxBatchSize)) }}
{{- $args = append $args (printf "--pooler-output-fn %s" .Values.engine.pooler) }}
{{- if .Values.engine.enablePrefixCaching }}
{{- $args = append $args "--enable-prefix-caching" }}
{{- end }}
{{- $args = append $args (printf "--port %d" (int .Values.engine.port)) }}
{{- if .Values.engine.extraArgs }}
{{- $args = append $args .Values.engine.extraArgs }}
{{- end }}
{{- join " " $args }}
{{- end }}
