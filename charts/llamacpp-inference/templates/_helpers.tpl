{{- define "llamacpp-inference.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "llamacpp-inference.fullname" -}}
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

{{- define "llamacpp-inference.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "llamacpp-inference.labels" -}}
helm.sh/chart: {{ include "llamacpp-inference.chart" . }}
{{ include "llamacpp-inference.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "llamacpp-inference.selectorLabels" -}}
app.kubernetes.io/name: {{ include "llamacpp-inference.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "llamacpp-inference.gpuTolerations" -}}
{{- if eq .Values.gpuType "nvidia" }}
- key: "nvidia.com/gpu"
  operator: "Exists"
  effect: "NoSchedule"
{{- else if eq .Values.gpuType "amd" }}
- key: "amd.com/gpu"
  operator: "Exists"
  effect: "NoSchedule"
{{- else if eq .Values.gpuType "intel" }}
- key: "gpu.intel.com/tile"
  operator: "Exists"
  effect: "NoSchedule"
{{- end }}
{{- end }}

{{/*
Build llama.cpp server command arguments
*/}}
{{- define "llamacpp-inference.engineArgs" -}}
{{- $args := list }}
{{- $args = append $args "-m" }}
{{- $args = append $args .Values.model.name }}
{{- $args = append $args "-l" }}
{{- $args = append $args (printf "%d" (int .Values.engine.port)) }}
{{- if .Values.engine.maxModelLen }}
{{- $args = append $args "--ctx-size" }}
{{- $args = append $args (printf "%d" (int .Values.engine.maxModelLen)) }}
{{- end }}
{{- if .Values.engine.extraArgs }}
{{- $args = append $args .Values.engine.extraArgs }}
{{- end }}
{{- join " " $args }}
{{- end }}
