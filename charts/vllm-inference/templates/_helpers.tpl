{{/*
Expand the name of the chart.
*/}}
{{- define "vllm-inference.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

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

{{- define "vllm-inference.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "vllm-inference.labels" -}}
helm.sh/chart: {{ include "vllm-inference.chart" . }}
{{ include "vllm-inference.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "vllm-inference.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vllm-inference.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "vllm-inference.gpuTolerations" -}}
{{- $base := list }}
{{- if eq .Values.gpuType "nvidia" }}
{{- $base = append $base (dict "key" "nvidia.com/gpu" "operator" "Exists" "effect" "NoSchedule") }}
{{- else if eq .Values.gpuType "amd" }}
{{- $base = append $base (dict "key" "amd.com/gpu" "operator" "Exists" "effect" "NoSchedule") }}
{{- else if eq .Values.gpuType "ascend" }}
{{- $base = append $base (dict "key" "Ascend.com/gpu" "operator" "Exists" "effect" "NoSchedule") }}
{{- else if eq .Values.gpuType "intel" }}
{{- $base = append $base (dict "key" "gpu.intel.com/tile" "operator" "Exists" "effect" "NoSchedule") }}
{{- end }}
{{- $user := .Values.tolerations | default list }}
{{- $combined := concat $base $user | uniq }}
{{- toYaml $combined }}
{{- end }}

{{/*
Build vLLM engine command based on model.type
- chat: standard vLLM server
- embedding: vLLM server with --task embed/rank
- vision: vLLM server (multipart messages handled automatically)
*/}}
{{- define "vllm-inference.engineArgs" -}}
{{- $args := list }}
{{- $args = append $args "--model" }}
{{- $args = append $args .Values.model.name }}
{{- $args = append $args "--trust-remote-code" }}
{{- if .Values.model.hfToken }}
{{- $args = append $args "--hf-token" }}
{{- $args = append $args .Values.model.hfToken }}
{{- end }}
{{- if .Values.engine.tensorParallelSize }}
{{- $args = append $args "--tensor-parallel-size" }}
{{- $args = append $args (printf "%d" (int .Values.engine.tensorParallelSize)) }}
{{- end }}
{{- if .Values.engine.pipelineParallelSize }}
{{- $args = append $args "--pipeline-parallel-size" }}
{{- $args = append $args (printf "%d" (int .Values.engine.pipelineParallelSize)) }}
{{- end }}
{{- $args = append $args "--gpu-memory-utilization" }}
{{- $args = append $args (printf "%.2f" .Values.engine.gpuMemoryUtilization) }}
{{- $args = append $args "--max-model-len" }}
{{- $args = append $args (printf "%d" (int .Values.engine.maxModelLen)) }}
{{- $args = append $args "--port" }}
{{- $args = append $args (printf "%d" (int .Values.engine.port)) }}
{{- if eq .Values.model.type "embedding" }}
{{- $args = append $args "--task" }}
{{- $args = append $args .Values.engine.embeddingTask }}
{{- if eq .Values.engine.embeddingTask "embed" }}
{{- $args = append $args "--pooler-output-fn" }}
{{- $args = append $args .Values.engine.poolerType }}
{{- end }}
{{- if .Values.engine.enablePrefixCaching }}
{{- $args = append $args "--enable-prefix-caching" }}
{{- end }}
{{- end }}
{{- if .Values.engine.extraArgs }}
{{- $args = append $args .Values.engine.extraArgs }}
{{- end }}
{{- join " " $args }}
{{- end }}

{{/*
Determine default model name based on model.type
*/}}
{{- define "vllm-inference.defaultModel" -}}
{{- if eq .Values.model.type "embedding" }}BAAI/bge-m3{{- else if eq .Values.model.type "vision" }}Qwen/Qwen2-VL-7B-Instruct{{- else }}Qwen/Qwen2.5-7B-Instruct{{- end }}
{{- end }}
{{/*
Create the name for the service account.
*/}}
{{- define "vllm-inference.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else }}
{{- include "vllm-inference.fullname" . }}
{{- end }}
{{- end }}
{{/*
Build unified pod annotations from all sources (scheduler, user, annotations).
*/}}
{{- define "vllm-inference.podAnnotations" -}}
{{- $annos := merge
  (.Values.scheduler.annotations | default dict)
  (.Values.podAnnotations | default dict)
  (.Values.annotations | default dict)
-}}
{{- toYaml $annos }}
{{- end }}
{{/*
Determine scheduler name based on scheduler.type.
Returns empty string for native scheduler (kube-scheduler default).
*/}}
{{- define "vllm-inference.schedulerName" -}}
{{- if eq .Values.scheduler.type "hami" }}hami-scheduler{{- else if eq .Values.scheduler.type "volcano" }}volcano{{- else }}{{ .Values.scheduler.name | default "" }}{{- end }}
{{- end }}
