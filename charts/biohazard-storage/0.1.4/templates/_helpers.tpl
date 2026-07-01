{{- define "biohazard-storage.clientBucketUrl" -}}
{{- if .Values.juicefs.clientBucketUrl -}}
{{- .Values.juicefs.clientBucketUrl -}}
{{- else -}}
{{- printf "http://%s:%v/%s" .Values.network.nodeIP .Values.network.rustfsS3NodePort .Values.rustfs.bucket -}}
{{- end -}}
{{- end -}}
