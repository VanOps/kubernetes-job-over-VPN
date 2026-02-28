{{/*
Expand the name of the chart.
*/}}
{{- define "ansible-job.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "ansible-job.fullname" -}}
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

{{/*
Create chart label value.
*/}}
{{- define "ansible-job.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "ansible-job.labels" -}}
helm.sh/chart: {{ include "ansible-job.chart" . }}
{{ include "ansible-job.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ansible-gitops
environment: {{ .Values.environment }}
{{- end }}

{{/*
Selector labels (used in matchLabels — must be stable, never change).
*/}}
{{- define "ansible-job.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ansible-job.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "ansible-job.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ansible-job.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image pull policy helper.
*/}}
{{- define "ansible-job.imagePullPolicy" -}}
{{- if eq .Values.ansible.image.tag "latest" -}}
Always
{{- else -}}
{{ default "IfNotPresent" .Values.ansible.image.pullPolicy }}
{{- end }}
{{- end }}
