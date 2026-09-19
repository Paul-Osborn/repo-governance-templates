# Optional templates

These are extra governance files you can drop into a project **when it needs them**. They're
kept out of the core set so a small solo tool stays small. Copy the ones that apply, fill in
the `<PLACEHOLDER>`s, and delete the rest.

| File | Copy to | Use it when… |
|------|---------|--------------|
| `LICENSE-GUIDE.md` | (read it, then add a `LICENSE`) | The project might ever be public or shared. Without a license, others legally can't use your code. |
| `SECURITY.template.md` | `SECURITY.md` | The project is public and you want a clear way for people to report security problems. |
| `CONTRIBUTING.template.md` | `CONTRIBUTING.md` | Other people (not just you + an agent) will contribute. |
| `CODEOWNERS.template` | `.github/CODEOWNERS` | You want changes to certain files to auto-request a specific reviewer. Low value solo; useful with a team. |
| `editorconfig.template` | `.editorconfig` | Almost always — it makes every editor use the same basic formatting (indentation, line endings). Cheap, prevents noisy diffs. |
| `ISSUE_TEMPLATE.template.md` | `.github/ISSUE_TEMPLATE.md` | Public/team project; you want bug reports to include the info you need. |
| `PULL_REQUEST_TEMPLATE.template.md` | `.github/PULL_REQUEST_TEMPLATE.md` | You want every PR to state what changed, why, and how it was tested. |

GitHub governance CI is core in V3 and is installed from `github/workflows/`; it is no longer an
optional example.
