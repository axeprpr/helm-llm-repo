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

{{- define "vllm-inference.nativeMode" -}}
{{- if eq (.Values.workload.mode | default "deployment") "deployment" -}}true{{- else -}}false{{- end -}}
{{- end }}

{{- define "vllm-inference.defaultModel" -}}
{{- if eq .Values.model.type "embedding" }}BAAI/bge-m3{{- else if eq .Values.model.type "vision" }}Qwen/Qwen2-VL-7B-Instruct{{- else }}Qwen/Qwen2.5-7B-Instruct{{- end }}
{{- end }}

{{- define "vllm-inference.modelName" -}}
{{- default (include "vllm-inference.defaultModel" .) .Values.model.name -}}
{{- end }}

{{- define "vllm-inference.servedModelName" -}}
{{- default (include "vllm-inference.modelName" .) .Values.model.servedName -}}
{{- end }}

{{- define "vllm-inference.modelURI" -}}
{{- if .Values.kthena.backend.modelURI -}}
{{- .Values.kthena.backend.modelURI -}}
{{- else -}}
{{- printf "hf://%s" (include "vllm-inference.modelName" .) -}}
{{- end -}}
{{- end }}

{{- define "vllm-inference.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else }}
{{- include "vllm-inference.fullname" . }}
{{- end }}
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
{{- toYaml $base }}
{{- end }}

{{/*
Build `vllm serve` args.
*/}}
{{- define "vllm-inference.engineArgs" -}}
{{- $args := list }}
{{- $args = append $args (include "vllm-inference.modelName" .) }}
{{- if .Values.model.trustRemoteCode }}
{{- $args = append $args "--trust-remote-code" }}
{{- end }}
{{- if .Values.model.hfToken }}
{{- $args = concat $args (list "--hf-token" .Values.model.hfToken) }}
{{- end }}
{{- if .Values.model.reasoningParser }}
{{- $args = concat $args (list "--reasoning-parser" .Values.model.reasoningParser) }}
{{- end }}
{{- if .Values.model.servedName }}
{{- $args = concat $args (list "--served-model-name" (include "vllm-inference.servedModelName" .)) }}
{{- end }}
{{- if or (eq .Values.model.format "gptq") (eq .Values.model.format "awq") }}
{{- $args = concat $args (list "--quantization" .Values.model.format) }}
{{- end }}
{{- if .Values.engine.dtype }}
{{- $args = concat $args (list "--dtype" .Values.engine.dtype) }}
{{- end }}
{{- if .Values.engine.kvCacheDType }}
{{- $args = concat $args (list "--kv-cache-dtype" .Values.engine.kvCacheDType) }}
{{- end }}
{{- $args = concat $args (list "--tensor-parallel-size" (printf "%d" (int .Values.engine.tensorParallelSize))) }}
{{- $args = concat $args (list "--pipeline-parallel-size" (printf "%d" (int .Values.engine.pipelineParallelSize))) }}
{{- $args = concat $args (list "--gpu-memory-utilization" (printf "%v" .Values.engine.gpuMemoryUtilization)) }}
{{- $args = concat $args (list "--max-model-len" (printf "%d" (int .Values.engine.maxModelLen))) }}
{{- $args = concat $args (list "--port" (printf "%d" (int .Values.engine.port))) }}
{{- if gt (int .Values.engine.maxNumBatchedTokens) 0 }}
{{- $args = concat $args (list "--max-num-batched-tokens" (printf "%d" (int .Values.engine.maxNumBatchedTokens))) }}
{{- end }}
{{- if gt (int .Values.engine.maxNumSeqs) 0 }}
{{- $args = concat $args (list "--max-num-seqs" (printf "%d" (int .Values.engine.maxNumSeqs))) }}
{{- end }}
{{- if eq .Values.model.type "embedding" }}
{{- $args = concat $args (list "--task" .Values.engine.embeddingTask) }}
{{- if eq .Values.engine.embeddingTask "embed" }}
{{- $args = concat $args (list "--pooler-output-fn" .Values.engine.poolerType) }}
{{- end }}
{{- end }}
{{- if .Values.engine.enablePrefixCaching }}
{{- $args = append $args "--enable-prefix-caching" }}
{{- end }}
{{- if .Values.engine.enableChunkedPrefill }}
{{- $args = append $args "--enable-chunked-prefill" }}
{{- end }}
{{- if .Values.engine.enforceEager }}
{{- $args = append $args "--enforce-eager" }}
{{- end }}
{{- if .Values.engine.extraArgs }}
{{- $args = concat $args .Values.engine.extraArgs }}
{{- end }}
{{- join " " $args }}
{{- end }}

{{- define "vllm-inference.podAnnotations" -}}
{{- $annos := dict }}
{{- with (.Values.scheduler.annotations | default dict) }}
{{- $annos = merge $annos . }}
{{- end }}
{{- with (.Values.podAnnotations | default dict) }}
{{- $annos = merge $annos . }}
{{- end }}
{{- with (.Values.annotations | default dict) }}
{{- $annos = merge $annos . }}
{{- end }}
{{- if .Values.scheduler.gpuPool.includeUUIDs }}
{{- $_ := set $annos "nvidia.com/use-gpuuuid" (join "," .Values.scheduler.gpuPool.includeUUIDs) }}
{{- end }}
{{- if .Values.scheduler.gpuPool.excludeUUIDs }}
{{- $_ := set $annos "nvidia.com/nouse-gpuuuid" (join "," .Values.scheduler.gpuPool.excludeUUIDs) }}
{{- end }}
{{- if and (eq .Values.scheduler.type "hami") .Values.scheduler.hami.nodeSchedulerPolicy }}
{{- $_ := set $annos "hami.io/node-scheduler-policy" .Values.scheduler.hami.nodeSchedulerPolicy }}
{{- end }}
{{- if and (eq .Values.scheduler.type "hami") .Values.scheduler.hami.gpuSchedulerPolicy }}
{{- $_ := set $annos "hami.io/gpu-scheduler-policy" .Values.scheduler.hami.gpuSchedulerPolicy }}
{{- end }}
{{- if and (eq .Values.scheduler.type "volcano") (.Values.scheduler.volcano.createPodGroup | default false) }}
{{- $_ := set $annos "scheduling.k8s.io/group-name" (include "vllm-inference.fullname" .) }}
{{- end }}
{{- toYaml $annos }}
{{- end }}

{{- define "vllm-inference.schedulerName" -}}
{{- if eq .Values.scheduler.type "hami" }}hami-scheduler{{- else if eq .Values.scheduler.type "volcano" }}volcano{{- else }}{{ .Values.scheduler.name | default "" }}{{- end }}
{{- end }}

{{- define "vllm-inference.kthenaImage" -}}
{{- if .Values.kthena.backend.server.image -}}
{{- .Values.kthena.backend.server.image -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}
{{- end }}
