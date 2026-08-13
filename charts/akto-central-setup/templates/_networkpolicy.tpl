{{/*
------------------------------------------------------------------------------
Egress rule builder shared by every component's NetworkPolicy.

A NetworkPolicy that declares policyTypes: [Egress] switches that pod to
default-deny for outbound traffic - only what these rules match is allowed.
That is the mechanism behind "the dashboard must not reach the public
internet".

Usage:
  {{ include "akto-central-setup.networkPolicy.egressRules" (list $root $componentOverrides) }}
where $componentOverrides is the matching entry under
networkPolicy.components.* (may be an empty dict).
------------------------------------------------------------------------------
*/}}
{{/*
RFC1918 private ranges, always allowed for egress regardless of what's in
networkPolicy.egressAllowlist. Hardcoded here (not a values.yaml default) so
that field can safely start empty and be purely additive - see the comment on
networkPolicy.egressAllowlist in values.yaml for why that matters with --set.
*/}}
{{- define "akto-central-setup.networkPolicy.baseEgressAllowlist" -}}
- cidr: 10.0.0.0/8
- cidr: 172.16.0.0/12
- cidr: 192.168.0.0/16
{{- end }}

{{- define "akto-central-setup.networkPolicy.egressRules" -}}
{{- $ctx := index . 0 -}}
{{- $extra := index . 1 | default dict -}}
{{- $np := $ctx.Values.networkPolicy -}}
{{- $base := include "akto-central-setup.networkPolicy.baseEgressAllowlist" . | fromYamlArray -}}
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
{{- range concat $base ($np.egressAllowlist | default list) ($extra.egressAllowlist | default list) }}
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

{{/*
------------------------------------------------------------------------------
Ingress rule builder. Only rendered when networkPolicy.restrictIngress is true.
------------------------------------------------------------------------------
*/}}
{{- define "akto-central-setup.networkPolicy.ingressRules" -}}
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
