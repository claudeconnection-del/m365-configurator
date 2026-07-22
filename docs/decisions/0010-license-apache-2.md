# 0010. License: Apache-2.0

- **Status:** Accepted
- **Date:** 2026-07-22
- **Deciders:** Project owner
- **Requirements:** (project meta — enables the sharing/collaboration goal in VISION)
- **Related:** OPEN-QUESTIONS Q10

## Context

The project was "all rights reserved" by default pending a license choice (Q10). The
tool is meant to be **shared and collaborative** but is **not** a hosted SaaS.
Prior-art licenses span the spectrum: Maester (MIT), Monkey365 (Apache-2.0), ScubaGear
(public-domain style), CIPP (AGPL-3.0, copyleft aimed at SaaS).

## Decision

License the project under **Apache-2.0**.

## Consequences

- **Permissive** — maximizes adoption and collaboration like MIT — but adds an
  **explicit patent grant** and a clear NOTICE/attribution mechanism, sensible for a
  tool that exercises Microsoft APIs and may be distributed to clients.
- **Follow-ups:** add a top-level `LICENSE` file (Apache-2.0 text), update the README
  **License** section (currently "TBD / all rights reserved"), and add SPDX
  `Apache-2.0` identifiers per the contributing conventions.
- **Trade-off:** slightly more verbose than MIT (NOTICE handling) — accepted for the
  patent-grant clarity.

## Alternatives considered

- **MIT** — simplest and fully permissive, but **no explicit patent grant**; viable if
  simplicity is later preferred over patent clarity.
- **AGPL-3.0** — rejected: network-copyleft aimed at SaaS deployments; deters some
  collaborators and mismatches a distributed, non-hosted CLI/dashboard tool.
- **Proprietary / all-rights-reserved** — rejected: blocks the sharing and
  collaboration the vision depends on.
