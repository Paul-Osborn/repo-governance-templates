# Contributing to <PROJECT_NAME>

> Copy to `CONTRIBUTING.md`. This is the human-facing version of the rules; the full set
> lives in `REPO_RULES.md` and the always-on agent rules in `AGENTS.md`.

Thanks for helping out. A few ground rules keep things clean:

## Workflow
1. **Branch first** — never commit to `main`. Use `git switch -c <type>/<short-desc>`
   (`feat/`, `fix/`, `docs/`, `chore/`, `refactor/`).
2. **One cohesive deliverable per branch / PR.** Include the tests, documentation, and small
   supporting refactors required to ship it; defer unrelated work.
3. **Open a pull request** describing *what* changed, *why*, and *how you tested it*.
4. A PR must build / run / pass tests and the pre-commit checks before it can merge.

## Setup
- Install dependencies: `<command>`
- Install the git hooks (secret scan, etc.): `lefthook install`
- Run tests: `<command>`

## Commits
- Use [Conventional Commits](https://www.conventionalcommits.org): `feat`, `fix`, `docs`,
  `chore`, `refactor`, `test`, `perf`. Imperative subject, ≤ 72 chars, no trailing period.
- The body explains *why*, not just *what*.

## Never commit
- Secrets (keys, tokens, passwords), build output, large data, or local/editor files.
  The secret scanner will block commits that contain credentials — that's expected.
