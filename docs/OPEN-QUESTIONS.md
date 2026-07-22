# Open questions

Decisions awaiting input. Each becomes an ADR in [`decisions/`](decisions/) once
resolved. Most are best answered *after* Phase 1 research, but a few shape that
research and are worth settling early (marked ⏱️ **early**).

## Architecture & runtime

- ⏱️ **Q1 — Core language/runtime.** The app fundamentally drives PowerShell
  modules. Options: (a) pure PowerShell 7 module/app; (b) a thin front-end in
  another language (Python/Go/Node) that invokes `pwsh`. Trade-off: minimal
  dependencies & syntax-stability (favors pure pwsh) vs. richer UI/tooling.
  _To be recommended at the design checkpoint (see `docs/research/06-...`)._
- ⏱️ **Q2 — Interface.** CLI, TUI, or a locally-served web UI? "Easy and
  satisfying to interact with" + "containerized" leans toward a local web UI or a
  polished TUI. _To be recommended at the design checkpoint._
- **Q3 — Container runtime model.** One-shot CLI container vs. long-running service
  container hosting the UI. Where is it expected to run (consultant laptop
  per-engagement vs. a shared server)? _Design checkpoint._

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
  list is being defined in `docs/research/05-security-baselines.md`.
- 🔬 **Q7 — DSC.** **DIRECTION SET:** seriously evaluate **Microsoft365DSC** as the
  engine ([ADR-0002](decisions/0002-evaluate-microsoft365dsc-as-engine.md), status
  *Proposed*). Confirmation depends on the research spike
  (`docs/research/03-microsoft365dsc.md`) + a hands-on container proof, especially
  the Linux/PowerShell-7 question and auth compatibility with Q4.

## Profiles & data

- **Q8 — Profile format.** JSON, YAML, or PowerShell data (`.psd1`)? Must be
  human-readable, diff-friendly, and config-only. _To be recommended at the design
  checkpoint (research 06)._
- **Q9 — Profile sharing/versioning.** Are profiles committed to this repo, kept in
  a separate repo, or purely exported files? How is a "known-good baseline"
  versioned over time? _Design checkpoint._

## Project meta

- **Q10 — License.** What license (if any)? Affects sharing/collaboration.
  _Awaiting owner input._
- ✅ **Q11 — Confluence space.** **RESOLVED:** Software Development (`SD`). See
  [ADR-0004](decisions/0004-documentation-location.md). Jira project key is **`MCA`**.

---

### Resolved

| Q | Decision | Record |
|---|----------|--------|
| Q4 | Auth = interactive delegated + device code, memory-only | ADR-0001 |
| Q6 | MVP = security baseline first | ADR-0003 |
| Q7 | Direction: evaluate Microsoft365DSC as engine (proposed) | ADR-0002 |
| Q11 | Docs in repo `docs/` + Confluence SD | ADR-0004 |

### Still open (owner input welcome any time)

- **Q10 — License** (e.g. MIT / Apache-2.0 / proprietary).
- **Q1/Q2/Q8/Q9** — architecture, interface, and profile-format choices, which
  I'll bring as **recommendations at the design checkpoint** after research lands.
