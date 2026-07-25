# Architecture Decision Records (ADRs)

We record significant, hard-to-reverse decisions as short, numbered ADRs so the
reasoning survives and anyone picking up the work understands *why*, not just
*what*.

## How to add one

1. Copy [`0000-template.md`](0000-template.md) to `NNNN-short-title.md`
   (next number, kebab-case title).
2. Fill it in. Keep it short — one decision per ADR.
3. Reference the requirement IDs it satisfies (see
   [`../REQUIREMENTS.md`](../REQUIREMENTS.md)) and any Jira issue (`MCA`).
4. Link related open questions from [`../OPEN-QUESTIONS.md`](../OPEN-QUESTIONS.md).

## Index

| # | Title | Status |
|---|-------|--------|
| [0001](0001-authentication-interactive-and-device-code.md) | Authentication: interactive delegated + device code, memory-only | Accepted |
| [0002](0002-evaluate-microsoft365dsc-as-engine.md) | Microsoft365DSC as primary engine — reject-as-primary; custom Graph/EXO engine | Accepted |
| [0003](0003-mvp-scope-security-baseline-first.md) | MVP scope: security baseline first | Accepted |
| [0004](0004-documentation-location.md) | Documentation lives in repo `docs/` + Confluence SD | Accepted |
| [0005](0005-core-runtime-powershell-7.md) | Core runtime: pure PowerShell 7 | Accepted |
| [0006](0006-interface-local-web-dashboard-and-cli.md) | Interface: local ephemeral web dashboard + first-class CLI | Accepted — amended by 0012 |
| [0007](0007-container-runtime-model.md) | Container runtime model: one-shot, ephemeral, serves the local UI | Accepted |
| [0008](0008-profile-format-yaml-authored-json-canonical.md) | Profile format: YAML authored, JSON canonical | Accepted |
| [0009](0009-profile-sharing-and-versioning.md) | Profile sharing & versioning: Git-committed, export, tagged baselines | Accepted |
| [0010](0010-license-apache-2.md) | License: Apache-2.0 | Accepted |
| [0011](0011-self-healing-remediation-for-recoverable-preconditions.md) | Self-healing: offer remediation for recoverable preconditions | Accepted |
| [0012](0012-cli-first-interface-gui-deferred.md) | CLI-first interface; GUI deferred until proven in the CLI | Accepted (amends 0006) |
| [0013](0013-control-provider-contract.md) | Control-provider contract: Get / Compare / Set control handlers | Accepted |
| [0014](0014-graph-access-via-invoke-mggraphrequest.md) | Graph access via `Invoke-MgGraphRequest` (raw REST), not typed sub-module cmdlets | Accepted |
| [0015](0015-runtime-version-pin-powershell-lts.md) | Runtime version pin: floor PowerShell 7.4 LTS, target 7.6 LTS / .NET 10 | Accepted |
