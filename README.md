# m365-configurator

> A portable, containerized tool for configuring Microsoft 365 tenants (Microsoft
> Graph + Exchange Online, and related PowerShell-driven surfaces) from reusable,
> reviewable configuration profiles — with verbose audit logging, dry-run
> previews, drift detection, and deterministic remediation.

**Status:** 🌱 Scaffolding / research phase. There is no application code yet — this
commit establishes a reproducible development environment and captures the project
vision so work can be picked up on any machine. See [`docs/ROADMAP.md`](docs/ROADMAP.md)
for what comes next and [`docs/OPEN-QUESTIONS.md`](docs/OPEN-QUESTIONS.md) for
decisions that are still open.

---

## What this project is

A consultant/operator tool that:

- **Bootstraps itself** — makes sure the required PowerShell modules
  (`Microsoft.Graph`, `ExchangeOnlineManagement`, and others as relevant) are
  installed and imported.
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

## Design tenets (baked in from day one)

These are the non-negotiables the whole project is built around. See
[`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md) for the full, testable list.

1. **Security is paramount.** No credentials are ever written to disk. Nothing
   "phones home" — the app only talks to endpoints it is explicitly told to.
2. **Minimal dependencies.** Fewer moving parts = fewer things to break or trust.
3. **Containerized & portable.** Runs the same everywhere.
4. **Audit-grade logging.** Verbose, structured, easily retrievable.
5. **Loud, fast failure.** Errors surface immediately and clearly — no silent
   partial application.
6. **Stability by construction.** As long as the underlying PowerShell module
   syntax is stable, this tool is stable. Version-pinning is a first-class concern.
7. **Reviewable, deterministic changes.** Dry-run first; diffs and remediations
   are predictable and explainable.
8. **Readability for the human inspecting it.** Code, profiles, logs, diffs, and
   dry-run output are formatted for fast visual inspection — consistent, aligned,
   and scannable. If a human has to squint to verify what will change, that's a bug.

## Quickstart — clone and develop anywhere

```bash
git clone <this-repo-url>
cd m365-configurator
git checkout claude/m365-exchange-config-app-1hko7b
```

Then pick **one** of:

### Option A — Dev Container (recommended, most reproducible)

Open the folder in VS Code with the **Dev Containers** extension and choose
**"Reopen in Container"** (or use the Dev Containers CLI). The container ships
PowerShell 7 and runs [`scripts/install-modules.ps1`](scripts/install-modules.ps1)
automatically, so the M365 modules are ready when it finishes building.

### Option B — Local PowerShell 7+

If you already have [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)
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

## Repository layout

```
.
├── README.md                 ← you are here
├── CONTRIBUTING.md           ← dev workflow, branch strategy, review process
├── .devcontainer/            ← reproducible dev environment (pwsh + modules)
├── scripts/                  ← bootstrap & module-install helpers
│   ├── bootstrap.ps1         ← one-shot setup from PowerShell
│   ├── bootstrap.sh          ← one-shot setup from a POSIX shell
│   └── install-modules.ps1   ← installs/reports the M365 PowerShell modules
├── docs/
│   ├── VISION.md             ← the north star, captured verbatim in intent
│   ├── REQUIREMENTS.md       ← functional & non-functional requirements
│   ├── ROADMAP.md            ← phased plan: research → design → build
│   ├── OPEN-QUESTIONS.md     ← decisions awaiting input
│   └── decisions/            ← Architecture Decision Records (ADRs)
├── profiles/                 ← saved configuration profiles (config only, NEVER secrets)
├── .gitignore                ← security-first: secrets/tokens/logs never committed
├── .gitattributes
└── .editorconfig
```

## Where to go next

- **Understand the goal:** [`docs/VISION.md`](docs/VISION.md)
- **See the plan:** [`docs/ROADMAP.md`](docs/ROADMAP.md)
- **Help decide open items:** [`docs/OPEN-QUESTIONS.md`](docs/OPEN-QUESTIONS.md)
- **Start contributing:** [`CONTRIBUTING.md`](CONTRIBUTING.md)

## License

TBD — see [`docs/OPEN-QUESTIONS.md`](docs/OPEN-QUESTIONS.md). Until a license is
chosen, this code is "all rights reserved" by default.
