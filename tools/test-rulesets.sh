#!/usr/bin/env bash
# Validates that the codified pr-quality ruleset and its self-healing applier are
# present and in compliance with the org standard (standards/github-settings.md)
# and OpenSSF Scorecard Branch-Protection requirements (issue #157). The live
# ruleset on the repo is converged by scripts/apply-rulesets.sh, which reads
# standards/rulesets/*.json as the source of truth.
set -euo pipefail

ERRORS=0
RULESET="${1:-${RULESET:-standards/rulesets/pr-quality.json}}"
APPLIER="${2:-${APPLIER:-scripts/apply-rulesets.sh}}"
WORKFLOW="${3:-${WORKFLOW:-.github/workflows/apply-repo-settings.yml}}"
readonly DONE_MARK="  done."

error() {
  local msg="$1"
  echo "ERROR: $msg" >&2
  ERRORS=$((ERRORS + 1))
}

echo "=== pr-quality ruleset — compliance coverage check ==="
echo ""

# Check 1: the codified ruleset exists and is a valid JSON object.
echo "Check 1: $RULESET exists and is valid JSON"
if [[ ! -f "$RULESET" ]]; then
  error "Missing $RULESET"
elif ! python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d, dict) else 1)" "$RULESET" 2>/dev/null; then
  error "$RULESET is not a valid JSON object"
fi
echo "$DONE_MARK"

# Check 2: the pull_request rule requires dismiss_stale_reviews_on_push and all
# org-standard review/merge controls (compliance check
# ruleset-drift-pr-quality-dismiss_stale_reviews_on_push, issues #427, #445, #447, #453, #461).
echo ""
echo "Check 2: pull_request rule sets dismiss_stale_reviews_on_push to true"
if [[ -f "$RULESET" ]]; then
  if ! python3 - "$RULESET" <<'PY'
import json, sys

with open(sys.argv[1]) as fh:
    ruleset = json.load(fh)

if not isinstance(ruleset, dict):
    sys.exit("ruleset root must be a JSON object")

rules = ruleset.get("rules", [])
if not isinstance(rules, list):
    sys.exit("rules must be a list")

pr_rules = [r for r in rules if isinstance(r, dict) and r.get("type") == "pull_request"]
if not pr_rules:
    sys.exit("no pull_request rule found")

for rule in pr_rules:
    params = rule.get("parameters")
    if not isinstance(params, dict):
        sys.exit("pull_request rule parameters must be an object")

    if params.get("dismiss_stale_reviews_on_push") is not True:
        sys.exit("dismiss_stale_reviews_on_push is not true")

    if params.get("allowed_merge_methods") != ["squash"]:
        sys.exit("allowed_merge_methods must equal exactly [\"squash\"]")

    review_count = params.get("required_approving_review_count")
    if isinstance(review_count, bool) or not isinstance(review_count, int) or review_count < 1:
        sys.exit("required_approving_review_count must be an integer >= 1")

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
  normalized_workflow=$(grep -Ev '^[[:space:]]*#' "$WORKFLOW" | tr '"' "'")
  if echo "$normalized_workflow" | grep -Eq "^[[:space:]]*uses:[[:space:]]*combsmith/\.github/\.github/workflows/apply-repo-settings-reusable\.yml@apply-repo-settings/"; then
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

# Check 5: the codified ruleset enforces OpenSSF Scorecard Branch-Protection Tier 1
# rules (deletion and non_fast_forward) on the active default branch (issue #157,
# standards/github-settings.md#pr-quality--standard-ruleset-all-repositories).
echo ""
echo "Check 5: $RULESET enforces active default-branch deletion and non_fast_forward rules (Scorecard Branch-Protection #157)"
if [[ -f "$RULESET" ]]; then
  if ! python3 - "$RULESET" <<'PY'
import json, sys

with open(sys.argv[1]) as fh:
    ruleset = json.load(fh)

if not isinstance(ruleset, dict):
    sys.exit("ruleset root must be a JSON object")

if ruleset.get("name") != "pr-quality":
    sys.exit("name must equal 'pr-quality'")

if ruleset.get("target") != "branch":
    sys.exit("target must equal 'branch'")

if ruleset.get("enforcement") != "active":
    sys.exit("enforcement must equal 'active'")

conditions = ruleset.get("conditions")
if not isinstance(conditions, dict):
    sys.exit("conditions must be an object")

ref_name = conditions.get("ref_name")
if not isinstance(ref_name, dict):
    sys.exit("conditions.ref_name must be an object")

include = ref_name.get("include")
if not isinstance(include, list) or "~DEFAULT_BRANCH" not in include:
    sys.exit("conditions.ref_name.include must contain '~DEFAULT_BRANCH'")

exclude = ref_name.get("exclude")
if not isinstance(exclude, list) or len(exclude) != 0:
    sys.exit("conditions.ref_name.exclude must be an empty list []")

rules = ruleset.get("rules")
if not isinstance(rules, list):
    sys.exit("rules must be a list")

rule_types = []
for rule in rules:
    if not isinstance(rule, dict) or not isinstance(rule.get("type"), str):
        sys.exit("every rule must be an object with a string 'type'")
    rule_types.append(rule["type"])

if len(rule_types) != len(set(rule_types)):
    sys.exit("duplicate rule types in rules")

for required_rule in ("deletion", "non_fast_forward"):
    matching = [r for r in rules if r.get("type") == required_rule]
    if not matching:
        sys.exit(f"missing required Tier 1 rule: {required_rule}")
    if any(set(r.keys()) != {"type"} for r in matching):
        sys.exit(f"{required_rule} rule must only contain 'type'")

bypass_actors = ruleset.get("bypass_actors")
if not isinstance(bypass_actors, list):
    sys.exit("bypass_actors must be a list")

has_org_admin = any(
    isinstance(a, dict)
    and a.get("actor_type") == "OrganizationAdmin"
    and a.get("bypass_mode") == "always"
    for a in bypass_actors
)
has_dependabot_app = any(
    isinstance(a, dict)
    and a.get("actor_type") == "Integration"
    and a.get("actor_id") == 3167543
    and a.get("bypass_mode") == "always"
    for a in bypass_actors
)
if not has_org_admin or not has_dependabot_app:
    sys.exit("bypass_actors must include OrganizationAdmin and Integration 3167543 with bypass_mode='always'")
PY
  then
    error "$RULESET does not enforce active default-branch deletion and non_fast_forward protection (Scorecard Branch-Protection #157)"
  fi
else
  error "Cannot check Branch-Protection Tier 1 controls — $RULESET is missing"
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
