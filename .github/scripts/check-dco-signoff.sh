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

# Skip merge commits only when Git indicates an active merge in progress
merge_head="$(git rev-parse --git-path MERGE_HEAD 2>/dev/null || true)"
if [[ -n "${merge_head}" && -f "${merge_head}" ]]; then
  exit 0
fi

# Extract author identity from git
if ! author_ident="$(git var GIT_AUTHOR_IDENT 2>/dev/null)"; then
  echo "Error: Unable to determine git author identity from 'git var GIT_AUTHOR_IDENT'." >&2
  echo "Ensure 'user.name' and 'user.email' are configured in git." >&2
  exit 1
fi

# Author format from GIT_AUTHOR_IDENT: "Name <email> timestamp tz"
author_name="$(echo "${author_ident}" | sed -E 's/^(.*) <[^>]+>.*/\1/')"
author_email="$(echo "${author_ident}" | sed -E 's/^.* <([^>]+)>.*/\1/')"
if [[ -z "${author_name}" || -z "${author_email}" || "${author_email}" == "${author_ident}" ]]; then
  echo "Error: Failed to parse author name and email from git author ident: ${author_ident}" >&2
  exit 1
fi

# Skip [bot] git authors:
# Match if the author name has [bot] (e.g. dependabot[bot], github-actions[bot])
# or if the email is a GitHub bot noreply email (*[bot]@users.noreply.github.com)
if [[ "${author_name}" =~ \[[bB][oO][tT]\] ]] || [[ "${author_email}" =~ \[[bB][oO][tT]\]@users\.noreply\.github\.com$ ]]; then
  exit 0
fi

author="${author_name} <${author_email}>"
expected_signoff="Signed-off-by: ${author}"

# Determine comment character (respects core.commentChar, defaults to '#')
comment_char="$(git config --get core.commentChar 2>/dev/null || true)"
if [[ -z "${comment_char}" || "${comment_char}" == "auto" ]]; then
  comment_char="#"
fi

# Validate commit message content before the scissors cutoff line,
# ignoring comment lines and CRLF line endings.
# Uses a single awk process reading the file directly to avoid pipeline SIGPIPE issues.
if ! awk -v signoff="${expected_signoff}" -v cchar="${comment_char}" '
  BEGIN {
    found = 0
  }
  {
    sub(/\r$/, "")
    line = $0
    sub(/^[ \t]+/, "", line)

    # Check if line begins with comment_char
    if (length(line) >= length(cchar) && substr(line, 1, length(cchar)) == cchar) {
      rem = substr(line, length(cchar) + 1)
      sub(/^[ \t]+/, "", rem)
      # Check scissors marker in comment: e.g. "# ------------------------ >8 ------------------------"
      if (rem ~ /^-+.*(>8|8<).*-+/) {
        exit
      }
      next
    }

    # Check scissors marker without comment_char (commit.cleanup=scissors)
    if (line ~ /^-+.*(>8|8<).*-+/) {
      exit
    }

    if ($0 == signoff) {
      found = 1
    }
  }
  END {
    if (found == 1) {
      exit 0
    } else {
      exit 1
    }
  }
' "${COMMIT_MSG_FILE}"; then
  cat >&2 <<EOF
Error: Missing or mismatched DCO Signed-off-by trailer in commit message.

Expected:
  ${expected_signoff}

To fix this:
  use git commit -s and ensure git user.name/user.email match Signed-off-by.
EOF
  exit 1
fi
