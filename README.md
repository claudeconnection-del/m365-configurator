# m365-configurator

> A portable, containerized tool for configuring Microsoft 365 tenants (Microsoft
> Graph + Exchange Online, and related PowerShell-driven surfaces) from reusable,
> reviewable configuration profiles — with verbose audit logging, dry-run
> previews, drift detection, and deterministic remediation.

**Status:** 🔨 **Phase 4 — build in progress.** Phases 0–3 are complete: the reproducible
dev environment, the Phase 1 research corpus, the Phase 2 design decisions (recorded as
[ADRs 0001–0013](docs/decisions/)), and the Phase 3 Jira (`MCA`) backlog (8 workstream
epics + 28 stories). The first module has landed — [`src/M365Configurator/`](src/M365Configurator)
with a **self-healing** module preflight (ADR-0011) — developed test-first (see
[`tests/`](tests)). See [`docs/ROADMAP.md`](docs/ROADMAP.md); run `/resume` (or say
"resume") for a live, reconciled status.

---

## What this project is

A consultant/operator tool that:

- **Bootstraps itself** — makes sure the required PowerShell modules
  (`Microsoft.Graph`, `ExchangeOnlineManagement`, …) are installed and imported,
  and is **self-healing**: if one is missing or outdated it offers a consented fix
  (source + the exact command), never a dead-end (ADR-0011).
- **Connects and disconnects on demand** while running, with **full credential
  cleanup** between sessions — nothing sensitive is persisted.
- **Exposes the configurable surface** of the underlying PowerShell modules in a
  way that's easy and satisfying to work with.
- **Saves configuration profiles** (e.g. a known-good security baseline) that can
  be re-applied to future tenants — selected from a list or imported from an
  exported file for collaboration.
- **Dry-runs before applying** — preview every change, apply only when green.
- **Detects drift** from a saved profile and offers **deterministic remediation**.
- **Logs verbosely** for audit, with easy access to those logs, and **fails loud
  and fast** with proper error handling.

## Design tenets

The non-negotiables the whole project is built around — the **canonical summary**;
other docs point here. See [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md) for the
full, testable list.

1. **Security is paramount.** No credentials are ever written to disk. Nothing
   "phones home" — the app only talks to endpoints it is explicitly told to.
2. **Minimal dependencies.** Fewer moving parts = fewer things to break or trust.
3. **Containerized & portable.** Runs the same everywhere.
4. **Audit-grade logging.** Verbose, structured, easily retrievable.
5. **Loud, fast failure — but self-healing.** Errors surface immediately and
   clearly — no silent partial application. For *recoverable* preconditions (e.g.
   a missing module) the app offers a consented fix rather than a dead-end
   ([ADR-0011](docs/decisions/0011-self-healing-remediation-for-recoverable-preconditions.md)).
6. **Stability by construction.** As long as the underlying PowerShell module
   syntax is stable, this tool is stable. Version-pinning is a first-class concern —
   both the M365 modules and the **runtime** itself
   ([ADR-0015](docs/decisions/0015-runtime-version-pin-powershell-lts.md)).
7. **Reviewable, deterministic changes.** Dry-run first; diffs and remediations
   are predictable and explainable.
8. **Readability for the human inspecting it.** Code, profiles, logs, diffs, and
   dry-run output are formatted for fast visual inspection — consistent, aligned,
   and scannable. If a human has to squint to verify what will change, that's a bug.

## Quickstart — clone and develop anywhere

```bash
git clone <this-repo-url>
cd m365-configurator
```

Then pick **one** of:

### Option A — Dev Container (recommended, most reproducible)

Open the folder in VS Code with the **Dev Containers** extension and choose
**"Reopen in Container"** (or use the Dev Containers CLI). The container ships
PowerShell 7 and, on create, runs [`scripts/install-modules.ps1`](scripts/install-modules.ps1)
and [`scripts/install-dev-tools.ps1`](scripts/install-dev-tools.ps1) — so the M365
modules **and** the test runner (Pester) are ready, and you can run
`Invoke-Pester -Path tests/` as soon as it finishes building.

### Option B — Local PowerShell (7.4 LTS or newer)

If you already have a [supported PowerShell](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)
installed:

```bash
pwsh -NoProfile -File scripts/bootstrap.ps1
# or from an existing pwsh session:
#   ./scripts/bootstrap.ps1
```

