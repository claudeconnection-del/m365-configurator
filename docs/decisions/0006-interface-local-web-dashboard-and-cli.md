# 0006. Interface: local ephemeral web dashboard, with a first-class CLI

- **Status:** Accepted — **amended by [ADR-0012](0012-cli-first-interface-gui-deferred.md) (2026-07-23):** the CLI is now the primary interface for v1 and the web dashboard is **deferred** until the functional surface is proven in the CLI. The dashboard requirements below are retained as the spec for that future work; they do **not** apply to v1.
- **Date:** 2026-07-22
- **Deciders:** Project owner + team
- **Requirements:** FR-4, FR-8, FR-12, NFR-1, NFR-2, NFR-3, NFR-9
- **Related:** OPEN-QUESTIONS Q2; `docs/research/06-prior-art-and-architecture.md` §6.2; ADR-0001, ADR-0005, ADR-0007

## Context

The vision calls for an interface that is **easy and satisfying** — the owner's
framing is a "configurator" that pares the sprawling M365 admin dashboards down to a
**profile- and configuration-focused dashboard**. Ease of use is a **core product
goal**, not a nicety.

Research 06 §6.2 recommended a CLI plus a *generated* self-contained HTML report,
explicitly to avoid the cost of a live web UI — but that argument was really an
argument against the **CIPP model**: an always-on *hosted*, *multi-tenant* service
that stores *long-lived refresh tokens* in an Azure Key Vault. At the checkpoint the
owner weighed ease-of-use above that and chose a genuine GUI dashboard.

Candidate GUI shapes for a containerized, pwsh-core tool: a **TUI**, a **native
desktop app**, or a **local browser dashboard**.

## Decision

The **primary interface is a local, ephemeral, browser-based dashboard** served by
the container on **`localhost`** (pure-PowerShell server per ADR-0005, e.g.
Pode/Pode.Web; front-end assets self-contained). A **first-class CLI** is the
secondary surface for automation, CI, and power users. **TUI and native desktop are
rejected as the core.**

This is *not* the CIPP web model. The tenet risk in a web UI comes from the CIPP
shape (hosted, always-on, multi-tenant, stored long-lived credentials, Azure
dependency). A **local / ephemeral / single-tenant / memory-only / no-egress**
dashboard avoids every one of those:

- **Localhost-only bind** — reachable only from the operator's machine while the
  container runs; no public surface.
- **Ephemeral** — lives and dies with the one-shot container (ADR-0007); tokens stay
  in the pwsh process memory, never on disk (ADR-0001, NFR-1).
- **No phone-home** — UI assets are bundled; a strict content policy blocks any
  external fetch (NFR-2).

## Consequences

- Delivers the "satisfying configurator dashboard" **reliably and portably** — the
  operator opens a localhost URL in their normal host browser; no terminal-rendering
  fragility, no display server.
- **Honest cost:** a web layer is a **larger dependency and attack surface** than a
  bare CLI — a real **NFR-3** hit, accepted because ease-of-use is a core product
  goal. It is bounded by keeping the server pure-pwsh (ADR-0005) and local-only.
- **New hard requirements** this creates: bind `localhost` only; never persist
  tokens; the dashboard and any generated report **must never render a secret**
  (NFR-1/NFR-5); enforce a no-external-fetch content policy (NFR-2). These are
  audited as security-review items (Phase 5).
- **One diff renderer** feeds both the dashboard and the CLI for dry-run and drift, so
  reviewers learn a single format (NFR-9).

## Alternatives considered

- **CLI + generated static HTML report only** (the research recommendation) —
  rejected: meets "reviewable" but not the interactive **configurator dashboard**
  the product is centered on.
- **TUI (terminal dashboard)** — rejected as the core: PowerShell's TUI tooling is
  thin (driving `Terminal.Gui`/gui.cs from pwsh is non-idiomatic) and terminals are
  inherently unreliable for a dashboard (rendering, input, resize, Unicode across
  emulators/SSH/containers) — higher effort, lower ceiling than a browser UI. A
  polished rich-CLI remains a fine *secondary* experience.
- **Native desktop (Electron/Tauri/Avalonia)** — rejected: a GUI inside a container
  needs a display server (X/VNC), which fights the containerized/portable tenet
  (NFR-4).
