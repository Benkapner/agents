Feature: Code applier branch handling

  The code applier must land pushes inside the dispatched issue's
  agent/<issue>-* branch namespace no matter which branch the sandbox
  leaves checked out, and must leave other issues' branches untouched.
  These scenarios drive real code runs through the post-scripts against
  live GitHub, so the branch guarantees are asserted on the scripts as
  shipped rather than on unit-level copies of their logic.

  The scenarios are gated behind the applier-branch-namespace capability
  (declared via BEHAVIOUR_CAPABILITIES in the Makefile) because they
  assert the post-code branch-namespace enforcement in this repo.

  The fix applier's refuse-to-push-on-branch-mismatch counterpart cannot
  be expressed here yet: the fix stage's only dispatch route is a
  changes_requested review submitted by the org review bot, which the
  behaviour suite cannot produce (suite-posted comments are bot-authored
  and bot comments are dropped by the dispatch gates). That path stays
  covered by script-level tests in this repo until a suite-reachable fix
  trigger exists.

  The decoy branch uses issue number 990000099 — far above any issue
  number a pool repo will ever reach — so the anchored
  agent/<issue>-.* head assertion can never match the decoy itself.

  A review trigger of "false" keeps the code run's pull request, which
  is labeled ready-for-review, from starting a review that would run the
  code fixture.

  Background:
    Given the enrolled test repository

  @requires:capability:applier-branch-namespace
  Scenario: Code run is renamed into the issue namespace and other branches are untouched
    Given the repository agents are configured with:
      """
      review:
        trigger: "false"
      """
    And an open pull request on branch "agent/990000099-decoy"
    And the tip of branch "agent/990000099-decoy" is recorded
    And an issue
    And a dummy agent that would:
      | description            | op              | args                                                     |
      | Check out decoy branch | checkout_branch | agent/990000099-decoy                                    |
      | Emit code JSON         | write_fixture   | output/agent-result.json, fixtures/code/implemented.json |
    When the issue is labeled "ready-to-code"
    Then the harness "code" workflow completes successfully
    And the agent will succeed to Check out decoy branch
    And the pull request head branch matches "agent/<issue>-.*"
    And branch "agent/990000099-decoy" is unchanged

  @requires:capability:applier-branch-namespace
  Scenario: Conforming branch is pushed without rename
    Given the repository agents are configured with:
      """
      review:
        trigger: "false"
      """
    And an issue
    And a remote branch "agent/<issue>-impl" seeded with a commit
    And a dummy agent that would:
      | description                 | op              | args                                                     |
      | Check out namespaced branch | checkout_branch | agent/<issue>-impl                                       |
      | Emit code JSON              | write_fixture   | output/agent-result.json, fixtures/code/implemented.json |
    When the issue is labeled "ready-to-code"
    Then the harness "code" workflow completes successfully
    And the agent will succeed to Check out namespaced branch
    And the pull request head branch matches "agent/<issue>-impl"
