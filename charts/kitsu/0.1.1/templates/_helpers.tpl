{{- define "kitsu.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "kitsu.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "kitsu.component" -}}
{{- printf "%s-%s" (include "kitsu.fullname" .root) .component | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "kitsu.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "kitsu.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "kitsu.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kitsu.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "kitsu.image" -}}
{{ .repository }}:{{ .tag }}
{{- end -}}

{{- define "kitsu.storageClassName" -}}
{{- $ixStorageClass := "" -}}
{{- with .Values.global -}}
{{- with .ixChartContext -}}
{{- with .storageClassName -}}
{{- $ixStorageClass = . -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- default $ixStorageClass .Values.persistence.storageClassName -}}
{{- end -}}

{{- define "kitsu.secretValue" -}}
{{- $root := .root -}}
{{- $key := .key -}}
{{- $value := .value -}}
{{- $length := default 48 .length -}}
{{- $existing := lookup "v1" "Secret" $root.Release.Namespace (include "kitsu.fullname" $root) -}}
{{- if $value -}}
{{- $value -}}
{{- else if and $existing (index $existing.data $key) -}}
{{- index $existing.data $key | b64dec -}}
{{- else -}}
{{- randAlphaNum $length -}}
{{- end -}}
{{- end -}}
