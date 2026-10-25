#!/usr/bin/env bash
# Validates that .github/workflows/apply-repo-settings.yml follows the
# canonical org thin-caller-stub contract (combsmith/.github#984, issue #440)
# and that the diverged local script fork (scripts/apply-repo-settings.sh)
# has been removed.
set -euo pipefail

ERRORS=0
WORKFLOW="${1:-.github/workflows/apply-repo-settings.yml}"
LEGACY_SCRIPT="${2:-scripts/apply-repo-settings.sh}"
readonly DONE_MARK="  done."

# Record a validation error message to stderr and increment ERRORS.
# Arguments:
#   $1 - Error message to report.
error() {
  local msg="$1"
  echo "ERROR: $msg" >&2
  ERRORS=$((ERRORS + 1))
  return 0
}

echo "=== apply-repo-settings.yml — thin caller stub & fork removal check ==="
echo ""

# Check 1: diverged local script fork is removed (consumer repos carry no script copy)
echo "Check 1: diverged local fork $LEGACY_SCRIPT is removed"
if [[ -e "$LEGACY_SCRIPT" ]]; then
  error "$LEGACY_SCRIPT still exists — consumer repos must not carry a local apply-repo-settings.sh fork (use the org reusable workflow)"
fi
echo "$DONE_MARK"

# Check 2: workflow file exists and uses canonical name "Apply repo settings"
echo ""
echo "Check 2: $WORKFLOW exists and uses canonical name 'Apply repo settings'"
if [[ ! -f "$WORKFLOW" ]]; then
  error "Missing $WORKFLOW"
  echo "$DONE_MARK"
  echo ""
  echo "Settings workflow check failed with $ERRORS error(s)" >&2
  exit 1
fi
if grep -Eq '^name:[[:space:]]*["'"'"']?Apply repository settings["'"'"']?[[:space:]]*$' "$WORKFLOW"; then
  error "$WORKFLOW still uses legacy fork name 'Apply repository settings' instead of canonical 'Apply repo settings'"
elif ! grep -Eq '^name:[[:space:]]*["'"'"']?Apply repo settings["'"'"']?[[:space:]]*$' "$WORKFLOW"; then
  error "$WORKFLOW does not declare canonical name 'Apply repo settings'"
fi
echo "$DONE_MARK"

# Check 3: workflow uses the reusable caller-stub trigger model (weekly schedule +
# manual dispatch + path-scoped push on the stub itself)
echo ""
echo "Check 3: $WORKFLOW uses the weekly + workflow-change trigger model"
if ! grep -Eq '^[[:space:]]*schedule:[[:space:]]*$' "$WORKFLOW"; then
  error "$WORKFLOW has no weekly 'schedule:' trigger — settings must converge on a cadence"
elif ! grep -Eq '^[[:space:]]*-[[:space:]]*cron:' "$WORKFLOW"; then
  error "$WORKFLOW declares 'schedule:' but defines no cron entry for the weekly self-heal"
elif grep -E '^[[:space:]]*-[[:space:]]*cron:' "$WORKFLOW" | grep -Evq '^[[:space:]]*-[[:space:]]*cron:[[:space:]]*["'"'"']?([0-9]|[1-5][0-9])[[:space:]]+([0-9]|1[0-9]|2[0-3])[[:space:]]+\*[[:space:]]+\*[[:space:]]+([0-7]|SUN|MON|TUE|WED|THU|FRI|SAT|sun|mon|tue|wed|thu|fri|sat)["'"'"']?[[:space:]]*(#.*)?$'; then
  error "$WORKFLOW cron entry must define a weekly schedule ('<min> <hour> * * <day-of-week>'), not a daily or other cadence"
fi
if ! grep -Eq '^[[:space:]]*workflow_dispatch:' "$WORKFLOW"; then
  error "$WORKFLOW has no 'workflow_dispatch:' trigger — settings must remain manually recoverable"
fi
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c "import yaml" >/dev/null 2>&1; then
  error "$WORKFLOW cannot be validated: python3 with PyYAML is required"
elif ! python3 - "$WORKFLOW" <<'PY'
import sys, yaml

TARGET_BRANCH = "main"
TARGET_PATH = ".github/workflows/apply-repo-settings.yml"

with open(sys.argv[1]) as fh:
    wf = yaml.safe_load(fh)

if not isinstance(wf, dict):
    sys.exit(1)

on_block = wf.get("on") if "on" in wf else wf.get(True)
push_block = on_block.get("push") if isinstance(on_block, dict) else None
if not isinstance(push_block, dict):
    sys.exit(1)

if "branches" in push_block and "branches-ignore" in push_block:
    sys.exit(1)
if "paths" in push_block and "paths-ignore" in push_block:
    sys.exit(1)

branches = push_block.get("branches")
branches_ignore = push_block.get("branches-ignore")
paths = push_block.get("paths")
paths_ignore = push_block.get("paths-ignore")

def target_is_included(patterns, target):
    included = False
    for pattern in patterns:
        if pattern == target:
            included = True
        elif pattern == f"!{target}":
            included = False
    return included

if not isinstance(branches, list) or not target_is_included(branches, TARGET_BRANCH):
    sys.exit(1)
