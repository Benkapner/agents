## Unreleased

### Breaking

- **Risk score gates review approval** — when risk assessment is enabled
  (`REVIEW_RISK_ASSESSMENT_ENABLED="true"`), PRs with a risk score at or
  above the configured threshold (`REVIEW_RISK_VERDICT_THRESHOLD`, default
  `4`) can no longer be auto-approved. The review verdict is downgraded to
  `comment` with a blockquote notice, requiring a human reviewer. A missing
  or degraded risk assessment also prevents approval (fail-closed).
  Configure the threshold in your harness `env` blocks.
  \
  **BREAKING CHANGE**: `REVIEW_RISK_ASSESSMENT_ENABLED` defaults to `"true"`
  on the stock GitHub harness. Consumers with risk assessment enabled will
  see auto-approved reviews become `comment` reviews when the risk score
  reaches or exceeds the threshold. To keep informational-only risk scoring,
  set   `REVIEW_RISK_VERDICT_THRESHOLD: "6"` (supported opt-out) or
  disable the feature with `REVIEW_RISK_ASSESSMENT_ENABLED: "false"`.
