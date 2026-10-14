#!/usr/bin/env bash
# Validates that .github/workflows/ci.yml contains a compliant secret-scan job
# per the org push-protection standard.
# See: https://github.com/combsmith/.github/blob/main/standards/push-protection.md#required-ci-job
set -euo pipefail

ERRORS=0
CI_FILE=".github/workflows/ci.yml"
readonly DONE_MARK="  done."

error() {
  local msg="$1"
  echo "ERROR: $msg" >&2
  ERRORS=$((ERRORS + 1))
}

echo "=== ci.yml — secret-scan job compliance check ==="
echo ""

if [[ ! -f "$CI_FILE" ]]; then
  error "Missing $CI_FILE"
  exit 1
fi

# Check 1: secret-scan job key is present
echo "Check 1: secret-scan job is defined"
if ! grep -q '^  secret-scan:' "$CI_FILE"; then
  error "$CI_FILE does not contain a 'secret-scan' job"
fi
echo "$DONE_MARK"

# Extract only the secret-scan job block (from its job key to the next top-level
# job entry) so checks 2-4 cannot be satisfied by content in other jobs or by
# comments that merely mention the action string elsewhere in the file.
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT
awk '/^  secret-scan:/{p=1} p && /^  [a-zA-Z]/ && !/^  secret-scan:/{exit} p{print}' "$CI_FILE" > "$TMPFILE"

# Check 2: gitleaks/gitleaks-action is used on an actual uses: line (scoped to secret-scan job)
echo "Check 2: secret-scan job uses gitleaks/gitleaks-action"
if ! grep -qE '^\s+uses:\s+gitleaks/gitleaks-action' "$TMPFILE"; then
  error "secret-scan job does not use gitleaks/gitleaks-action on a uses: line"
fi
echo "$DONE_MARK"

# Check 3: fetch-depth: 0 is set in the checkout step's with: block (not just anywhere in the job)
echo "Check 3: secret-scan checkout uses fetch-depth: 0"
if ! awk '
  /uses:[[:space:]]+actions\/checkout/ { in_checkout=1; in_with=0; next }
  in_checkout && /^[[:space:]]+with:/ { in_with=1; next }
  in_with && /fetch-depth:[[:space:]]+0/ { found=1; exit }
  in_with && /^[[:space:]]+-/ { exit }
  /^[[:space:]]+-/ { in_checkout=0; in_with=0 }
  END { exit !found }
' "$TMPFILE"; then
  error "secret-scan checkout step does not set fetch-depth: 0 in its with: block"
fi
echo "$DONE_MARK"

# Check 4: continue-on-error must NOT be set on the gitleaks step
# (having it would allow gitleaks findings to silently pass the build)
echo "Check 4: continue-on-error must NOT be set on the gitleaks step" # NOSONAR
# Use /^[[:space:]]+-[[:space:]]/ as the step delimiter so the check is
# order-independent: continue-on-error is caught whether it appears before or
# after the uses: line within the same step.
if awk '/^[[:space:]]+-[[:space:]]/ { if (gitleaks && cont) { found=1; exit } gitleaks=0; cont=0 } /gitleaks\/gitleaks-action/ { gitleaks=1 } /continue-on-error/ { cont=1 } END { if (gitleaks && cont || found) exit 1 }' "$TMPFILE"; then
  : # no continue-on-error found on the gitleaks step
else
  error "secret-scan job has 'continue-on-error' on the gitleaks step — findings will not fail the build"
fi
echo "$DONE_MARK"

# Check 5: gitleaks step passes --redact and --exit-code 1 in its args
echo "Check 5: gitleaks step passes --redact and --exit-code 1"
GITLEAKS_ARGS=$(awk '
  /uses:[[:space:]]+gitleaks\/gitleaks-action/ { in_gitleaks=1; next }
  in_gitleaks && /args:/ { print; exit }
  /^[[:space:]]+-[[:space:]]/ { in_gitleaks=0 }
' "$TMPFILE")
if ! echo "$GITLEAKS_ARGS" | grep -q -- '--redact'; then
  error "gitleaks step args do not include --redact"
fi
if ! echo "$GITLEAKS_ARGS" | grep -q -- '--exit-code 1'; then
  error "gitleaks step args do not include --exit-code 1"
fi
echo "$DONE_MARK"

# Check 6: secret-scan job is skipped for Dependabot events.
# Dependabot PR runs do not have access to secrets.GITLEAKS_LICENSE; the
# licensed gitleaks-action requires that secret and fails with "missing gitleaks
# license" (Fleet Monitor issue #397). The job must carry a job-level `if:`
# guard that excludes the dependabot[bot] actor.
echo "Check 6: secret-scan job skips Dependabot via job-level if: guard"
JOB_IF=$(awk '
  /^  secret-scan:/ { in_job=1; next }
  in_job && /^[[:space:]]+-[[:space:]]+["]?(name|uses|run|id|if)["]?:/ { exit }
  in_job && /^[[:space:]]+"?steps"?:/ { exit }
  in_job && /^[[:space:]]+"?if"?:/ { print; exit }
' "$TMPFILE")
if ! echo "$JOB_IF" | grep -q "dependabot\[bot\]"; then
  error "secret-scan job has no job-level 'if:' guard excluding dependabot[bot]"
fi
echo "$DONE_MARK"

echo ""
if [[ "$ERRORS" -gt 0 ]]; then
  echo "secret-scan compliance check failed with $ERRORS error(s)" >&2
  exit 1
else
  echo "All secret-scan compliance checks passed"
  exit 0
fi