if isinstance(branches_ignore, list) and TARGET_BRANCH in branches_ignore:
    sys.exit(1)
if not isinstance(paths, list) or not target_is_included(paths, TARGET_PATH):
    sys.exit(1)
if isinstance(paths_ignore, list) and TARGET_PATH in paths_ignore:
    sys.exit(1)
PY
then
  error "$WORKFLOW on.push must include 'main' in branches and '.github/workflows/apply-repo-settings.yml' in paths (and not under branches-ignore/paths-ignore)"
fi
echo "$DONE_MARK"

# Check 4: apply job delegates to the org reusable workflow on the ring1 channel
# with checkout_ref in lockstep, secrets: inherit, and no inline steps
echo ""
echo "Check 4: $WORKFLOW delegates to org reusable workflow with checkout_ref in lockstep"
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c "import yaml" >/dev/null 2>&1; then
  error "$WORKFLOW cannot be validated: python3 with PyYAML is required"
else
  stub_problems=$(python3 - "$WORKFLOW" <<'PY'
import re, sys, yaml

REUSABLE_PREFIX = "combsmith/.github/.github/workflows/apply-repo-settings-reusable.yml@"
CHANNEL_PATTERN = re.compile(r"^apply-repo-settings/v[0-9]+-ring1$")

with open(sys.argv[1]) as fh:
    wf = yaml.safe_load(fh)

if not isinstance(wf, dict):
    wf = {}

jobs = wf.get("jobs") if isinstance(wf.get("jobs"), dict) else {}
apply_job = jobs.get("apply") if isinstance(jobs.get("apply"), dict) else None

problems = []
if apply_job is None:
    problems.append("missing 'jobs.apply' job definition")
else:
    uses = str(apply_job.get("uses", ""))
    if not uses.startswith(REUSABLE_PREFIX):
        problems.append(f"jobs.apply.uses must target '{REUSABLE_PREFIX}<channel>' (got '{uses}')")
    else:
        channel = uses.split("@", 1)[1]
        if not CHANNEL_PATTERN.match(channel):
            problems.append(f"jobs.apply.uses channel must match 'apply-repo-settings/v<N>-ring1' for this ring1 repo (got '{channel}')")
        with_block = apply_job.get("with") if isinstance(apply_job.get("with"), dict) else {}
        checkout_ref = str(with_block.get("checkout_ref", ""))
        if checkout_ref != channel:
            problems.append(f"jobs.apply.with.checkout_ref ('{checkout_ref}') must match uses: channel ('{channel}')")

    if "steps" in apply_job:
        problems.append("jobs.apply must not define inline 'steps:' (thin caller stub delegates all logic to the reusable)")

    if apply_job.get("secrets") != "inherit":
        problems.append(f"jobs.apply.secrets must be 'inherit' (got '{apply_job.get('secrets')}')")

print("\n".join(problems))
PY
)
  if [[ -n "$stub_problems" ]]; then
    while IFS= read -r problem; do
      [[ -z "$problem" ]] && continue
      error "$WORKFLOW: $problem"
    done <<< "$stub_problems"
  fi
fi
echo "$DONE_MARK"

# Check 5: every permissions: scope in the workflow is a valid GitHub Actions
# scope. An invalid scope (e.g. `administration`, which is not a GITHUB_TOKEN
# permission) makes the whole file an "invalid workflow file" that fails at
# startup with 0s duration on every run.
echo ""
echo "Check 5: $WORKFLOW uses only valid permissions scopes"
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c "import yaml" >/dev/null 2>&1; then
  error "$WORKFLOW cannot be validated: python3 with PyYAML is required"
else
  invalid_scopes=$(python3 - "$WORKFLOW" <<'PY'
import sys, yaml

# Valid GITHUB_TOKEN permission scopes accepted in a workflow `permissions:` block.
ALLOWED = {
    "actions", "attestations", "checks", "contents", "deployments",
    "discussions", "id-token", "issues", "models", "packages", "pages",
    "pull-requests", "repository-projects", "security-events", "statuses",
}

with open(sys.argv[1]) as fh:
    wf = yaml.safe_load(fh)

if not isinstance(wf, dict):
    wf = {}

def scopes(perms):
    """Return the set of individual permission scope keys declared in perms."""
    return set(perms) if isinstance(perms, dict) else set()

bad = set()
bad |= scopes(wf.get("permissions"))
jobs = wf.get("jobs")
if isinstance(jobs, dict):
    for job in jobs.values():
        if isinstance(job, dict):
            bad |= scopes(job.get("permissions"))
bad -= ALLOWED
print("\n".join(sorted(bad)))
PY
)
  if [[ -n "$invalid_scopes" ]]; then
    while IFS= read -r scope; do
      [[ -z "$scope" ]] && continue
      error "$WORKFLOW declares invalid permissions scope '$scope' — GitHub rejects this as an invalid workflow file, causing every run to fail at startup"
    done <<< "$invalid_scopes"
  fi
fi
echo "$DONE_MARK"

echo ""
if [[ "$ERRORS" -gt 0 ]]; then
  echo "Settings workflow check failed with $ERRORS error(s)" >&2
  exit 1
else
  echo "All settings workflow checks passed"
  exit 0
fi
