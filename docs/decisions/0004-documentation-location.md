# 0004. Documentation lives in repo `docs/` + Confluence "Software Development" (SD)

- **Status:** Accepted
- **Date:** 2026-07-22
- **Related:** OPEN-QUESTIONS Q11

## Context

Two Confluence spaces exist: the personal **Moose** space and the team
**Software Development** (`SD`) space. Research/design/planning docs need a shared,
collaborative home; the repo also carries `docs/` for versioned, code-adjacent docs.

## Decision

- **Repo `docs/` is the source of truth** for anything code-adjacent (vision,
  requirements, ADRs, research).
- **Mirror/curate** the research → design → planning narrative into a page tree
  under the Confluence **SD** space for collaboration and visibility, linking back
  to the repo.
- **Jira project `MCA`** tracks work items, referenced by FR/NFR IDs.

## Consequences

- Some duplication between repo and Confluence; mitigate by treating the repo as
  the source of truth and Confluence as the curated collaborative view.

## Alternatives considered

- **Personal (Moose) space** — less collaborative; rejected.
