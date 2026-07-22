---
description: Catch up on m365-configurator across the repo, Jira (MCA), and Confluence (SD), reconcile them, and report where we left off + the next action.
argument-hint: "[optional focus, e.g. 'jira' or a topic]"
---

You are resuming work on **m365-configurator**. The owner keeps state in three
places that drift apart: this **repo**, **Jira**, and **Confluence**. Reconcile
all three and give a tight, decision-ready status. Do not rely on `CLAUDE.md`'s
cached status — regenerate it live.

Coordinates (do not ask the user for these):
- Atlassian Cloud ID: `b738554c-85e3-4c02-8140-fef01cb5fdb9` (`chomey.atlassian.net`)
- Jira project: `MCA` · Confluence space: `SD`
- Key Confluence pages: `1048577` (project home), `917517` (research index)
- Default/working branch: `main`

Optional focus from the user: **$ARGUMENTS** — if given, weight the report toward
it, but still run every source check below.

Do these, preferring parallel tool calls where independent:

1. **Repo.** Run `bash scripts/repo-status.sh`. Note the current branch, any
   uncommitted changes, and — importantly — any branch with commits **not yet
   merged into the default branch** (e.g. an unmerged research/feature branch).

2. **Jira (MCA).** With `mcp__Atlassian_Rovo__searchJiraIssuesUsingJql` and the
   Cloud ID, query `project = MCA ORDER BY updated DESC` (fields: summary, status,
   issuetype, priority, updated, parent). Group by status; call out anything
   In Progress or blocked. If the project is empty, say so explicitly — that is a
   meaningful signal about which phase we're in.

3. **Confluence (SD).** With `mcp__Atlassian_Rovo__searchConfluenceUsingCql`,
   query `space = SD AND type = page ORDER BY lastmodified DESC`. Read the project
   home and research index pages if their status may have changed. Note their
   claimed status.

4. **Reconcile & report.** Produce a concise brief with these sections:
   - **Where we are** — the current roadmap phase, in one or two lines.
   - **State by source** — repo / Jira / Confluence, one line each.
   - **Drift & loose ends** — anywhere the three disagree (e.g. Confluence says a
     deliverable is "done" but the commits aren't merged into the default branch;
     docs that exist in one place but not another; Jira empty when planning was
     expected). Be specific and cite branch/page/issue.
   - **Needs the owner** — open decisions or checkpoints blocking progress (pull
     from `docs/OPEN-QUESTIONS.md` and any Proposed ADRs).
   - **Recommended next action** — the single most useful thing to do next, and
     offer to do it. If it would touch a branch other than the current designated
     one, or requires an owner decision, ask first (use `AskUserQuestion` for
     genuine either/or choices) rather than acting unilaterally.

Keep it scannable. Lead with the recommended next action if the situation is
simple; lead with drift if there's a real inconsistency to resolve.
