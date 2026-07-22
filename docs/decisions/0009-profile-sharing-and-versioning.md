# 0009. Profile sharing & versioning: Git-committed, single-file export, tagged baselines

- **Status:** Accepted
- **Date:** 2026-07-22
- **Deciders:** Project owner + team
- **Requirements:** FR-5, FR-6, NFR-1, NFR-5, NFR-9
- **Related:** OPEN-QUESTIONS Q9; ADR-0008; `docs/research/06-prior-art-and-architecture.md` §6.4

## Context

Q9 asked how profiles are shared and versioned: committed to this repo, kept in a
separate repo, or purely exported files — and how a "known-good baseline" is versioned
over time. Research 06 §6.4 pointed at the Maester "tests-as-code you commit" model.

## Decision

- Treat profiles as **version-controlled files in Git**.
- Support **single-file export/import** (one YAML/JSON) for the ad-hoc "upload an
  exported profile" path the vision and **FR-6** call for.
- Version a **known-good baseline as a Git tag** (e.g. `baseline-1.2.0`), so a
  `v1 → v2` baseline diff reviews in the normal PR flow.
- Ship the **reference security baseline in *this* repo** under `profiles/` for the
  MVP; consumers keep **their own** profiles in their own location and the tool loads
  a profile **by path or from an exported file** — tool and profiles stay **loosely
  coupled**.

## Consequences

- **Safe to commit** precisely because profiles are **credential-free** (FR-5, NFR-1)
  — a direct payoff of the no-persistence tenet, unlike CIPP which must vault secrets.
- Git gives **history, blame, PR review, and tags "for free"** — the most auditable,
  readable versioning available (NFR-5/NFR-9).
- **Single-file export** satisfies collaboration without requiring the recipient to
  clone a repo (FR-6).
- **Reversible:** promoting profiles to a **separate repo** later is an easy move;
  the in-repo reference baseline keeps the MVP simple now.

## Alternatives considered

- **Separate profiles repo now** — deferred: cleaner for multi-consumer sharing but an
  extra moving part for the MVP.
- **Export-only, no version control** — rejected: loses history and auditability
  (NFR-5).
- **Vaulted secrets alongside profiles (CIPP)** — not applicable: we store **no**
  secrets in or beside profiles.
