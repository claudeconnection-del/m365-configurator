# 0015. Runtime version pin: floor PowerShell 7.4 LTS, target 7.6 LTS / .NET 10

- **Status:** Accepted
- **Date:** 2026-07-25
- **Deciders:** Project owner
- **Requirements:** NFR-3, NFR-4, NFR-7, NFR-8
- **Related:** ADR-0005 (core runtime: pure PowerShell 7), ADR-0007 (container runtime model); Jira MCA-39, MCA-9

## Context

ADR-0005 settled *which* runtime we build on — pure PowerShell 7 — but pinned no
**version**. That left a gap in the stability tenet: NFR-7 promises "module
versions are pinned; upgrades are deliberate", and
[`scripts/install-modules.ps1`](../../scripts/install-modules.ps1) is the single
source of truth for those module pins — but nothing pinned the runtime *hosting*
those modules. Two concrete symptoms:

1. The module manifest declared `PowerShellVersion = '7.0'`. **PowerShell 7.0
   reached end-of-support on 03-Dec-2022**, so the manifest advertised support for
   a runtime that had been dead for over three years while imposing no meaningful
   floor. Anything from 7.0 up satisfied it.
2. There is no Dockerfile yet, so the container runtime is unpinned *by absence* —
   a base image of `powershell:latest` would silently float across .NET major
   versions between builds, which ADR-0007 (one-shot ephemeral container) and NFR-8
   (reproducible build from a fresh clone) both depend on not happening.

This matters more than a normal version bump because PowerShell exposes the
underlying .NET types directly. We rely on that surface — `System.Collections.
Generic.HashSet[string]` with an explicit `StringComparer` for plan ordering,
`System.Collections.IDictionary` and `System.Management.Automation.PSCustomObject`
type probes in the compare path. A floating .NET is a floating type surface, and
NFR-7's syntax-stability promise extends to it.

PowerShell's support lifecycle follows .NET's. As verified against the
[PowerShell Support Lifecycle](https://learn.microsoft.com/powershell/scripting/install/powershell-support-lifecycle)
on 2026-07-25:

| Version | Released | End-of-support | .NET |
| --- | --- | --- | --- |
| 7.4 (LTS) | 16-Nov-2023 | 10-Nov-2026 | .NET 8 (LTS) |
| 7.5 (Stable) | 23-Jan-2025 | 10-Nov-2026 | .NET 9 |
| **7.6 (LTS)** | 18-Mar-2026 | **14-Nov-2028** | **.NET 10 (LTS)** |

7.6 is the current LTS and the only line with runway past Nov 2026. Both 7.4 and
7.5 expire 10-Nov-2026.

## Decision

Pin the runtime at two levels:

- **Floor: PowerShell 7.4 (LTS).** The module manifest requires `7.4`, so a
  consultant laptop still on the previous LTS can run the tool through the overlap
  window. This is a *floor*, not a target.
- **Target: PowerShell 7.6.x (LTS) on .NET 10 (LTS).** The container base image
  (`mcr.microsoft.com/powershell:7.6-<distro>`) and CI both pin to this exact pair,
  so shipped behaviour is reproducible and matches what we test.

**Revisit trigger: 10-Nov-2026**, when 7.4 goes out of support. At that point the
floor rises to 7.6 and this ADR is amended — not silently drifted.

We deliberately do **not** pin to 7.4/.NET 8 as the target despite it being the
older, more conservative LTS: it has under four months of support left, so
"conservative" would mean shipping on a runtime that goes dark before the tool
does.

## Consequences

- **NFR-7 (syntax-stability) now covers the runtime, not just the modules** — the
  .NET type surface we lean on is fixed by a pinned base image rather than
  inherited from whatever the host happens to have.
- **NFR-8 (reproducible build)** gains a real anchor: the container build is
  deterministic across rebuilds instead of floating with `latest`.
- **NFR-3 (minimal dependencies)** is unaffected — this pins an existing
  dependency rather than adding one.
- **The manifest floor is now honest.** `Import-Module` fails fast with a clear
  version error on an unsupported runtime, instead of loading and failing later in
  an unrelated place (NFR-6).
- **Trade-off — a supported-version window, not a single version.** Accepting 7.4
  through 7.6 means the .NET surface is not identical across every environment the
  module *can* load in, only across the one we *ship*. Mitigated by CI running the
  pinned target and by the floor rising at the revisit trigger. Tests must not
  depend on .NET-10-only APIs while the floor is 7.4.
- **Follow-up:** the container base-image pin lands with the Dockerfile in MCA-9;
  this ADR records the value to use so that work has no open question.
- **Follow-up:** there is no CI yet (`.github/workflows/` does not exist). When it
  lands it should run the suite as a **matrix over both ends of the window** — 7.4
  (floor) and 7.6 (target) — which is the only way the trade-off above is actually
  verified rather than assumed. Until then the coverage is incidental: the dev
  container runs 7.4 and the owner's workstation runs 7.6.4.

## Alternatives considered

- **Hard-pin a single version (7.6 only), floor and target identical** — rejected
  for now: maximally reproducible, but locks out anyone on 7.4 LTS for the ~3.5
  months both are supported, for a type surface we do not currently depend on. This
  becomes the position automatically at the 10-Nov-2026 revisit.
- **Pin to 7.4 / .NET 8 as the conservative LTS** — rejected: end-of-support
  10-Nov-2026. Pinning *to* a runtime about to expire buys no stability.
- **Track `latest` / leave the floor at 7.0** — rejected: directly contradicts
  NFR-7 and NFR-8, and the 7.0 floor was actively misleading about what we support.
- **Pin only the container, leave the manifest floor alone** — rejected: the CLI is
  the primary interface for v1 (ADR-0012) and runs on host `pwsh` outside the
  container, so the floor is a real gate, not a formality.
