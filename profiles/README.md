# profiles/

Saved configuration profiles live here.

## Rules

- **Configuration only. Never credentials.** A profile describes *what* to
  configure, not *how to authenticate*. Tokens, secrets, certificates, and
  tenant-identifying secrets must never appear in a profile.
- **Human-readable and diff-friendly.** Profiles are meant to be reviewed in pull
  requests and shared with collaborators.
- **Shareable.** Files placed directly under `profiles/` are safe to commit and
  share (subject to review). Machine-specific or sensitive exports belong under
  `profiles/local/`, which is git-ignored.

The concrete profile schema is an open design decision — see
[`../docs/OPEN-QUESTIONS.md`](../docs/OPEN-QUESTIONS.md) (Q8/Q9).

> If you ever find yourself about to save a secret into a profile: stop. That is a
> bug in the design, not a thing to work around. Raise it.
