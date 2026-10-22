#!/usr/bin/env bash
# check-dco-signoff.sh — Validate DCO sign-off in commit messages.
#
# Ensures that commit messages contain a Signed-off-by trailer matching
# the git author identity ('git var GIT_AUTHOR_IDENT') for human commits.
# Skips merge commits and [bot] authors.

set -euo pipefail

COMMIT_MSG_FILE="${1:-}"

if [[ -z "${COMMIT_MSG_FILE}" ]]; then
  echo "Error: Commit message file argument missing." >&2
  echo "Usage: $0 <commit-msg-file>" >&2
  exit 1
fi

if [[ ! -f "${COMMIT_MSG_FILE}" ]]; then
  echo "Error: Commit message file '${COMMIT_MSG_FILE}' not found." >&2
  exit 1
fi

# Skip merge commits:
# 1. Active git merge in progress (MERGE_HEAD exists)
merge_head="$(git rev-parse --git-path MERGE_HEAD 2>/dev/null || true)"
if [[ -n "${merge_head}" && -f "${merge_head}" ]]; then
  exit 0
fi

# 2. First non-comment line starts with "Merge "
first_line="$(grep -v '^[[:space:]]*#' "${COMMIT_MSG_FILE}" | head -n 1 || true)"
if [[ "${first_line}" =~ ^Merge[[:space:]] ]]; then
  exit 0
fi

# Extract author identity from git
if ! author_ident="$(git var GIT_AUTHOR_IDENT 2>/dev/null)"; then
  echo "Error: Unable to determine git author identity from 'git var GIT_AUTHOR_IDENT'." >&2
  echo "Ensure 'user.name' and 'user.email' are configured in git." >&2
  exit 1
fi

# Author format from GIT_AUTHOR_IDENT: "Name <email> timestamp tz"
author="$(echo "${author_ident}" | sed -E 's/^(.* <[^>]+>).*/\1/')"
if [[ -z "${author}" || ( "${author}" == "${author_ident}" && "${author_ident}" != *">"* ) ]]; then
  echo "Error: Failed to parse author name and email from git author ident: ${author_ident}" >&2
  exit 1
fi

# Skip [bot] git authors (e.g., dependabot[bot], github-actions[bot])
if [[ "${author}" =~ \[[bB][oO][tT]\] ]]; then
  exit 0
fi

expected_signoff="Signed-off-by: ${author}"

# Check for matching Signed-off-by trailer (excluding comments)
if ! sed -e 's/\r$//' "${COMMIT_MSG_FILE}" | grep -v '^[[:space:]]*#' | grep -Fxq "${expected_signoff}"; then
  cat >&2 <<EOF
Error: Missing or mismatched DCO Signed-off-by trailer in commit message.

Expected:
  ${expected_signoff}

To fix this:
  use git commit -s and ensure git user.name/user.email match Signed-off-by.
EOF
  exit 1
fi
