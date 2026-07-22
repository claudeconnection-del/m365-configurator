# Open questions

Decisions awaiting input. Each becomes an ADR in [`decisions/`](decisions/) once
resolved. The **Phase 2 design checkpoint (2026-07-22)** resolved the architecture,
interface, and profile questions with the project owner — see the Resolved table.

## Architecture & runtime

- ✅ **Q1 — Core language/runtime.** **RESOLVED:** pure **PowerShell 7** module/app;
  no second-language front-end. The local web server is also PowerShell (single
  runtime). See [ADR-0005](decisions/0005-core-runtime-powershell-7.md).
- ✅ **Q2 — Interface.** **RESOLVED:** a **local, ephemeral, browser-based dashboard**
  (localhost, pure-pwsh server) is the primary interface — a "configurator" that
  pares the M365 admin consoles down to a profile/config view — with a **first-class
  CLI** alongside. TUI/native desktop rejected as the core. This intentionally
  overrides the research's CLI-first recommendation: ease-of-use is a core product
  goal. See [ADR-0006](decisions/0006-interface-local-web-dashboard-and-cli.md).
- ✅ **Q3 — Container runtime model.** **RESOLVED:** a **one-shot, ephemeral**
  container that serves the localhost UI while running, then is discarded; runs on a
  consultant laptop per engagement, not as a shared service. See
  [ADR-0007](decisions/0007-container-runtime-model.md).

## Security & authentication

- ✅ **Q4 — Authentication method(s).** **RESOLVED:** interactive delegated
  (browser) + device code flow, tokens **memory-only**. See
  [ADR-0001](decisions/0001-authentication-interactive-and-device-code.md).
- **Q5 — Certificate handling.** Deferred with app-only auth. If adopted, certs
  must be runtime-supplied and never persisted. _Revisit if unattended automation
  is needed._

## Scope

- ✅ **Q6 — MVP surface.** **RESOLVED:** security baseline first. See
  [ADR-0003](decisions/0003-mvp-scope-security-baseline-first.md). Specific control
  list defined in `docs/research/05-security-baselines.md` (~11-control v1 slice).
- ✅ **Q7 — DSC.** **RESOLVED:** **reject Microsoft365DSC as the primary engine**;
  build a custom Graph/EXO engine, reusing M365DSC's cross-platform export +
  offline delta-report tooling only. Ratified without a container proof. See
  [ADR-0002](decisions/0002-evaluate-microsoft365dsc-as-engine.md) (now *Accepted*)
  and `docs/research/03-microsoft365dsc.md`.

## Profiles & data

- ✅ **Q8 — Profile format.** **RESOLVED:** **YAML** to author, **JSON** as the
  canonical (diff/interchange) form; `.psd1` is the documented minimal-deps fallback.
  See [ADR-0008](decisions/0008-profile-format-yaml-authored-json-canonical.md).
- ✅ **Q9 — Profile sharing/versioning.** **RESOLVED:** **Git-committed,
  credential-free** profiles + single-file export/import; known-good baselines as
  **git tags**; reference baseline shipped in-repo under `profiles/`. See
  [ADR-0009](decisions/0009-profile-sharing-and-versioning.md).

## Project meta

- ✅ **Q10 — License.** **RESOLVED:** **Apache-2.0**. See
  [ADR-0010](decisions/0010-license-apache-2.md). _Follow-up:_ add `LICENSE`, update
  README's License section.
- ✅ **Q11 — Confluence space.** **RESOLVED:** Software Development (`SD`). See
  [ADR-0004](decisions/0004-documentation-location.md). Jira project key is **`MCA`**.

---

### Resolved

| Q | Decision | Record |
|---|----------|--------|
| Q1 | Runtime = pure PowerShell 7 | ADR-0005 |
| Q2 | Interface = local ephemeral web dashboard + first-class CLI | ADR-0006 |
| Q3 | Container = one-shot, ephemeral, serves localhost UI | ADR-0007 |
| Q4 | Auth = interactive delegated + device code, memory-only | ADR-0001 |
| Q6 | MVP = security baseline first | ADR-0003 |
| Q7 | Microsoft365DSC = reject-as-primary; custom Graph/EXO engine | ADR-0002 |
| Q8 | Profile format = YAML authored, JSON canonical | ADR-0008 |
| Q9 | Profiles = Git-committed + export; baselines as git tags | ADR-0009 |
| Q10 | License = Apache-2.0 | ADR-0010 |
| Q11 | Docs in repo `docs/` + Confluence SD | ADR-0004 |

### Still open

- **Q5 — Certificate handling** — deferred until (and if) unattended/app-only
  automation is needed; certs must be runtime-supplied, never persisted.
