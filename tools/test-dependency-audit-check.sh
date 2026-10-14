#!/usr/bin/env bash
# Validates that the dependency-audit workflow keeps producing the
# "dependency-audit / Detect ecosystems" required status check enforced by the
# code-quality ruleset (compliance: ruleset-drift-code-quality-required_status_checks,
# issue #388).
#
# The codified ruleset (combsmith/.github → standards/rulesets/code-quality.json)
# requires the context "dependency-audit / Detect ecosystems". A GitHub check
# context from a reusable-workflow caller is "<caller-job-id> / <reusable-job-name>",
# so that exact context is produced only when:
#   - a job with id "dependency-audit" exists in this workflow, and
#   - it calls the org reusable dependency-audit-reusable.yml (whose "detect"
#     job is named "Detect ecosystems").
# If either half drifts (job renamed, uses: changed, workflow deleted, or the
# PR trigger dropped so the check never runs), the required check becomes
# unsatisfiable and every merge to main is blocked. This guard catches that in
# PR CI instead of waiting for the next weekly compliance audit.
#
# Usage: bash tools/test-dependency-audit-check.sh [workflow-file]
#   workflow-file  Path to the dependency-audit workflow.
#                  Defaults to .github/workflows/dependency-audit.yml.
set -euo pipefail

WORKFLOW="${1:-.github/workflows/dependency-audit.yml}"
REUSABLE="combsmith/.github/.github/workflows/dependency-audit-reusable.yml"
CALLER_JOB="dependency-audit"

ERRORS=0
error() {
  local message="$1"
  echo "ERROR: $message" >&2
  ERRORS=$((ERRORS + 1))
}

echo "=== dependency-audit required-check contract ($WORKFLOW) ==="
echo ""

if [[ ! -f "$WORKFLOW" ]]; then
  error "Missing $WORKFLOW — the 'dependency-audit / Detect ecosystems' required check cannot be produced"
  echo ""
  echo "dependency-audit check contract failed with $ERRORS error(s)" >&2
  exit 1
fi

echo "Check 1: workflow triggers on pull_request and push to main"
if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
  trigger_problems=$(python3 - "$WORKFLOW" <<'PY'
import sys, yaml

with open(sys.argv[1]) as fh:
    wf = yaml.safe_load(fh)
if not isinstance(wf, dict):
    wf = {}

# YAML parses the bare key 'on:' as the boolean True, so accept either form.
on = wf.get("on", wf.get(True, {}))
if isinstance(on, list):
    on = {k: None for k in on}
elif isinstance(on, str):
    on = {on: None}
elif not isinstance(on, dict):
    on = {}

def branches(event):
    if event not in on:
        return None
    node = on.get(event)
    if not isinstance(node, dict):
        return ["main"]
    if "branches" not in node:
        return ["main"]
    b = node.get("branches")
    if isinstance(b, str):
        return [b]
    return b if isinstance(b, list) else []

problems = []
for event in ("pull_request", "push"):
    b = branches(event)
    if b is None:
        problems.append(f"missing '{event}:' trigger")
    elif "main" not in b:
        problems.append(f"'{event}:' does not target 'main' (got {b})")

# 'merge_group' is part of the canonical trigger set (standards/workflows/
# dependency-audit.yml). It is required so the 'dependency-audit / Detect
# ecosystems' check reports on a merge queue's 'gh-readonly-queue/*' ref;
# dropping it is centrally-owned 'on:' drift.
if "merge_group" not in on:
    problems.append("missing 'merge_group:' trigger")
else:
    # A bare 'merge_group:' (null) or one without an explicit 'types:' uses the
    # default activity type 'checks_requested', which fires on a merge queue. But
    # an explicit 'types:' that omits 'checks_requested' silently stops the
    # workflow from running on merge-queue requests while still passing a
    # bare-presence check, so the required check never reports there.
    mg = on.get("merge_group")
    if isinstance(mg, dict) and "types" in mg:
        types = mg.get("types")
        if isinstance(types, str):
            types = [types]
        if not isinstance(types, list) or "checks_requested" not in types:
            problems.append(
                "'merge_group:' types do not include 'checks_requested' "
                f"(got {mg.get('types')}) — the check would not run on a merge queue"
            )
print("\n".join(problems))
PY
)
  if [[ -n "$trigger_problems" ]]; then
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      # 'merge_group' problems concern the merge-queue ref, not PRs to main, so
      # branch the satisfiability suffix to steer a fixing developer correctly.
      if [[ "$p" == *merge_group* ]]; then
        error "$WORKFLOW $p — the required check must run on the merge queue (gh-readonly-queue/*) to be satisfiable"
      else
        error "$WORKFLOW $p — the required check must run on PRs to main to be satisfiable"
      fi
    done <<< "$trigger_problems"
  fi
else
  echo "  python3/PyYAML unavailable — skipping trigger validation" >&2
fi
echo "  done."

echo ""
echo "Check 2: a job with id '$CALLER_JOB' exists (left side of the check context)"
if ! grep -qE "^[[:space:]]+${CALLER_JOB}:[[:space:]]*$" "$WORKFLOW"; then
  error "$WORKFLOW does not define a job id '$CALLER_JOB' — the check context would not be '$CALLER_JOB / Detect ecosystems'"
fi
echo "  done."

echo ""
echo "Check 3: the job calls the org dependency-audit reusable, pinned to a ref"
if ! grep -qE "uses:[[:space:]]*['\"]?${REUSABLE}@" "$WORKFLOW"; then
  error "$WORKFLOW does not call '${REUSABLE}@<ref>' — the reusable's 'Detect ecosystems' job supplies the right side of the check context"
fi
echo "  done."

echo ""
if [[ "$ERRORS" -gt 0 ]]; then
  echo "dependency-audit check contract failed with $ERRORS error(s)" >&2
  exit 1
else
  echo "All dependency-audit check contract checks passed"
  exit 0
fi
