# Contributing to m365-configurator

This guide gets you productive on any machine and describes how we work.

## 1. Get a working environment

See the [Quickstart in the README](README.md#quickstart--clone-and-develop-anywhere).
The **dev container** is the reproducible path; local PowerShell **7.6+**
(the ADR-0015 floor) with `scripts/bootstrap.ps1` also works.

Verify your environment:

```powershell
pwsh -NoProfile -File scripts/install-modules.ps1   # idempotent; safe to re-run
```

Install the dev/test tooling and run the suite (the code is built **test-first**
with Pester 5+; the dev container provisions Pester automatically):

```powershell
pwsh -NoProfile -File scripts/install-dev-tools.ps1   # one-time; installs pinned Pester
Invoke-Pester -Path tests/
```

## 2. Branching

- All work for this initiative lands on **`main`** (the default branch).
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

Every change is measured against the project's design tenets. To keep a single
source of truth, the **canonical summary lives in the
[README](README.md#design-tenets)** and the full, testable list in
[`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md). In brief: no credentials on disk,
ever; no unexpected network calls; loud, fast failure — with **self-healing**
*offers* for recoverable preconditions
([ADR-0011](docs/decisions/0011-self-healing-remediation-for-recoverable-preconditions.md));
audit-grade logging; minimal dependencies; dry-run before apply; pinned module
versions; readability for visual inspection. **Reviewers reject changes that
violate these.**

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
