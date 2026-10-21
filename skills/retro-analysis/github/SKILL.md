---
name: retro-analysis-github
description: >
  GitHub-specific CLI recipes for the retro-analysis skill. Use gh CLI
  to trace workflow runs, read logs, download artifacts, and search for
  duplicate issues on GitHub.
---

# Retro Analysis — GitHub CLI Recipes

## Workflow tracing

### From an issue

```bash
# Find triage dispatches (triggered by /fs-triage or label events)
gh run list --repo "$REPO_FULL_NAME" --workflow=fullsend.yaml \
  --json databaseId,status,conclusion,event,createdAt \
  -q '.[] | select(.event == "issue_comment" or .event == "issues")'
```

```bash
# Find the corresponding agent runs in the dispatch repo
gh run list --repo "$DISPATCH_REPO" --workflow=triage.yml --limit 10 \
  --json databaseId,status,conclusion,createdAt
```

```bash
# If the issue reached ready-to-code, find code dispatches
gh run list --repo "$DISPATCH_REPO" --workflow=code.yml --limit 10 \
  --json databaseId,status,conclusion,createdAt
```

### From a PR

```bash
# Find review dispatches
gh run list --repo "$DISPATCH_REPO" --workflow=review.yml --limit 10 \
  --json databaseId,status,conclusion,createdAt
```

```bash
# Find fix dispatches (if review requested changes)
gh run list --repo "$DISPATCH_REPO" --workflow=fix.yml --limit 10 \
  --json databaseId,status,conclusion,createdAt
```

## Reading agent logs and artifacts

```bash
# View job outcomes
gh run view <RUN_ID> --repo "$DISPATCH_REPO" --json jobs \
  -q '.jobs[] | "\(.name) \(.status)/\(.conclusion)"'

# Search logs for errors
gh run view <RUN_ID> --repo "$DISPATCH_REPO" --log 2>&1 \
  | grep -i "error\|fail\|exit code"

# Download session artifacts (JSONL traces)
gh run download <RUN_ID> --repo "$DISPATCH_REPO"
```

## Discovering the agents repo

```bash
# From an agent workflow run log, extract the agents repo
gh run view <RUN_ID> --repo "$DISPATCH_REPO" --log 2>&1 \
  | grep -oP 'Fetching agent \S+ from \K[^@]+' \
  | head -1
```

## Duplicate search

Run both passes for every proposal — fix-keyed and root-cause-keyed (see the
retro-analysis skill's "Before proposing" section).

```bash
# Fix-keyed: broad keyword search across title and body, open issues
gh api \
  "search/issues?q=<fix+keywords>+repo:<target_repo>+is:issue+is:open&per_page=20" \
  --jq '.items[] | {number: .number, title: .title, url: .html_url, body: .body}'

# Root-cause-keyed: search by the affected subsystem/component instead of the fix
gh api \
  "search/issues?q=<subsystem+or+root-cause+keywords>+repo:<target_repo>+is:issue+is:open&per_page=20" \
  --jq '.items[] | {number: .number, title: .title, url: .html_url, body: .body}'

# Include closed issues to apply the close-reason rules (duplicate / not
# planned / completed). state_reason carries the close reason; closed_at is
# required by the 30-day not-planned rule.
gh api \
  "search/issues?q=<keywords>+repo:<target_repo>+is:issue&per_page=20" \
  --jq '.items[] | {number: .number, title: .title, state: .state, state_reason: .state_reason, closed_at: .closed_at, url: .html_url, body: .body}'

# Follow a duplicate chain to its canonical: read the duplicate candidate's own
# body and comments for the "duplicate of #X" reference, then fetch #X directly.
# (The duplicate points to the canonical, not the reverse — so searching for
# issues that mention the candidate's number does not find its canonical.)
gh issue view <candidate-number> --repo <target_repo> \
  --json number,title,state,stateReason,body,comments \
  --jq '{number, title, state, stateReason, body, comments: [.comments[].body]}'
# Then fetch the referenced canonical directly (follow further links if it is
# itself a duplicate):
gh issue view <canonical-number> --repo <target_repo> \
  --json number,title,state,stateReason,url

# Reverse-reference search (distinct use): find issues/PRs that mention a
# candidate, e.g. a later issue that supersedes it.
gh api \
  "search/issues?q=<candidate-number>+repo:<target_repo>+is:issue&per_page=20" \
  --jq '.items[] | {number: .number, title: .title, state: .state, url: .html_url, body: .body}'
```

Use multiple searches with different keyword combinations if the first returns no results — the same idea can be filed under different titles.
