# 0003. MVP scope: security baseline first

- **Status:** Accepted
- **Date:** 2026-07-22
- **Deciders:** Project owner + team
- **Requirements:** FR-4, FR-5, FR-8, FR-9, FR-10, FR-11
- **Related:** OPEN-QUESTIONS Q6; `docs/research/05-security-baselines.md`

## Context

The configurable surface (Graph + Exchange Online) is enormous. The owner's primary
use case is a reusable **known-good security baseline** applied per client.

## Decision

The MVP targets a **security-baseline** slice, taken end-to-end
(save profile → dry-run → apply → drift-detect → remediate):

- Identity & Conditional Access
- Authentication methods
- Exchange Online / Defender for Office 365 (anti-phishing, anti-spam, anti-malware,
  Safe Links / Safe Attachments)
- Tenant sharing & app-consent controls
- Auditing & logging

Breadth expands afterward, accelerated by Microsoft365DSC if ADR-0002 is accepted.

## Consequences

- Focuses research depth and the first build slices on high-value controls.
- Delivers a usable vertical quickly.
- Baseline content is opinionated and needs per-client tuning — reinforces the need
  for **name remapping** (FR-7) and **dry-run** (FR-8).

## Alternatives considered

- **Broad Exchange-Online-first** or **broadest-coverage-first** — both slower to a
  usable, high-value slice.
