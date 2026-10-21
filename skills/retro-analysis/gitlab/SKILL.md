---
name: retro-analysis-gitlab
description: >
  GitLab-specific CLI recipes for the retro-analysis skill. Use curl
  against the GitLab REST API to trace pipelines, read job logs,
  download artifacts, and search for duplicate issues on GitLab.
---

# Retro Analysis — GitLab CLI Recipes

## Environment setup

```bash
GITLAB_HOST=$(echo "${ORIGINATING_URL}" | sed -E 's|^https://([^/]+)/.*|\1|')
REPO_ENCODED=$(printf '%s' "${REPO_FULL_NAME}" | jq -sRr @uri)
ORG=$(echo "${REPO_FULL_NAME}" | cut -d/ -f1)
DISPATCH_REPO="${ORG}/.fullsend"
DISPATCH_REPO_ENCODED=$(printf '%s' "${DISPATCH_REPO}" | jq -sRr @uri)
```

All API calls use:
```bash
curl --fail --silent --show-error \
  --connect-timeout 10 --max-time 30 \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://${GITLAB_HOST}/api/v4${ENDPOINT}"
```

## Pipeline tracing

### List recent pipelines in the dispatch project

Agent workflows run in the dispatch project (`${DISPATCH_REPO}`), not the
source project.

```bash
curl --fail --silent --show-error \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://${GITLAB_HOST}/api/v4/projects/${DISPATCH_REPO_ENCODED}/pipelines?per_page=20" \
  | jq '.[] | {id: .id, status: .status, ref: .ref, created_at: .created_at}'
```

### List jobs in a pipeline

```bash
curl --fail --silent --show-error \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://${GITLAB_HOST}/api/v4/projects/${DISPATCH_REPO_ENCODED}/pipelines/<PIPELINE_ID>/jobs" \
  | jq '.[] | {id: .id, name: .name, status: .status, stage: .stage}'
```

## Reading job logs

```bash
curl --fail --silent --show-error \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://${GITLAB_HOST}/api/v4/projects/${DISPATCH_REPO_ENCODED}/jobs/<JOB_ID>/trace" \
  | grep -i "error\|fail\|exit code"
```

## Downloading artifacts

```bash
curl --fail --silent --show-error \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  --output artifacts.zip \
  "https://${GITLAB_HOST}/api/v4/projects/${DISPATCH_REPO_ENCODED}/jobs/<JOB_ID>/artifacts"
```

## Duplicate search

Search the target project — match each proposal's `target_repo`. Run both
passes for every proposal — fix-keyed and root-cause-keyed (see the
retro-analysis skill's "Before proposing" section).

```bash
TARGET_ENCODED=$(printf '%s' "<target_repo>" | jq -sRr @uri)

# Fix-keyed: keywords drawn from the proposed change, open issues
curl --fail --silent --show-error \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://${GITLAB_HOST}/api/v4/projects/${TARGET_ENCODED}/issues?search=<fix+keywords>&state=opened&per_page=20" \
  | jq '.[] | {iid: .iid, title: .title, state: .state, web_url: .web_url, description: .description}'

# Root-cause-keyed: search by the affected subsystem/component instead of the fix
curl --fail --silent --show-error \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://${GITLAB_HOST}/api/v4/projects/${TARGET_ENCODED}/issues?search=<subsystem+or+root-cause+keywords>&state=opened&per_page=20" \
  | jq '.[] | {iid: .iid, title: .title, state: .state, web_url: .web_url, description: .description}'

# Include closed issues to apply the close-reason rules (duplicate / not
# planned / completed). state carries the state; closed_at is required by the
# 30-day not-planned rule; labels often carry the reason on GitLab.
curl --fail --silent --show-error \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://${GITLAB_HOST}/api/v4/projects/${TARGET_ENCODED}/issues?search=<keywords>&per_page=20" \
  | jq '.[] | {iid: .iid, title: .title, state: .state, closed_at: .closed_at, labels: .labels, web_url: .web_url, description: .description}'

# Follow a duplicate chain to its canonical: read the duplicate candidate's own
# description and notes for the "duplicate of #X" reference, then fetch #X
# directly. (The duplicate points to the canonical, not the reverse — so a
# search mentioning the candidate's number does not find its canonical.)
curl --fail --silent --show-error \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://${GITLAB_HOST}/api/v4/projects/${TARGET_ENCODED}/issues/<candidate-iid>" \
  | jq '{iid: .iid, title: .title, state: .state, description: .description}'
curl --fail --silent --show-error \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://${GITLAB_HOST}/api/v4/projects/${TARGET_ENCODED}/issues/<candidate-iid>/notes?per_page=50" \
  | jq '.[] | {body: .body}'
# Then fetch the referenced canonical directly (follow further links if it is
# itself a duplicate).
```

Use multiple searches with different keyword combinations if the first returns no results — the same idea can be filed under different titles.
