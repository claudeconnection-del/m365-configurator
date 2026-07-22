# Open questions

Decisions awaiting input. Each becomes an ADR in [`decisions/`](decisions/) once
resolved. Most are best answered *after* Phase 1 research, but a few shape that
research and are worth settling early (marked ⏱️ **early**).

## Architecture & runtime

- ⏱️ **Q1 — Core language/runtime.** The app fundamentally drives PowerShell
  modules. Options: (a) pure PowerShell 7 module/app; (b) a thin front-end in
  another language (Python/Go/Node) that invokes `pwsh`. Trade-off: minimal
  dependencies & syntax-stability (favors pure pwsh) vs. richer UI/tooling.
- ⏱️ **Q2 — Interface.** CLI, TUI, or a locally-served web UI? "Easy and
  satisfying to interact with" + "containerized" leans toward a local web UI or a
  polished TUI. This heavily shapes the architecture.
- **Q3 — Container runtime model.** One-shot CLI container vs. long-running service
  container hosting the UI. Where is it expected to run (consultant laptop
  per-engagement vs. a shared server)?

## Security & authentication

- ⏱️ **Q4 — Authentication method(s).** Which to support first: interactive
  delegated (browser), device-code, app-only with certificate, managed identity?
  This is central to "no credentials on disk" and "full cleanup between sessions."
- **Q5 — Certificate handling.** If app-only/cert auth is supported, how are certs
  supplied at runtime without persisting them (mounted secret, in-memory only)?

## Scope

- **Q6 — MVP surface.** Start focused on a security-baseline slice (e.g.
  conditional access, authentication methods, anti-phishing/anti-spam) vs. broad
  coverage? Which specific settings matter most first?
- **Q7 — DSC.** Is **Microsoft365DSC** in scope as an engine (it already models
  much of M365 as DSC and supports export/drift), as an alternative to a
  hand-rolled profile/drift engine, or out of scope? (Owner noted difficulty
  getting DSC working — research will assess whether it earns its place.)

## Profiles & data

- **Q8 — Profile format.** JSON, YAML, or PowerShell data (`.psd1`)? Must be
  human-readable, diff-friendly, and config-only.
- **Q9 — Profile sharing/versioning.** Are profiles committed to this repo, kept
  in a separate repo, or purely exported files? How is a "known-good baseline"
  versioned over time?

## Project meta

- **Q10 — License.** What license (if any)? Affects sharing/collaboration.
- **Q11 — Confluence space.** Which Confluence space should the research and design
  docs live in? (Jira project key is confirmed as **`MCA`**.)

---

### Resolved

_None yet._
