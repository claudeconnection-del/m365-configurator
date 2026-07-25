# 0014. Graph access via `Invoke-MgGraphRequest` (raw REST), not typed sub-module cmdlets

- **Status:** Accepted
- **Date:** 2026-07-25
- **Deciders:** Project owner (direct decision during the Phase 4 build)
- **Requirements:** FR-4; NFR-3 (minimal dependencies), NFR-4 (containerized & portable), NFR-7 (stability via pinned versions)
- **Related:** ADR-0002 (custom Graph/EXO engine), ADR-0013 (control-provider contract); Jira MCA-4, MCA-22; `docs/research/01-microsoft-graph-surface.md` §2.3, §4

## Context

ADR-0013 makes each Graph control a `Get`/`Set` handler. Those seams have to
actually talk to Microsoft Graph, and there are two ways to do it from PowerShell:

1. **Typed sub-module cmdlets** — e.g. `Get-/Update-MgPolicyIdentitySecurityDefaultEnforcementPolicy`.
   These are what research 01 catalogues per control. They give typed request/response
   objects and parameter validation, but each lives in a **separate Graph
   sub-module** (`Microsoft.Graph.Identity.SignIns`, `.Applications`,
   `.Identity.DirectoryManagement`, …). The full SDK is 33 modules / ~950 MB
   (research 01 §2.1); even the baseline subset pulls in several sub-modules.
2. **Raw REST via `Invoke-MgGraphRequest`** — a single cmdlet that ships in
   **`Microsoft.Graph.Authentication`**, the one Graph module we already pin and
   already require for `Connect-MgGraph`. It sends `GET`/`PATCH`/`POST` to a Graph
   URI and returns a hashtable.

The project's tenets pull hard toward option 2: **minimal dependencies** (NFR-3),
**containerized & portable / small image** (NFR-4), and **fewer pinned versions to
track** (NFR-7). The connection foundation already standardised on
`Microsoft.Graph.Authentication` only.

## Decision

**Graph control handlers issue raw REST calls through `Invoke-MgGraphRequest`
against explicit v1.0 endpoints; the project does not take a dependency on the
typed Graph sub-modules for the security-baseline surface.**

- The single pinned Graph module stays **`Microsoft.Graph.Authentication`**
  (already in `Get-M365RequiredModule`). No sub-modules are added to the pin set
  for the v1 slice.
- Handlers issue the raw REST call through **one thin module seam**,
  `Invoke-M365GraphRequest` (private), which wraps `Invoke-MgGraphRequest`. This
  keeps the SDK touch-point in a single place — the one spot to add paging
  (`@odata.nextLink`), retry, and Graph-error interpretation later — and gives the
  tests a module-owned mock target that does not depend on the SDK being importable
  in the test session.
- Each handler owns its endpoint and its field mapping. Example (ID-1, verified
  against Microsoft Learn, graph-rest-1.0):
  - `Get`: `Invoke-M365GraphRequest -Method GET  -Uri 'v1.0/policies/identitySecurityDefaultsEnforcementPolicy'`
    → project the secret-free config shape `@{ isEnabled = [bool] $response.isEnabled }`.
  - `Set`: `Invoke-M365GraphRequest -Method PATCH -Uri '…' -Body @{ isEnabled = $Desired.isEnabled }`
    (204 No Content on success).
- `Invoke-M365GraphRequest` is the **single seam** the tests mock
  (`Mock Invoke-M365GraphRequest -ModuleName M365Configurator`), so every handler
  is exercised with real request/response shaping but no tenant — the same
  scriptblock-seam discipline used across the connection and profile layers.
- Beta endpoints are used only where v1.0 lacks a control, and each such use is
  called out in the handler (research 01 flags the AM-4/AM-5 cases).

## Consequences

- **Minimal dependency surface (NFR-3/NFR-4).** The whole Graph provider rides on
  one already-pinned module; the container doesn't grow per control, and there is
  no per-sub-module version matrix to keep in sync (NFR-7).
- **One uniform call + mock path.** Every Graph handler looks the same and is
  tested the same way (one mock target), which keeps controls small and reviewable
  (the ADR-0013 "additive, local" property).
- **We own the shapes.** Without typed objects, each handler explicitly maps the
  JSON it needs — which is *desirable* here: it forces the secret-free projection
  (NFR-1) and the exact desired-state field set to be written down per control,
  and it feeds the canonical-diff (`Get` output is already a plain map).
- **Trade-off — no SDK typing/validation.** We don't get compile-time-ish
  parameter checking or model classes; a wrong field name surfaces at call time.
  Mitigated by grounding each endpoint against Microsoft Learn, pinning to v1.0,
  and covering each handler with tests.
- **Trade-off — manual paging/errors.** For collection controls (CA policies,
  MCA-23/24) the handler must page (`@odata.nextLink`) and interpret Graph errors
  itself, rather than leaning on a cmdlet. Acceptable and localised to the few
  collection handlers.
- **Reversible per control.** Nothing stops a future control from importing a
  typed sub-module if a specific surface makes raw REST impractical; this decision
  sets the default, not an absolute ban. Such a case would be its own ADR note.

## Alternatives considered

- **Typed sub-module cmdlets as the default.** Rejected: the dependency, image-size,
  and version-pinning cost conflicts with NFR-3/NFR-4/NFR-7 for little gain, since
  the baseline surface is a modest, well-understood set of endpoints we can map by
  hand. (Research 01 §2.3 already scoped "which sub-modules the baseline needs" —
  this decision avoids needing them at all for v1.)
- **A thin typed wrapper generated from the OpenAPI metadata.** Rejected as
  over-engineering for the v1 slice; revisit only if the hand-mapped surface grows
  unwieldy.
