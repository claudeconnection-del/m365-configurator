#!/usr/bin/env bash
#
# repo-status.sh — deterministic snapshot of this repo's git state for the
# "resume" workflow. Read-only: fetches, then reports. Never mutates branches.
#
# Output is grouped and aligned for fast visual inspection (design tenet #8).
#
set -euo pipefail

cd "$(dirname "$0")/.."

DEFAULT_BRANCH="main"

hr() { printf '%s\n' "----------------------------------------------------------------"; }

echo "m365-configurator — repo status  ($(date -u '+%Y-%m-%d %H:%M UTC'))"
hr

# Best-effort refresh of remote-tracking refs; stay quiet and non-fatal offline.
git fetch --all --prune --quiet 2>/dev/null || echo "(offline — remote refs may be stale)"

CURRENT="$(git rev-parse --abbrev-ref HEAD)"
echo "Current branch : ${CURRENT}"
echo "Default branch : ${DEFAULT_BRANCH}"
echo "HEAD commit    : $(git log -1 --oneline)"
hr

echo "Working tree:"
if [ -n "$(git status --porcelain)" ]; then
  git status --short
else
  echo "  clean"
fi
hr

echo "Local branches vs their upstream:"
git for-each-ref --format='  %(refname:short)  ->  %(upstream:short) %(upstream:track)' refs/heads
hr

echo "Branches NOT fully merged into ${DEFAULT_BRANCH} (unmerged work):"
found_unmerged=0
if git rev-parse --verify --quiet "origin/${DEFAULT_BRANCH}" >/dev/null; then
  base="origin/${DEFAULT_BRANCH}"
else
  base="${DEFAULT_BRANCH}"
fi
for ref in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin | grep -v -- '->'); do
  [ "$ref" = "$base" ] && continue
  ahead="$(git rev-list --count "${base}..${ref}" 2>/dev/null || echo 0)"
  if [ "$ahead" -gt 0 ]; then
    found_unmerged=1
    printf '  %-55s %s commit(s) ahead\n' "$ref" "$ahead"
    git log --oneline "${base}..${ref}" | sed 's/^/      /'
  fi
done
[ "$found_unmerged" -eq 0 ] && echo "  (none — everything is merged into the default branch)"
hr

echo "Done. Next: check Jira (project MCA) and Confluence (space SD) — see .claude/commands/resume.md"
