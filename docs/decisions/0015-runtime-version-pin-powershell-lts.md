# 0015. Runtime version pin: PowerShell 7.6 LTS / .NET 10 (floor = target)

- **Status:** Accepted — **amended 2026-07-25** (independent review of MCA-39):
  floor raised 7.4 → 7.6; floor and target collapsed. See "Amendment" below.
- **Date:** 2026-07-25
- **Deciders:** Project owner
- **Requirements:** NFR-4, NFR-7, NFR-8
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

Pin the runtime to **one version pair: PowerShell 7.6.x (LTS) on .NET 10 (LTS)**.

- **Floor = target: PowerShell 7.6.** The module manifest requires `7.6`; the
  container base image and CI pin the same pair, so shipped behaviour is
  reproducible and matches what we test.
- **Revisit triggers:** (a) a newer PowerShell LTS ships, (b) 7.6 approaches its
  14-Nov-2028 end of support, or (c) a module-pin bump changes its runtime
  requirement. Each is a deliberate amendment here — never a silent drift.

### Amendment (2026-07-25, from the independent MCA-39 review)

As first accepted, this ADR set a **7.4 floor** with a 7.6 target, to let a
laptop on the previous LTS run the tool through the ~3.5-month overlap window.
The independent review found that floor **unreachable**: the pinned
`ExchangeOnlineManagement` **3.10.0** (module pin, MCA-2) *requires PowerShell
7.6+* due to .NET 10 assembly dependencies — a constraint Microsoft documents
and the project's own research recorded
([research 02](../research/02-exchange-online-surface.md) §7). On 7.4 the
manifest would accept the import and the EXO module would fail later with an
assembly-load error — exactly the confusing late failure NFR-6 exists to
prevent. The overlap the 7.4 floor was preserving was therefore already
foreclosed. The alternative (downgrading the EXO pin to 3.9.2) was rejected:
it ships a superseded module and forgoes .NET 10 for a type surface we don't
need to keep.

The module-pin ↔ runtime coupling is now recorded beside the pin in
`Get-M365RequiredModule.ps1` and **guarded by tests**
(`tests/M365Configurator.Manifest.Tests.ps1`), so a future runtime or module
bump cannot silently re-break it.

## Consequences

- **NFR-7 (syntax-stability) now covers the runtime, not just the modules** — the
  .NET type surface we lean on is fixed by a pinned base image rather than
  inherited from whatever the host happens to have.
- **NFR-8 (reproducible build)** gains a real anchor: the container build is
  deterministic across rebuilds instead of floating with `latest`.
- **NFR-3 (minimal dependencies)** is unaffected — this pins an existing
  dependency rather than adding one (hence NFR-3 is not claimed in the header).
- **The manifest floor is now honest.** `Import-Module` fails fast with a clear
  version error on an unsupported runtime, instead of loading and failing later in
  an unrelated place (NFR-6). The bootstrap/install scripts additionally check the
  full version *before* the module import so downlevel hosts get an actionable
  message with the install URL (ADR-0011), not PowerShell's terse `#requires`
  error.
- **Trade-off — one exact type surface.** Floor = target means anyone below 7.6
  cannot run the tool at all. Accepted: the EXO module pin imposes 7.6 anyway,
  and a single pinned pair is maximally reproducible (NFR-7/NFR-8).
- **Follow-up:** the container base-image pin lands with the Dockerfile in MCA-9.
  Note (checked 2026-07-25): `mcr.microsoft.com/powershell` publishes **no 7.6
  image yet** (newest is 7.5) — until it does, the container/CI install pinned
  7.6.x from the official GitHub release artifacts.
- **Follow-up:** there is no CI yet (`.github/workflows/` does not exist). When it
  lands it runs the suite on the **pinned 7.6.x** (floor = target, so a single
  leg verifies the window). Until then the coverage is the owner's workstation
  (7.6.4) and the dev container (7.6).

## Alternatives considered

- **Floor 7.4 LTS with target 7.6 (the original decision)** — retracted by the
  2026-07-25 amendment: the pinned EXO module forecloses 7.4, so the floor
  advertised support it could not deliver (see Amendment).
- **Keep the 7.4 floor and downgrade `ExchangeOnlineManagement` to 3.9.2** —
  rejected: genuinely restores the overlap window, but ships a superseded module
  and forgoes .NET 10 to preserve compatibility we have no user demand for.
- **Pin to 7.4 / .NET 8 as the conservative LTS** — rejected: end-of-support
  10-Nov-2026. Pinning *to* a runtime about to expire buys no stability.
- **Track `latest` / leave the floor at 7.0** — rejected: directly contradicts
  NFR-7 and NFR-8, and the 7.0 floor was actively misleading about what we support.
- **Pin only the container, leave the manifest floor alone** — rejected: the CLI is
  the primary interface for v1 (ADR-0012) and runs on host `pwsh` outside the
  container, so the floor is a real gate, not a formality.
