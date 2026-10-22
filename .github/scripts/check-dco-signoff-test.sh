#!/usr/bin/env bash
# check-dco-signoff-test.sh — Tests for check-dco-signoff.sh
#
# Run from the repo root: bash .github/scripts/check-dco-signoff-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="${SCRIPT_DIR}/check-dco-signoff.sh"

FAILURES=0
TESTS=0

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

assert_pass() {
  local test_name="$1"
  shift
  TESTS=$((TESTS + 1))
  if "$@" >/dev/null 2>&1; then
    echo "PASS: ${test_name}"
  else
    echo "FAIL: ${test_name} — expected exit 0"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_fail() {
  local test_name="$1"
  local expected_err="${2:-}"
  shift 2
  TESTS=$((TESTS + 1))
  local output
  output="$("$@" 2>&1 || true)"
  if "$@" >/dev/null 2>&1; then
    echo "FAIL: ${test_name} — expected non-zero exit code"
    FAILURES=$((FAILURES + 1))
  elif [[ -n "${expected_err}" ]] && ! echo "${output}" | grep -Fiq "${expected_err}"; then
    echo "FAIL: ${test_name} — missing expected error string: '${expected_err}'"
    echo "Actual output:"
    echo "${output}"
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS: ${test_name}"
  fi
}

# --- Setup test fixture repo ---
FIXTURE_REPO="${TMPDIR}/repo"
mkdir -p "${FIXTURE_REPO}"
git -C "${FIXTURE_REPO}" init -q
git -C "${FIXTURE_REPO}" config user.name "Test Author"
git -C "${FIXTURE_REPO}" config user.email "author@example.com"

# 1. Valid commit message with matching signoff
MSG_VALID="${TMPDIR}/msg_valid.txt"
cat > "${MSG_VALID}" <<EOF
feat(test): add new feature

Detailed explanation of the change.

Signed-off-by: Test Author <author@example.com>
EOF

assert_pass "valid sign-off matching author" \
  env -C "${FIXTURE_REPO}" "${CHECK_SCRIPT}" "${MSG_VALID}"

# 2. Valid commit message with git comments and CRLF
MSG_COMMENTS="${TMPDIR}/msg_comments.txt"
printf "feat(test): add new feature\r\n\r\n# Please enter the commit message\r\nSigned-off-by: Test Author <author@example.com>\r\n# Comments ignored\r\n" > "${MSG_COMMENTS}"

assert_pass "valid sign-off with CRLF and comments" \
  env -C "${FIXTURE_REPO}" "${CHECK_SCRIPT}" "${MSG_COMMENTS}"

# 3. Valid sign-off with multiple co-signers
MSG_MULTI="${TMPDIR}/msg_multi.txt"
cat > "${MSG_MULTI}" <<EOF
chore(deps): update dependency

Signed-off-by: Another Person <other@example.com>
Signed-off-by: Test Author <author@example.com>
EOF

assert_pass "valid sign-off among multiple trailers" \
  env -C "${FIXTURE_REPO}" "${CHECK_SCRIPT}" "${MSG_MULTI}"

# 4. Missing sign-off entirely
MSG_MISSING="${TMPDIR}/msg_missing.txt"
cat > "${MSG_MISSING}" <<EOF
fix(bug): resolve issue without signoff

No sign-off trailer here.
EOF

assert_fail "missing sign-off fails with actionable guidance" \
  "use git commit -s and ensure git user.name/user.email match Signed-off-by" \
  env -C "${FIXTURE_REPO}" "${CHECK_SCRIPT}" "${MSG_MISSING}"

# 5. Mismatched email in sign-off
MSG_MISMATCH_EMAIL="${TMPDIR}/msg_mismatch_email.txt"
cat > "${MSG_MISMATCH_EMAIL}" <<EOF
docs(readme): update guide

Signed-off-by: Test Author <wrong-email@example.com>
EOF

assert_fail "mismatched email fails" \
  "Signed-off-by: Test Author <author@example.com>" \
  env -C "${FIXTURE_REPO}" "${CHECK_SCRIPT}" "${MSG_MISMATCH_EMAIL}"

# 6. Mismatched name in sign-off
MSG_MISMATCH_NAME="${TMPDIR}/msg_mismatch_name.txt"
cat > "${MSG_MISMATCH_NAME}" <<EOF
docs(readme): update guide

Signed-off-by: Different Name <author@example.com>
EOF

assert_fail "mismatched name fails" \
  "Signed-off-by: Test Author <author@example.com>" \
  env -C "${FIXTURE_REPO}" "${CHECK_SCRIPT}" "${MSG_MISMATCH_NAME}"

# 7. Commented-out sign-off
MSG_COMMENTED="${TMPDIR}/msg_commented.txt"
cat > "${MSG_COMMENTED}" <<EOF
refactor(core): clean up functions

# Signed-off-by: Test Author <author@example.com>
EOF

assert_fail "commented-out sign-off fails" \
  "Missing or mismatched DCO Signed-off-by trailer" \
  env -C "${FIXTURE_REPO}" "${CHECK_SCRIPT}" "${MSG_COMMENTED}"

# 8. Bot author skipped (dependabot[bot])
assert_pass "bot author skipped without sign-off" \
  env -C "${FIXTURE_REPO}" \
  GIT_AUTHOR_NAME="dependabot[bot]" \
  GIT_AUTHOR_EMAIL="49699333+dependabot[bot]@users.noreply.github.com" \
  "${CHECK_SCRIPT}" "${MSG_MISSING}"

# 9. Bot author with [BOT] in name skipped
assert_pass "bot author uppercase [BOT] skipped" \
  env -C "${FIXTURE_REPO}" \
  GIT_AUTHOR_NAME="ci-bot[BOT]" \
  GIT_AUTHOR_EMAIL="ci@example.com" \
  "${CHECK_SCRIPT}" "${MSG_MISSING}"

# 10. Merge commit with MERGE_HEAD skipped
MERGE_REPO="${TMPDIR}/merge_repo"
mkdir -p "${MERGE_REPO}"
git -C "${MERGE_REPO}" init -q
git -C "${MERGE_REPO}" config user.name "Test Author"
git -C "${MERGE_REPO}" config user.email "author@example.com"
touch "${MERGE_REPO}/.git/MERGE_HEAD"

assert_pass "merge commit with MERGE_HEAD skipped without sign-off" \
  env -C "${MERGE_REPO}" "${CHECK_SCRIPT}" "${MSG_MISSING}"

# 11. Merge commit title skipped
MSG_MERGE="${TMPDIR}/msg_merge.txt"
cat > "${MSG_MERGE}" <<EOF
Merge branch 'feature-branch' into main

Detailed merge explanation.
EOF

assert_pass "commit message starting with Merge skipped without sign-off" \
  env -C "${FIXTURE_REPO}" "${CHECK_SCRIPT}" "${MSG_MERGE}"

# 12. Missing argument fails
assert_fail "missing argument fails" \
  "Commit message file argument missing" \
  env -C "${FIXTURE_REPO}" "${CHECK_SCRIPT}"

# 13. Non-existent file fails
assert_fail "non-existent file fails" \
  "not found" \
  env -C "${FIXTURE_REPO}" "${CHECK_SCRIPT}" "${TMPDIR}/does_not_exist.txt"

# --- Summary ---
echo ""
echo "Ran ${TESTS} tests, ${FAILURES} failures"
if [[ "${FAILURES}" -gt 0 ]]; then
  exit 1
fi
