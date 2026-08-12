{{/*
------------------------------------------------------------------------------
Egress rule builder shared by every component's NetworkPolicy.

A NetworkPolicy declaring policyTypes: [Egress] makes that pod default-deny for
outbound traffic - only what these rules match is allowed.

Regional note: central is in a different cluster, so its address has to be
reachable through this allowlist.
------------------------------------------------------------------------------
*/}}
{{- define "akto-regional-setup.networkPolicy.egressRules" -}}
{{- $ctx := index . 0 -}}
{{- $extra := index . 1 | default dict -}}
{{- $np := $ctx.Values.networkPolicy -}}
{{- if $np.allowDNS }}
# DNS - required for any Service name to resolve.
- to:
  - namespaceSelector:
      matchLabels:
        {{- toYaml $np.dnsNamespaceSelector | nindent 8 }}
  ports:
  - port: 53
    protocol: UDP
  - port: 53
    protocol: TCP
{{- end }}
{{- if $np.allowIntraRelease }}
# Components of this release talking to each other.
- to:
  - podSelector:
      matchLabels:
        app.kubernetes.io/instance: {{ $ctx.Release.Name }}
{{- end }}
{{- range concat ($np.egressAllowlist | default list) ($extra.egressAllowlist | default list) }}
- to:
  - ipBlock:
      cidr: {{ .cidr }}
      {{- with .except }}
      except:
        {{- toYaml . | nindent 8 }}
      {{- end }}
  {{- with .ports }}
  ports:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- range concat ($np.egressNamespaces | default list) ($extra.egressNamespaces | default list) }}
- to:
  - namespaceSelector:
      matchLabels:
        {{- toYaml . | nindent 8 }}
{{- end }}
{{- end }}

{{- define "akto-regional-setup.networkPolicy.ingressRules" -}}
{{- $ctx := index . 0 -}}
{{- $np := $ctx.Values.networkPolicy -}}
# Other components of this release.
- from:
  - podSelector:
      matchLabels:
        app.kubernetes.io/instance: {{ $ctx.Release.Name }}
{{- range $np.ingressNamespaces | default list }}
- from:
  - namespaceSelector:
      matchLabels:
        {{- toYaml . | nindent 8 }}
{{- end }}
{{- range $np.ingressAllowlist | default list }}
- from:
  - ipBlock:
      cidr: {{ .cidr }}
      {{- with .except }}
      except:
        {{- toYaml . | nindent 8 }}
      {{- end }}
  {{- with .ports }}
  ports:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}
