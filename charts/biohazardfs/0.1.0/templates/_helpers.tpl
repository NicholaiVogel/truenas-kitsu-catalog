{{- define "biohazardfs.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "biohazardfs.fullname" -}}
{{- if .Release.Name -}}
{{- printf "%s-%s" .Release.Name (include "biohazardfs.name" .) | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "biohazardfs.name" . -}}
{{- end -}}
{{- end -}}

{{- define "biohazardfs.secretName" -}}
{{- if .Values.secrets.existingSecret -}}
{{- .Values.secrets.existingSecret -}}
{{- else -}}
{{- printf "%s-secret" (include "biohazardfs.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "biohazardfs.secretChecksum" -}}
{{- printf "%s|%s|%s|%s|%s|%s|%s" .Values.secrets.existingSecret .Values.secrets.version .Values.secrets.databaseUrl .Values.secrets.objectStoreEndpoint .Values.secrets.objectStoreBucket .Values.secrets.objectStoreAccessKeyId .Values.secrets.objectStoreSecretAccessKey | sha256sum -}}
{{- end -}}
