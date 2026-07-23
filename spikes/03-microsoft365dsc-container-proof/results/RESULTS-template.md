# Microsoft365DSC container proof — results log

Copy this file to `results/RESULTS-<date>.md` and fill it in from a run. The probe
scripts also drop timestamped `results-*.json` / `results-*.md` here automatically;
this template is the human-curated verdict that feeds the ADR-0002 decision.

## Environment

| Field | Value |
| --- | --- |
| Date (UTC) | |
| Host OS / Docker | |
| Image (linux/windows) | |
| Microsoft365DSC version (pinned) | |
| PowerShell version | |
| Tenant used (yes/no; test tenant?) | |
| Auth mode (none / device-code / app-cert) | |

## Findings — the R1–R9 matrix (from docs/research/03-microsoft365dsc.md §10)

| # | Question | Expected (from research) | Observed | Verdict |
| --- | --- | --- | --- | --- |
| R1 | Does `Export-M365DSCConfiguration` / import run on Linux+pwsh7? | Import reported broken (#3144) | | ☐ confirms ☐ refutes |
| R2 | Any *apply* on Linux (`Invoke-DscResource`) vs Windows LCM? | Linux: no LCM; Windows: works | | ☐ confirms ☐ refutes |
| R3 | Total on-disk footprint vs the ~5-module custom slice | Much heavier (NFR-3 cost) | | ☐ confirms ☐ refutes |
| R4 | Graph dep = Authentication only, or many sub-modules? | Authentication only (per manifest) | | ☐ confirms ☐ refutes |
| R5 | Cert re-check with an ephemeral-only cert store? | Needs persistent key at rest | | ☐ confirms ☐ refutes |
| R6 | Does a compiled MOF embed secrets (app-only auth)? | Plaintext-by-default; cert-encrypt is decryptable | | ☐ confirms ☐ refutes |
| R7 | Delta-report false positives on identical exports? | Known ResourceID / CA-exclusion FPs | | ☐ confirms ☐ refutes |
| R8 | Windows image size / licensing if fallback chosen | Multi-GB Windows base | | ☐ confirms ☐ refutes |
| R9 | Pin & re-verify against the exact shipped release | Dev-branch manifest may drift | | ☐ confirms ☐ refutes |

## Decision input for ADR-0002

- Does the evidence support **reject-as-primary** (custom Graph/EXO engine), or does
  it open a viable Windows-container path? 
- If Windows-container is pursued, list the accepted exceptions (NFR-4 portability,
  ADR-0001 app-cert auth, NFR-1 cleanup surface, NFR-3 footprint).

_Summary verdict:_ 

_Recommended ADR-0002 status change (if any):_ 
