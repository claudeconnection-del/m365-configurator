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

The profile format is **settled**: authored in **YAML**, with **JSON** as the
canonical (diff/interchange) form (`.psd1` is a documented minimal-deps fallback) —
see [ADR-0008](../docs/decisions/0008-profile-format-yaml-authored-json-canonical.md).
Sharing & versioning (git-committed, credential-free, single-file export, known-good
baselines as git tags) is [ADR-0009](../docs/decisions/0009-profile-sharing-and-versioning.md).

> If you ever find yourself about to save a secret into a profile: stop. That is a
> bug in the design, not a thing to work around. Raise it.
