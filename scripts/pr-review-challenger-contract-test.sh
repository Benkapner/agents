#!/usr/bin/env bash
# pr-review-challenger-contract-test.sh — Verify challenger result guidance.
#
# Run from the repo root:
#   bash scripts/pr-review-challenger-contract-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SKILL="${REPO_ROOT}/skills/pr-review/SKILL.md"
FAILURES=0

CHALLENGER_SECTION="$(awk '
  /^#### 6d\. Challenger pass/ { found = 1 }
  found && /^#### 6e\. / { exit }
  found { print }
' "${SKILL}")"

if [[ -z "${CHALLENGER_SECTION}" ]]; then
  echo "FAIL: could not extract the '#### 6d. Challenger pass' section from ${SKILL}"
  exit 1
fi

# Normalize to a single space-separated line so assertions survive markdown
# re-wrapping.
CHALLENGER_SECTION="$(printf '%s\n' "${CHALLENGER_SECTION}" | tr '\n' ' ' | tr -s ' ')"

assert_contains() {
  local name="$1" expected="$2"
  if grep -qF -- "${expected}" <<<"${CHALLENGER_SECTION}"; then
    echo "PASS: ${name}"
  else
    echo "FAIL: ${name} — missing '${expected}' in challenger guidance"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_not_contains() {
  local name="$1" unexpected="$2"
  if grep -qF -- "${unexpected}" <<<"${CHALLENGER_SECTION}"; then
    echo "FAIL: ${name} — found forbidden '${unexpected}' in challenger guidance"
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS: ${name}"
  fi
}

assert_contains "structured response requires both arrays" \
  "Require a parsed object with both arrays."
assert_contains "full removal requires complete evidence-backed accounting" \
  "has one distinct, evidence-backed"
assert_contains "full removal requires one-to-one correspondence" \
  "matched one-to-one using"
assert_contains "full removal records match on named identity fields" \
  '`original_category` + `original_file`'
assert_contains "full removal records corroborate with the description" \
  '`original_description` corroborates'
assert_contains "full removal reasons cite specific evidence" \
  '`removal_reason` must cite evidence.'
assert_contains "full removal is gated on empty adjudication" \
  'non-empty challenged subset with empty `adjudicated_findings`'
assert_contains "full removal replaces the challenged subset" \
  'Replace the challenged subset with the empty array'
assert_contains "successful full removal restores withheld findings" \
  'the empty array, then re-append withheld findings.'

assert_contains "incomplete empty accounting is a failure" \
  "Missing, incomplete, duplicated, unmatched, or evidence-free accounting is a failure."
assert_not_contains "empty adjudication is no longer an unconditional failure" \
  "treat this as a challenger failure"
assert_contains "genuine challenger failures use fallback" \
  "has a timeout or tool error, returns malformed or empty"
assert_contains "invalid empty accounting uses fallback" \
  "invalid empty-adjudication accounting"
assert_contains "failure fallback restores the pre-challenger set" \
  "fall back to the pre-challenger merged finding set"

assert_contains "time-budget skip keeps the merged set" \
  "skip the challenger: keep the merged finding set from"
assert_contains "time-budget skip records a low finding" \
  'record the item-4 `low` finding with the reason `time budget:'

assert_contains "prompt-size guard withholds low and info findings" \
  'tokens, withhold `low` and `info` findings from the challenger'
assert_contains "prompt-size guard restores withheld findings" \
  "input and re-append them, unchallenged, after step 3."
assert_contains "retained findings replace the challenged subset" \
  'Otherwise replace the challenged subset with `adjudicated_findings`,'
assert_contains "retained findings restore withheld findings" \
  "then re-append withheld findings."
assert_contains "removed findings are logged but excluded" \
  'Log `removed_findings`, but exclude them from the final review.'

assert_contains "challenger failure finding is low severity" \
  '"severity": "low"'
assert_contains "challenger failure uses sub-agent-failure category" \
  '"category": "sub-agent-failure"'
assert_contains "challenger failure preserves the original findings" \
  'Using pre-challenger finding set.'
assert_contains "challenger failure is non-actionable" \
  '"actionable": false'

if [[ ${FAILURES} -gt 0 ]]; then
  echo "${FAILURES} test(s) failed"
  exit 1
fi

echo "All PR review challenger contract tests passed"
