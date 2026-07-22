# 0008. Profile format: YAML authored, JSON canonical

- **Status:** Accepted
- **Date:** 2026-07-22
- **Deciders:** Project owner + team
- **Requirements:** FR-5, FR-6, NFR-3, NFR-9
- **Related:** OPEN-QUESTIONS Q8; `docs/research/06-prior-art-and-architecture.md` §6.3; ADR-0009

## Context

Profiles must be **human-readable, diff-friendly, and config-only — never
credentials** (FR-5, NFR-1, NFR-9). Q8 weighed **YAML**, **JSON**, and PowerShell
data (`.psd1`). Research 06 found the field already clusters on YAML + JSON
(ScubaGear config is YAML/JSON; Maester/Monkey365 rules are JSON); only M365DSC uses
PowerShell/`.psd1` + MOF.

## Decision

**Author and share profiles in YAML.** **Canonicalize to JSON internally** — stable
key ordering, sorted arrays — for diffing and as the export/interchange format.

## Consequences

- **YAML** wins reviewability: comments, low syntactic noise, block structure — a
  reviewer can scan a profile and know what it means (NFR-9).
- **Canonical JSON** keeps drift/dry-run diffs **deterministic** and matches the
  native shape of Graph request bodies (research 01), so the diff engine has one
  stable internal form.
- Both are **config-only** — no executable logic, safe to commit and share (FR-5,
  ADR-0009).
- **Honest cost:** YAML needs a pinned parser dependency (`powershell-yaml`, the same
  module ScubaGear pins) — a small but real **NFR-3** cost; the version is pinned.
- **Documented fallback:** if minimal-deps is ever weighted above reviewer
  familiarity, native `.psd1` (`Import-PowerShellDataFile`, data-only, zero extra
  deps) is the drop-in alternative.

## Alternatives considered

- **JSON-only** — rejected as the authoring format: no comments hurts the
  reviewability of a shared baseline (retained as the canonical machine form).
- **`.psd1` primary** — the minimal-deps fallback; idiomatic pwsh and zero-dependency,
  but noisier to diff for deeply nested objects and less approachable for
  non-PowerShell collaborators.
- **`.ps1` / MOF (DSC-style)** — rejected: code-shaped, unsafe to share, against
  config-only.
