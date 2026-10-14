#!/usr/bin/env bash
# Validates that the codified pr-quality ruleset and its self-healing applier are
# present and in compliance with the org standard. The live ruleset on the repo is
# converged by scripts/apply-rulesets.sh, which reads standards/rulesets/*.json as
# the source of truth.
set -euo pipefail

ERRORS=0
RULESET="standards/rulesets/pr-quality.json"
APPLIER="scripts/apply-rulesets.sh"
WORKFLOW=".github/workflows/apply-repo-settings.yml"
readonly DONE_MARK="  done."

error() {
  local msg="$1"
  echo "ERROR: $msg" >&2
  ERRORS=$((ERRORS + 1))
}

echo "=== pr-quality ruleset — compliance coverage check ==="
echo ""

# Check 1: the codified ruleset exists and is valid JSON.
echo "Check 1: $RULESET exists and is valid JSON"
if [[ ! -f "$RULESET" ]]; then
  error "Missing $RULESET"
elif ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$RULESET" 2>/dev/null; then
  error "$RULESET is not valid JSON"
fi
echo "$DONE_MARK"

# Check 2: the pull_request rule requires dismiss_stale_reviews_on_push (compliance
# check ruleset-drift-pr-quality-dismiss_stale_reviews_on_push, issues #427, #445, #447, #453, #461).
echo ""
echo "Check 2: pull_request rule sets dismiss_stale_reviews_on_push to true"
if [[ -f "$RULESET" ]]; then
  if ! python3 - "$RULESET" <<'PY'
import json, sys

with open(sys.argv[1]) as fh:
    ruleset = json.load(fh)

rules = ruleset.get("rules", [])
pr_rules = [r for r in rules if r.get("type") == "pull_request"]
if not pr_rules:
    sys.exit("no pull_request rule found")

for rule in pr_rules:
    params = rule.get("parameters", {})

    if params.get("dismiss_stale_reviews_on_push") is not True:
        sys.exit("dismiss_stale_reviews_on_push is not true")

    if params.get("allowed_merge_methods") != ["squash"]:
        sys.exit("allowed_merge_methods must equal exactly [\"squash\"]")

    if not isinstance(params.get("required_approving_review_count"), int) or params.get("required_approving_review_count") < 1:
        sys.exit("required_approving_review_count must be at least 1")

    if params.get("require_code_owner_review") is not True:
        sys.exit("require_code_owner_review must be true")

    if params.get("required_review_thread_resolution") is not True:
        sys.exit("required_review_thread_resolution must be true")

    if params.get("require_last_push_approval") is not True:
        sys.exit("require_last_push_approval must be true")
PY
  then
    error "$RULESET does not comply with required pull_request controls"
  fi
else
  error "Cannot check pull_request controls — $RULESET is missing"
fi
echo "$DONE_MARK"

# Check 3: the idempotent applier script exists.
echo ""
echo "Check 3: $APPLIER exists"
if [[ ! -f "$APPLIER" ]]; then
  error "Missing $APPLIER — the ruleset cannot be converged without an applier"
fi
echo "$DONE_MARK"

# Check 4: the settings workflow converges the pr-quality ruleset so drift
# self-heals. This is satisfied either by the thin caller-stub model — the workflow
# references the approved org reusable (apply-repo-settings-reusable.yml on its
# first-party channel pin), which runs the ruleset remediation centrally — or by
# the legacy model where the workflow invokes apply-rulesets.sh for pr-quality
# locally. Either contract keeps pr-quality drift self-healing.
echo ""
echo "Check 4: $WORKFLOW converges the pr-quality ruleset (reusable ref or local applier)"
if [[ ! -f "$WORKFLOW" ]]; then
  error "Missing $WORKFLOW"
else
  normalized_workflow=$(tr '"' "'" < "$WORKFLOW")
  if echo "$normalized_workflow" | grep -Eq "uses:[[:space:]]*combsmith/\.github/\.github/workflows/apply-repo-settings-reusable\.yml@apply-repo-settings/"; then
    :  # approved reusable-workflow reference — ruleset remediation runs centrally
  elif echo "$normalized_workflow" | grep -Eq "apply-rulesets\.sh.*pr-quality"; then
    :  # legacy local applier model — also compliant
  elif echo "$normalized_workflow" | grep -q "apply-rulesets.sh"; then
    error "$WORKFLOW invokes apply-rulesets.sh but not for the pr-quality ruleset"
  else
    error "$WORKFLOW neither references the approved apply-repo-settings-reusable workflow nor invokes apply-rulesets.sh for pr-quality — the ruleset will not be re-applied on merge"
  fi
fi
echo "$DONE_MARK"

echo ""
if [[ "$ERRORS" -gt 0 ]]; then
  echo "Ruleset compliance check failed with $ERRORS error(s)" >&2
  exit 1
else
  echo "All ruleset compliance checks passed"
  exit 0
fi
