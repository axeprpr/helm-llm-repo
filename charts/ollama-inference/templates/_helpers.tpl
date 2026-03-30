{{- define "ollama-inference.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ollama-inference.fullname" -}}
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

{{- define "ollama-inference.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ollama-inference.labels" -}}
helm.sh/chart: {{ include "ollama-inference.chart" . }}
{{ include "ollama-inference.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "ollama-inference.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ollama-inference.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "ollama-inference.gpuTolerations" -}}
{{- if eq .Values.gpuType "nvidia" }}
- key: "nvidia.com/gpu"
  operator: "Exists"
  effect: "NoSchedule"
{{- else if eq .Values.gpuType "amd" }}
- key: "amd.com/gpu"
  operator: "Exists"
  effect: "NoSchedule"
{{- end }}
{{- end }}
