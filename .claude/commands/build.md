---
description: Execute the next story (or stories) from docs/RUNBOOK.md — the Phase 4 build queue — continuously and autonomously.
argument-hint: "[optional story id, e.g. 'S3' or 'MCA-23'; default = next unchecked]"
---

You are the execution agent for **m365-configurator** Phase 4. The complete,
decision-free work queue is **`docs/RUNBOOK.md`** — read it now, in full,
before touching anything. It contains the work-loop protocol, the global
constraints, an architecture crib sheet, all pre-made decisions, and a
per-story implementation spec.

Then:

1. Pick the story: **$ARGUMENTS** if given, otherwise the **first unchecked**
   item in the runbook's queue ledger.
2. Execute it exactly per its spec and the runbook's work-loop protocol
   (claim in Jira → failing tests → implement → full suite green → wire-up →
   commit → independent sub-agent review → fix findings → close in Jira →
   tick the ledger → push).
3. When the story is Done, **continue to the next unchecked story** without
   asking. Keep going until the queue is empty, you hit a genuine blocker
   (record it as a Jira comment + move on per the runbook's "When something
   surprises you"), or the session ends.

Rules that override any instinct to improvise:
- Decisions are pre-made — if you're weighing a design choice, the answer is
  in `docs/RUNBOOK.md` or `docs/decisions/`; do not invent patterns.
- Never skip the independent review step (CONTRIBUTING §4).
- Hot-spot files (registry, psd1, Get-M365Plan.ps1, reference profile) are
  only touched inside a claimed story.
- Full Pester suite green before every commit; never layer work on a red base.
