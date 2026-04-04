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

{{/*
Create the service account name.
*/}}
{{- define "llamacpp-inference.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "llamacpp-inference.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end }}

{{/*
Select the correct llama.cpp backend image tag based on gpuType.
References: GPUStack community-inference-backends.yaml
*/}}
{{- define "llamacpp-inference.backendImage" -}}
{{- $base := .Values.image.repository | default "ghcr.io/ggerganov/llama.cpp" }}
{{- $tag := .Values.image.tag | default "" }}
{{- if and .Values.image.autoBackend (not $tag) }}
{{- if eq .Values.gpuType "nvidia" }}{{- $tag = "server-cuda" }}
{{- else if eq .Values.gpuType "amd" }}{{- $tag = "server-rocm" }}
{{- else if eq .Values.gpuType "musa" }}{{- $tag = "server-musa" }}
{{- else if or (eq .Values.gpuType "vulkan") (eq .Values.gpuType "intel") }}{{- $tag = "server" }}
{{- else if eq .Values.gpuType "none" }}{{- $tag = "server-cpu" }}
{{- end }}
{{- end }}
{{- printf "%s:%s" $base $tag }}
{{- end }}

{{/*
Build llama.cpp server command arguments.
References: GPUStack llama.cpp backend config
*/}}
{{- define "llamacpp-inference.engineArgs" -}}
{{- $args := list }}
{{- /* Model source */ -}}
{{- if .Values.model.downloadOnStartup }}
{{- $args = append $args "-hf" }}
{{- if .Values.model.ggufFile }}
{{- $quant := (trimSuffix ".gguf" .Values.model.ggufFile | splitList "-" | last | upper) }}
{{- $args = append $args (printf "%s:%s" .Values.model.name $quant) }}
{{- else }}
{{- $args = append $args .Values.model.name }}
{{- end }}
{{- else if .Values.model.ggufFile }}
{{- $args = append $args "-m" }}
{{- $args = append $args (printf "%s/%s" .Values.model.name .Values.model.ggufFile) }}
{{- else }}
{{- $args = append $args "-m" }}
{{- $args = append $args .Values.model.name }}
{{- end }}
{{- /* API server */ -}}
{{- $args = append $args "-fa" }}
{{- /* Host/Port */ -}}
{{- $args = append $args "--host" }}
{{- $args = append $args "0.0.0.0" }}
{{- $args = append $args "--port" }}
{{- $args = append $args (printf "%d" (int .Values.engine.port)) }}
{{- /* Context size */ -}}
{{- if .Values.engine.contextSize }}
{{- $args = append $args "--ctx-size" }}
{{- $args = append $args (printf "%d" (int .Values.engine.contextSize)) }}
{{- end }}
{{- /* GPU layers */ -}}
{{- if .Values.engine.gpuLayers }}
{{- $args = append $args "--n-gpu-layers" }}
{{- $args = append $args (printf "%d" (int .Values.engine.gpuLayers)) }}
{{- end }}
{{- /* Tensor parallelism / threads */ -}}
{{- if and .Values.engine.tensorParallelSize (gt (int .Values.engine.tensorParallelSize) 1) }}
{{- $args = append $args "--split-mode" }}
{{- $args = append $args "layer" }}
{{- $args = append $args "--tensor-split" }}
{{- $args = append $args (printf "%d" (int .Values.engine.tensorParallelSize)) }}
{{- else if .Values.engine.threads }}
{{- $args = append $args "--threads" }}
{{- $args = append $args (printf "%d" (int .Values.engine.threads)) }}
{{- end }}
{{- /* Batch size */ -}}
{{- if .Values.engine.batchSize }}
{{- $args = append $args "--batch-size" }}
{{- $args = append $args (printf "%d" (int .Values.engine.batchSize)) }}
{{- end }}
{{- /* Parallel sequences */ -}}
{{- if .Values.engine.parallel }}
{{- $args = append $args "--parallel" }}
{{- $args = append $args (printf "%d" (int .Values.engine.parallel)) }}
{{- end }}
{{- /* Extra args */ -}}
{{- if .Values.engine.extraArgs }}
{{- $args = append $args .Values.engine.extraArgs }}
{{- end }}
{{- join " " $args }}
{{- end }}

{{- define "llamacpp-inference.gpuTolerations" -}}
{{- $base := list }}
{{- if eq .Values.gpuType "nvidia" }}
{{- $base = append $base (dict "key" "nvidia.com/gpu" "operator" "Exists" "effect" "NoSchedule") }}
{{- else if eq .Values.gpuType "amd" }}
{{- $base = append $base (dict "key" "amd.com/gpu" "operator" "Exists" "effect" "NoSchedule") }}
{{- else if eq .Values.gpuType "intel" }}
{{- $base = append $base (dict "key" "gpu.intel.com/tile" "operator" "Exists" "effect" "NoSchedule") }}
{{- end }}
{{- $user := .Values.tolerations | default list }}
{{- $combined := concat $base $user | uniq }}
{{- toYaml $combined }}
{{- end }}

{{- define "llamacpp-inference.schedulerName" -}}
{{- if eq .Values.scheduler.type "hami" }}hami-scheduler{{- else if eq .Values.scheduler.type "volcano" }}volcano{{- else }}{{ .Values.scheduler.name | default "" }}{{- end }}
{{- end }}
