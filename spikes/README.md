# Spikes

Time-boxed, throwaway investigations that produce **evidence for a decision** —
not shipping code. A spike answers a specific, risky question (usually one an ADR
depends on) with something runnable and reproducible, records the findings, and
then gets referenced from the decision it informed.

Spikes are intentionally separate from the eventual application code: they may
pull heavy dependencies, target runtimes we would not ship on, and cut corners a
production slice never would. Treat their output as **research artifacts**.

## Current spikes

| Spike | Question | Feeds |
| --- | --- | --- |
| [`03-microsoft365dsc-container-proof/`](03-microsoft365dsc-container-proof/) | Can Microsoft365DSC actually run as our engine on Linux + pwsh 7, and what lands on disk? (R1–R9) | [ADR-0002](../docs/decisions/0002-evaluate-microsoft365dsc-as-engine.md) · [research 03](../docs/research/03-microsoft365dsc.md) · OPEN-QUESTIONS Q7 |
