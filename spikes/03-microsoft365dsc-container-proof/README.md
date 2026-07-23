# Spike: Microsoft365DSC container proof (R1–R9)

A reproducible, containerized proof that turns the **desk research** in
[`docs/research/03-microsoft365dsc.md`](../../docs/research/03-microsoft365dsc.md)
into **empirical evidence**, so the [ADR-0002](../../docs/decisions/0002-evaluate-microsoft365dsc-as-engine.md)
accept/reject decision rests on what actually happens — not on documentation alone.

> **Why this exists.** Research Track 03 concluded that Microsoft365DSC is very
> likely **not viable as our primary engine** on Linux + PowerShell 7 (the LCM is
> Windows-only; no device-code/interactive apply; MOF stores credentials). The
> project owner chose to **run this proof before ratifying** ADR-0002. This spike
> is the test harness for that decision. It is a throwaway investigation, **not**
> the shipping tool.

## What it checks

Each probe maps to a risk (`Rn`) from the research doc's §10 test matrix:

| # | Question | Where it runs |
| --- | --- | --- |
| R1 | Does `Microsoft365DSC` install + import, and an export run, on Linux/pwsh7? | Linux |
| R2 | Is there any *apply* path on Linux (`Invoke-DscResource`) vs the Windows LCM? | Linux + Windows |
| R3 | On-disk footprint vs our ~5-module custom slice (NFR-3) | Linux |
| R4 | Does the Graph dependency stay at `Microsoft.Graph.Authentication` only? | Linux |
| R5 | Can the LCM re-check with a cert that lives only in an ephemeral store? | Windows (guided) |
| R6 | Does a compiled MOF embed secrets under app-only auth? (NFR-1) | Windows |
| R7 | Does the offline delta report show false positives on identical exports? | Linux |
| R8 | Windows image size / licensing if the fallback is chosen | Windows |
| R9 | Pin & re-verify against the **exact** shipped release | both |

## Layout

```
spikes/03-microsoft365dsc-container-proof/
├─ README.md               this file
├─ Dockerfile.linux        Linux + pwsh 7 image (target runtime)
├─ Dockerfile.windows      Windows Server Core image (fallback host)
├─ run.sh                  build + run the Linux probes, write ./results
├─ probes/
│  ├─ _Common.ps1          shared helpers + secret-safe result writer
│  ├─ Invoke-LinuxProbes.ps1    R1/R2/R3/R4/R7 (+ opt-in export)
│  └─ Invoke-WindowsProbes.ps1  R2/R5/R6/R8
└─ results/
   ├─ RESULTS-template.md  human-curated verdict that feeds ADR-0002
   └─ (generated results-*.json / results-*.md are git-ignored)
```

## Run it

### Linux (the important one — R1/R3/R4 need no tenant)

```bash
cd spikes/03-microsoft365dsc-container-proof
./run.sh 1.26.0        # pin the exact Microsoft365DSC release under test (R9)
# results land in ./results/results-<timestamp>.{json,md}
```

`run.sh` just wraps:

```bash
docker build -f Dockerfile.linux --build-arg M365DSC_VERSION=1.26.0 -t m365dsc-proof:linux .
docker run --rm -v "$(pwd)/results:/proof-results" m365dsc-proof:linux
```

The build's install step is **resilient** — if `Install-Module`/`Import-Module`
fails on Linux (the outcome issue #3144 predicts), the image still builds and the
**R1 probe records the failure** as the finding, so you always get a results file
to attach to the decision.

### Windows (fallback path — R2 apply / R5 / R6 / R8)

Requires a **Windows container host** (won't build on a Linux Docker engine):

```powershell
cd spikes\03-microsoft365dsc-container-proof
docker build -f Dockerfile.windows --build-arg M365DSC_VERSION=1.26.0 -t m365dsc-proof:win .
docker run --rm -v ${PWD}\results:C:\proof-results m365dsc-proof:win
docker images m365dsc-proof:win     # record the image size for R8
```

## Optional: exercising export / apply (needs auth)

The default Linux run contacts **no tenant**. To test a live single-component
export (adds R1x, and lets R6 inspect a real MOF), supply auth via environment
variables and pass `-RunExport`. Prefer a **throwaway test tenant** and an
**app registration with a runtime-injected certificate**:

```bash
docker run --rm \
  -e M365_TENANTID="contoso.onmicrosoft.com" \
  -e M365_APPID="<app-guid>" \
  -e M365_CERT_THUMBPRINT="<thumbprint-of-a-cert-in-the-container-store>" \
  -v "$(pwd)/results:/proof-results" \
  m365dsc-proof:linux -RunExport
```

- **R2 (Linux apply attempt):** after an export works, try
  `Invoke-DscResource -Method Set` against one resource (e.g.
  `AADAuthorizationPolicy`) and record whether it runs headless or errors on the
  missing LCM. This is a guided manual step — capture the result in
  `results/RESULTS-*.md`.
- **R5 (cert re-check):** place the app cert only in a tmpfs-backed store, apply
  with `ApplyAndMonitor`, remove the store, and observe whether the 15-min
  consistency check still succeeds.

## Security notes (the tenets still apply, even in a spike)

- The probes **never write credential values** to results — the MOF scan (R6)
  records only *whether* secret-shaped content is present and its classification,
  never the value.
- Auth material is read from environment variables and never echoed. Use a
  **test tenant**. Treat any produced MOF/export as secret-bearing until R6 proves
  otherwise, and delete `results/` when done.
- Nothing here should ever run against a production tenant with a persisted cert.

## Feeding the decision back

Fill in [`results/RESULTS-template.md`](results/RESULTS-template.md) with the
observed verdicts, then:

1. Note in [`docs/OPEN-QUESTIONS.md`](../../docs/OPEN-QUESTIONS.md) Q7 whether the
   proof **confirms or refutes** the research recommendation.
2. Update [ADR-0002](../../docs/decisions/0002-evaluate-microsoft365dsc-as-engine.md)
   status (Accepted-as-primary / Rejected-as-primary / Accepted-with-Windows-container)
   with the evidence attached — the owner's call.
