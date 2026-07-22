# Contributing to m365-configurator

This guide gets you productive on any machine and describes how we work.

## 1. Get a working environment

See the [Quickstart in the README](README.md#quickstart--clone-and-develop-anywhere).
The **dev container** is the reproducible path; local PowerShell 7+ with
`scripts/bootstrap.ps1` also works.

Verify your environment:

```powershell
pwsh -NoProfile -File scripts/install-modules.ps1   # idempotent; safe to re-run
```

## 2. Branching

- All work for this initiative lands on **`claude/m365-exchange-config-app-1hko7b`**.
- Never push to another branch without explicit permission.
- Keep commits small, descriptive, and scoped to one logical change.

## 3. Commit messages

Use short, imperative subjects (e.g. `Add drift-detection engine skeleton`).
Explain the *why* in the body when it isn't obvious. Reference Jira issues
(project key `MCA`) where applicable, e.g. `MCA-12: ...`.

## 4. Code authoring & review workflow

To keep quality high, **an agent never reviews its own code**:

1. One agent (or contributor) **authors** a change.
2. A **separate** agent/contributor **reviews** it before merge.
3. Independent workstreams are parallelized wherever they don't conflict.

When using automation, spawn distinct author and reviewer agents. The reviewer
checks against the design tenets below and the requirements in
[`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md).

## 5. Non-negotiable design tenets

Every change is measured against these (full, testable list in
[`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md)):

- **No credentials on disk. Ever.** No secrets in code, config, logs, or profiles.
- **No unexpected network calls.** The app talks only to endpoints it is
  explicitly told to. Adding an outbound call requires justification in review.
- **Loud, fast failure.** No silent catches; no partial application without a
  clear, logged error.
- **Audit-grade logging.** Structured, verbose, retrievable.
- **Minimal dependencies.** New dependencies must be justified in review.
- **Dry-run first.** Any change-applying feature ships with a preview path.
- **Version-pinning discipline.** Stability is tied to pinned module versions.
- **Readability for visual inspection.** Format code, profiles, logs, and diffs so
  a human can scan and verify them at a glance. Consistent, aligned, and scannable
  beats clever or dense. Reviewers reject output that's hard to eyeball.

## 6. Security reporting

Found something sensitive committed by mistake (a token, a cert, tenant data)?
Do **not** just delete it in a new commit — the history still contains it. Flag it
so the secret can be rotated and history scrubbed. The `.gitignore` is tuned to
prevent this; if you're adding a new kind of sensitive artifact, extend it first.

## 7. Handy references

- Vision: [`docs/VISION.md`](docs/VISION.md)
- Requirements: [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md)
- Roadmap: [`docs/ROADMAP.md`](docs/ROADMAP.md)
- Open questions: [`docs/OPEN-QUESTIONS.md`](docs/OPEN-QUESTIONS.md)
- Architecture decisions: [`docs/decisions/`](docs/decisions/)
