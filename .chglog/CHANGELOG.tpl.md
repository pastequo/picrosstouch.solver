{{ range .Versions }}
<a name="{{ .Tag.Name }}"></a>
## {{ if .Tag.Previous }}[{{ .Tag.Name }}]({{ $.Info.RepositoryURL }}/compare/{{ .Tag.Previous.Name }}...{{ .Tag.Name }}){{ else }}{{ .Tag.Name }}{{ end }} ({{ datetime "2006-01-02" .Tag.Date }})

{{ range .CommitGroups -}}
### {{ .Title }}

{{ range .Commits -}}
* {{ with .Scope }}**{{ . }}:** {{ end }}[{{ .Subject }}]({{ $.Info.RepositoryURL }}/-/commit/{{ .Hash.Long }}){{with .Author}} - *{{.Name}}*{{end}}
{{ end }}
{{ end -}}

{{- if .RevertCommits -}}
### Reverts

{{ range .RevertCommits -}}
* [{{ .Revert.Header }}]({{ $.Info.RepositoryURL }}/-/commit/{{ .Hash.Long }}){{with .Author}} - *{{.Name}}*{{end}}
{{ end }}
{{ end -}}

{{- if .MergeCommits -}}
### Merge Requests

{{ range .MergeCommits -}}
* [{{ .Header }}]({{ $.Info.RepositoryURL }}/-/commit/{{ .Hash.Long }}){{with .Author}} - *{{.Name}}*{{end}}
{{ end }}
{{ end -}}

{{- if .NoteGroups -}}
{{ range .NoteGroups -}}
### {{ .Title }}

{{ range .Notes }}
{{ .Body }}
{{ end }}
{{ end -}}
{{ end -}}
{{ end -}}