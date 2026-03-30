{{- define "vision-inference.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "vision-inference.fullname" -}}
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

{{- define "vision-inference.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "vision-inference.labels" -}}
helm.sh/chart: {{ include "vision-inference.chart" . }}
{{ include "vision-inference.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "vision-inference.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vision-inference.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "vision-inference.gpuTolerations" -}}
{{- if eq .Values.gpuType "nvidia" }}
- key: "nvidia.com/gpu"
  operator: "Exists"
  effect: "NoSchedule"
{{- else if eq .Values.gpuType "ascend" }}
- key: "Ascend.com/gpu"
  operator: "Exists"
  effect: "NoSchedule"
{{- end }}
{{- end }}

{{/*
Build vLLM vision command arguments
*/}}
{{- define "vision-inference.engineArgs" -}}
{{- $args := list }}
{{- $args = append $args (printf "--model %s" .Values.model.name) }}
{{- $args = append $args "--trust-remote-code" }}
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
{{- $args = append $args (printf "--max-num-seqs %d" (int .Values.engine.maxNumSegs)) }}
{{- $args = append $args (printf "--port %d" (int .Values.engine.port)) }}
{{- if .Values.engine.extraArgs }}
{{- $args = append $args .Values.engine.extraArgs }}
{{- end }}
{{- join " " $args }}
{{- end }}