This installs the required modules into your **CurrentUser** scope (no admin
rights, no system changes) and prints the versions it installed.

> **Nothing in bootstrap authenticates to any tenant.** It only installs modules
> from the PowerShell Gallery. Connecting to M365 is an explicit, interactive step
> that will live in the application itself.

### Supported PowerShell versions

Version-pinning covers the runtime as well as the modules
([ADR-0015](docs/decisions/0015-runtime-version-pin-powershell-lts.md)). PowerShell's
support lifecycle follows .NET's:

| | Version | .NET | Supported until |
| --- | --- | --- | --- |
| **Floor** (module manifest requires) | 7.4 LTS | .NET 8 | 10-Nov-2026 |
| **Target** (shipped container + CI) | 7.6 LTS | .NET 10 | 14-Nov-2028 |

Anything from 7.4 up will load. 7.5 works but is a non-LTS line that also expires
10-Nov-2026, so prefer 7.4 or 7.6. **7.0–7.3 are out of support and are rejected at
import** rather than failing later somewhere confusing.

The dev container pins the **floor** (7.4) on purpose — code that runs there runs on
the target too, but not the reverse, so developing against the floor catches
accidental use of APIs a 7.4 user could not run.

> At the **10-Nov-2026** revisit trigger, 7.4 leaves support and the floor rises to
> 7.6. That is a deliberate amendment to ADR-0015, not a silent drift.

## Running the tests

The project is built **test-first** with Pester 5+. Install the dev tooling once,
then run the suite:

```bash
pwsh -NoProfile -File scripts/install-dev-tools.ps1        # one-time; installs pinned Pester
pwsh -NoProfile -Command "Invoke-Pester -Path tests/"
```

The dev container (Option A) provisions Pester automatically, so there you can run
`Invoke-Pester -Path tests/` directly.

## Repository layout

```
.
├── README.md                 ← you are here
├── CLAUDE.md                 ← orientation + the /resume workflow (for AI sessions)
├── CONTRIBUTING.md           ← dev workflow, branch strategy, review process
├── LICENSE                   ← Apache-2.0 (ADR-0010)
├── .devcontainer/            ← reproducible dev environment (pwsh + modules + Pester)
├── .claude/                  ← repo-scoped Claude commands (e.g. /resume)
├── src/
│   └── M365Configurator/     ← the PowerShell module (manifest + Public/ functions)
├── tests/                    ← Pester specs (run with: Invoke-Pester -Path tests/)
├── scripts/                  ← bootstrap, module-install, and dev-tooling helpers
│   ├── bootstrap.ps1         ← one-shot setup from PowerShell
│   ├── bootstrap.sh          ← one-shot setup from a POSIX shell
│   ├── install-modules.ps1   ← installs/reports the pinned M365 modules (single source of truth)
│   ├── install-dev-tools.ps1 ← installs the pinned test runner (Pester)
│   └── repo-status.sh        ← repo side of the /resume reconciliation
├── docs/
│   ├── VISION.md             ← the north star, captured verbatim in intent
│   ├── REQUIREMENTS.md       ← functional & non-functional requirements + traceability
│   ├── ROADMAP.md            ← phased plan: research → design → build
│   ├── OPEN-QUESTIONS.md     ← decisions log (resolved items point to ADRs)
│   └── decisions/            ← Architecture Decision Records (ADRs 0001–0013)
├── profiles/                 ← saved configuration profiles (config only, NEVER secrets)
├── .gitignore                ← security-first: secrets/tokens/logs never committed
├── .gitattributes
└── .editorconfig
```

## Where to go next

- **Understand the goal:** [`docs/VISION.md`](docs/VISION.md)
- **See the plan:** [`docs/ROADMAP.md`](docs/ROADMAP.md)
- **Review the decisions:** [`docs/decisions/`](docs/decisions/) (ADRs 0001–0013)
- **Run the tests:** `Invoke-Pester -Path tests/` (see [Running the tests](#running-the-tests))
- **Start contributing:** [`CONTRIBUTING.md`](CONTRIBUTING.md)

## License

Licensed under the **Apache License 2.0** — see [`LICENSE`](LICENSE) and
[ADR-0010](docs/decisions/0010-license-apache-2.md).
