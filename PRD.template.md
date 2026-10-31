# Project brief / PRD — <PROJECT_NAME>

> **What this is:** the project-level research document — what we're building and why. Created
> once at the start of the project (the agent interviews you to fill it), and kept updated as
> things evolve. This is the *project* brief; per-**feature** plans go in `SPEC.md`, not here.
> Replace every `<PLACEHOLDER>`.

## Problem / why
<What problem does this solve? Why does it need to exist?>

## Goal / outcome
<The one-sentence definition of "done" for the whole project.>

## Users / context
<Who uses it and in what situation. "Just me, on Windows" is a perfectly valid answer.>

## Scope
- **In:** <the things this project WILL do>
- **Out (for now):** <things explicitly NOT being built — this is what prevents drift>

## Requirements
- <what it must do — one bullet per capability>

## User experience
- **First useful result:** <shortest safe onboarding path and obvious next step>
- **Defaults and control:** <recommended choices, reasons, and how users change them>
- **Detail when needed:** <ordinary path first; where advanced options live; consequential limits and approvals visible before action>
- **Progress and recovery:** <what users can see, how failures/interruptions explain the next action, and routine work they should not need to babysit>

Adapt technology, language and setup to users' experience and environment. Reuse known
context and approved decisions; ask only for missing material decisions.

## Non-functional needs
- **Security / privacy:** <e.g. local-only, no telemetry, how secrets are handled>
- **Performance / limits:** <if any>
- **Platform:** <e.g. Windows; Python 3.x; offline>

## Constraints / decisions already made
- **Stack:** <language, key libraries>
- <other fixed decisions the build must respect>

## Success criteria (how we'll know it works)
- <observable, testable outcome>

## Risks / open questions
- <risk or unknown to resolve, with the answer once decided>

## Milestones (optional)
1. <first usable slice>
2. <next>
