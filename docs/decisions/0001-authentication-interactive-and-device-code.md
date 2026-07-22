# 0001. Authentication: interactive delegated + device code, memory-only

- **Status:** Accepted
- **Date:** 2026-07-22
- **Deciders:** Project owner + team
- **Requirements:** FR-2, FR-3, NFR-1, NFR-2
- **Related:** OPEN-QUESTIONS Q4/Q5

## Context

The tool connects to Microsoft 365 (Graph + Exchange Online) per tenant, often in
a consultant/multi-tenant workflow, and must **never persist credentials**, with
**full cleanup between sessions**. Containerized/headless operation is a goal.

## Decision

Support two authentication methods initially, both **memory-only** (no tokens or
secrets written to disk):

1. **Interactive delegated (browser)** sign-in.
2. **Device code flow** — the natural default for headless/containerized runs.

App-only auth (app registration + certificate) is **deferred** (Q5). If later
adopted for unattended automation, certificates must be supplied at runtime and
never persisted.

## Consequences

- Directly serves the "no credentials on disk" and "full cleanup" tenets.
- Device code fits containers (no in-container browser required).
- Requires per-tenant delegated consent and least-privilege scopes per feature.
- **Risk to reconcile:** Microsoft365DSC (see ADR-0002) commonly favors app+cert/
  secret auth and may not support delegated/device-code — research 03/04 must
  resolve this tension.

## Alternatives considered

- **App-only cert/secret first** — better for automation, heavier secret handling; deferred.
- **Persistent token cache** — rejected; violates no-persistence.
