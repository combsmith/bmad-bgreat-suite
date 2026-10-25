#!/usr/bin/env bash
# Validates that the PyYAML install in .github/workflows/ci.yml is hardened
# against transient network/PyPI failures (Fleet Monitor issue #381) while
# preserving binary-only and SHA-256 hash-locked installation (issues #358, #378).
#
# The Install PyYAML step is the only network-dependent operation in the CI
# workflow. Without a retry, a single PyPI hiccup fails the whole run and shows
# up as CI flakiness. This guard requires the install to run inside a bounded
# retry loop with a backoff, so the hardening cannot silently regress.
set -euo pipefail

ERRORS=0
CI_FILE="${1:-.github/workflows/ci.yml}"
readonly DONE_MARK="  done."

error() {
  local message="$1"
  printf "ERROR: %s\n" "$message" >&2
  ERRORS=$((ERRORS + 1))
}

echo "=== ci.yml — pip install retry hardening check ==="
echo ""

if [[ ! -f "$CI_FILE" ]]; then
  error "Missing $CI_FILE"
  exit 1
fi

# Extract only the "Install PyYAML" step block (from its `- name:` line up to
# the next step's `- name:` line) so the checks below cannot be satisfied by
# unrelated content elsewhere in the workflow.
STEP_BLOCK=$(awk '
  /^[[:space:]]*-[[:space:]]+name:[[:space:]]+["'"'"'"]?Install PyYAML["'"'"'"]?[[:space:]]*$/ { grab=1; print; next }
  grab && /^[[:space:]]*-[[:space:]]+(name|uses|run|id|if):/ { exit }
  grab { print }
' "$CI_FILE")

echo "Check 1: an 'Install PyYAML' step exists"
if [[ -z "$STEP_BLOCK" ]]; then
  error "$CI_FILE has no step named 'Install PyYAML'"
  # Nothing else can be validated without the step.
  echo "$DONE_MARK"
  echo ""
  echo "pip install retry hardening check failed with $ERRORS error(s)" >&2
  exit 1
fi
echo "$DONE_MARK"

echo "Check 2: the install still pins pyyaml with --require-hashes and --only-binary :all:"
if ! grep -qiE 'pip[0-9]*[[:space:]]+install' <<< "$STEP_BLOCK"; then
  error "Install PyYAML step no longer contains a 'pip install' invocation"
fi
if ! grep -qE -- '(^|[[:space:]])--require-hashes([[:space:]]|;|$)' <<< "$STEP_BLOCK"; then
  error "Install PyYAML step no longer passes --require-hashes"
fi
if ! grep -qE -- '--only-binary([[:space:]]+|=):all:' <<< "$STEP_BLOCK"; then
  error "Install PyYAML step no longer passes --only-binary :all:"
fi
REQ_FILE=$(sed -nE 's/.*(^|[[:space:]])(-r|--requirement)([[:space:]]+|=)["'"'"']?([^"'"'"'[:space:];]+)["'"'"']?.*/\4/p' <<< "$STEP_BLOCK" | head -n 1)
if [[ -z "$REQ_FILE" ]]; then
  error "Install PyYAML step no longer references a requirements file via -r <file>"
elif [[ ! -f "$REQ_FILE" ]]; then
  error "Install PyYAML step references missing requirements file: $REQ_FILE"
elif ! grep -qiE '^pyyaml==[0-9]' "$REQ_FILE" || ! grep -qiE '^[[:space:]]*--hash=sha256:[0-9a-f]{64}' "$REQ_FILE"; then
  error "Requirements file $REQ_FILE does not pin pyyaml==X.Y.Z with --hash=sha256: digests"
fi
echo "$DONE_MARK"

echo "Check 3: the install runs inside a bounded retry loop"
if ! grep -qE 'for[[:space:]]+[[:alnum:]_]+[[:space:]]+in[[:space:]]+(([0-9]+[[:space:]]*){2,}|\{[0-9]+\.\.[0-9]+\})' <<< "$STEP_BLOCK"; then
  error "Install PyYAML step does not use a bounded retry loop (e.g., 'for n in 1 2 3' or 'for n in {1..3}')"
fi
echo "$DONE_MARK"

echo "Check 4: the retry loop backs off between attempts (sleep)"
if ! grep -qE '(^|[[:space:]])sleep[[:space:]]' <<< "$STEP_BLOCK"; then
  error "Install PyYAML retry loop has no 'sleep' backoff between attempts"
fi
echo "$DONE_MARK"

echo ""
if [[ "$ERRORS" -gt 0 ]]; then
  echo "pip install retry hardening check failed with $ERRORS error(s)" >&2
  exit 1
else
  echo "All pip install retry hardening checks passed"
  exit 0
fi
