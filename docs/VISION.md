# Vision

> This document captures the north star for m365-configurator so that anyone
> picking up the work — on any machine, at any time — shares the same intent.

## The problem

Configuring Microsoft 365 tenants (Microsoft Graph, Exchange Online, and adjacent
surfaces) is powerful but scattered across many PowerShell modules and cmdlets.
Applying a consistent, known-good configuration to a new tenant — and proving it
stayed that way — is manual, error-prone, and hard to audit.

## The product

A portable, containerized tool that makes tenant configuration **repeatable,
reviewable, and auditable**:

1. **Self-bootstrapping.** Ensures the required PowerShell modules are installed
   and imported.
2. **Session-based connections.** Connect and disconnect on demand while the app
   runs, with **full credential cleanup** between sessions.
3. **Broad configuration surface.** Exposes what the underlying PowerShell modules
   can configure (Graph + Exchange Online at minimum; others — including DSC —
   where they add value) in an interface that is easy and satisfying to use.
4. **Configuration profiles.** Save a configuration (e.g. a known-good security
   baseline) once, then re-apply it to future tenants. Profiles can be:
   - selected from a list, or
   - imported from an exported file (for collaboration).
5. **Dry-run before apply.** Preview every change; apply only when everything is
   green.
6. **Drift detection + remediation.** Scan a live tenant against a saved profile,
   report drift, and offer **deterministic** remediations.
7. **Name remapping.** Where configurations are referenced by name (names are
   unique per configuration), profiles provide a way to update those names when
   applying to a new tenant.

## What "good" feels like

> Known-good security baseline? Saved. Next client needs it? Authenticate, pick
> the profile from a list (or upload an exported one), press **Dry Run** to test,
> then apply if all is green.

## Guardrails (see REQUIREMENTS.md for the testable version)

- **Security is paramount.** No credentials persisted. Nothing phones home.
- **Minimal dependencies.** Fewer things to trust and maintain.
- **Containerized & portable.** Same behavior everywhere.
- **Audit-grade, verbose logging** with easy retrieval.
- **Loud, fast failure** with proper error handling.
- **Stable** for as long as the underlying PowerShell module syntax is stable.

## Explicitly open for revision

The vision is fixed; the *how* is not. Architecture, language, and interface are
open for design — especially informed by the research phase — and are decided
collaboratively (see [`OPEN-QUESTIONS.md`](OPEN-QUESTIONS.md) and
[`decisions/`](decisions/)).
