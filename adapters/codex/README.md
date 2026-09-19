# Codex adapter

Codex reads the repository's root `AGENTS.md` natively. No project-local executable adapter is
required, and project instructions are not treated as a security boundary.

For new projects, install the managed global bootstrap from `global/new-project-bootstrap.md`
with `update-global-rules.sh --agent codex` on Linux or `update-global-rules.ps1 -Agent codex`
on Windows. The bootstrap only scaffolds an ungoverned new folder.

Keep Codex sandboxing and approvals at user or organization scope. Permit ordinary read/build/test
operations in the workspace; require confirmation for host writes, credential access, destructive
operations, privileged commands, and unexpected network changes. Do not add a repository rule that
allows the repository to expand its own sandbox or approval authority.

Repository safety still comes from Git hooks, CI, GitHub protection, and human ratification. A
malicious or mistaken project instruction must not be able to grant itself more host access.
