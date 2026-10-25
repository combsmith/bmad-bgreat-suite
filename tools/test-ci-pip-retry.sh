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
# Note: this is a retry-focused smoke check that the Install PyYAML step still
# invokes pip with hash/binary flags and a requirements file pinning pyyaml.
# Authoritative per-package version/hash validation across all workflow pip
# commands and requirements files lives in tools/test-ci-dependency-hardening.sh.
if ! grep -qiE 'pip[0-9]*[[:space:]]+install' <<< "$STEP_BLOCK"; then
  error "Install PyYAML step no longer contains a 'pip install' invocation"
fi
if ! grep -qE -- '(^|[[:space:]])--require-hashes([[:space:]]|\\|;|$)' <<< "$STEP_BLOCK"; then
  error "Install PyYAML step no longer passes --require-hashes"
fi
if ! grep -qE -- '--only-binary([[:space:]]+|=):all:' <<< "$STEP_BLOCK"; then
  error "Install PyYAML step no longer passes --only-binary :all:"
fi
STEP_REQ_FILES=()
while IFS= read -r req_file; do
  [[ -n "$req_file" ]] && STEP_REQ_FILES+=("$req_file")
done < <(
  awk '
    {
      sub(/[;&|].*$/, "")
      n = split($0, tok, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        t = tok[i]
        sub(/^["'"'"']/, "", t)
        sub(/["'"'"']$/, "", t)
        if ((t == "-r" || t == "--requirement") && i + 1 <= n) {
          v = tok[++i]
          sub(/^["'"'"']/, "", v)
          sub(/["'"'"']$/, "", v)
          if (v != "") print v
        } else if (t ~ /^(-r|--requirement)=/) {
          sub(/^(-r|--requirement)=/, "", t)
          sub(/^["'"'"']/, "", t)
          sub(/["'"'"']$/, "", t)
          if (t != "") print t
        }
      }
    }
  ' <<< "$STEP_BLOCK"
)
if [[ ${#STEP_REQ_FILES[@]} -eq 0 ]]; then
  error "Install PyYAML step no longer references a requirements file via -r <file>"
else
  pyyaml_pinned=false
  for req_file in "${STEP_REQ_FILES[@]}"; do
    if [[ ! -f "$req_file" ]]; then
      error "Install PyYAML step references missing requirements file: $req_file"
    elif awk '
      BEGIN { in_pyyaml = 0; ok = 0 }
      {
        sub(/\r$/, "")
        line = $0
        sub(/^[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)
        if (line == "" || line ~ /^#/) next
        has_cont = (line ~ /\\$/)
        sub(/[[:space:]]*\\$/, "", line)
        if (tolower(line) ~ /^pyyaml(\[[a-z0-9._,-]+\])?==[0-9]/) {
          in_pyyaml = 1
          if (line ~ /--hash=sha256:[0-9a-fA-F]{64}/) ok = 1
          if (!has_cont) in_pyyaml = 0
        } else if (in_pyyaml) {
          if (line ~ /--hash=sha256:[0-9a-fA-F]{64}/) ok = 1
          if (!has_cont) in_pyyaml = 0
        }
      }
      END { exit (ok ? 0 : 1) }
    ' "$req_file"; then
      pyyaml_pinned=true
    fi
  done
  if [[ "$pyyaml_pinned" != true ]]; then
    error "Referenced requirements file(s) (${STEP_REQ_FILES[*]}) do not pin pyyaml==X.Y.Z with --hash=sha256: digests"
  fi
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
