#!/usr/bin/env bash
# Validates that dependency installs are hardened against OpenSSF Scorecard
# Pinned-Dependencies findings (issue #378) and SonarCloud GitHub Actions /
# dependency-hardening findings (issue #358):
#   - githubactions:S8541 — pip install must pass --only-binary :all: so no
#     source-distribution setup script is executed during CI.
#   - githubactions:S8543/S8544/S8545 & OpenSSF Scorecard Pinned-Dependencies —
#     pip install must pass --require-hashes with -r <requirements-file>, and
#     every referenced requirements file must pin exact versions (name==X.Y.Z)
#     with SHA-256 hashes (--hash=sha256:...).
#   - text:S8564 — package.json must ship a committed lock file
#     (package-lock.json) so npm resolves predictable versions.
# This guard catches a regression in PR CI instead of waiting for the next
# SonarCloud audit or OpenSSF Scorecard scan.
set -euo pipefail

ERRORS=0
CI_FILE="${1:-.github/workflows/ci.yml}"
LOCK_FILE="${2:-package-lock.json}"
readonly DONE_MSG="  done."

error() {
  local message="$1"
  printf "ERROR: %s\n" "$message" >&2
  ERRORS=$((ERRORS + 1))
}

extract_req_file() {
  local cmd="$1"
  sed -nE 's/.*(^|[[:space:]])(-r|--requirement)([[:space:]]+|=)["'"'"']?([^"'"'"'[:space:];]+)["'"'"']?.*/\4/p' <<< "$cmd" | head -n 1
}

has_inline_pip_args() {
  local cmd="$1"
  local rest
  # Extract the pip install segment up to any shell control operator (;, |, &)
  rest=$(sed -E '
    s/^.*[[:space:]]pip[0-9]*[[:space:]]+install([[:space:]]+|$)//;
    s/^pip[0-9]*[[:space:]]+install([[:space:]]+|$)//;
    s/[;&|].*$//;
    s/(^|[[:space:]])--require-hashes([[:space:]]|$)/ /g;
    s/(^|[[:space:]])--only-binary([[:space:]]+|=):all:([[:space:]]|$)/ /g;
    s/(^|[[:space:]])(-r|--requirement)([[:space:]]+|=)["'"'"']?[^"'"'"'[:space:]]+["'"'"']?([[:space:]]|$)/ /g;
    s/(^|[[:space:]])(-q|--quiet|--no-cache-dir|--disable-pip-version-check)([[:space:]]|$)/ /g;
    s/(^|[[:space:]])(--retries|--timeout)([[:space:]]+|=)[0-9]+([[:space:]]|$)/ /g;
    s/[[:space:]]+//g
  ' <<< "$cmd")
  [[ -n "$rest" ]]
}

validate_requirements_file() {
  local req_file="$1"
  if [[ ! -f "$req_file" ]]; then
    error "pip install references missing requirements file: $req_file"
    return
  fi

  local problems
  problems=$(awk '
    BEGIN {
      pkg_count = 0
      in_cont = 0
      current_hashes = 0
      current_pkg = ""
      bad = 0
    }
    {
      sub(/\r$/, "")
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "" || substr(line, 1, 1) == "#") {
        if (in_cont) {
          print "blank or comment line breaks backslash continuation"
          bad = 1
          in_cont = 0
        }
        next
      }
      has_cont = (line ~ /\\$/)
      if (has_cont) {
        sub(/[[:space:]]*\\$/, "", line)
      }
      if (line ~ /^[A-Za-z0-9._-]+==[0-9][0-9A-Za-z._+-]*$/) {
        if (in_cont) {
          printf "expected --hash continuation before new package: %s\n", line
          bad = 1
        }
        if (pkg_count > 0 && current_hashes == 0) {
          printf "package %s is missing --hash=sha256:<64-hex>\n", current_pkg
          bad = 1
        }
        pkg_count++
        current_pkg = line
        current_hashes = 0
        in_cont = has_cont
      } else if (line ~ /^--hash=sha256:[0-9a-fA-F]{64}$/) {
        if (!in_cont || pkg_count == 0) {
          printf "hash line without preceding backslash continuation: %s\n", line
          bad = 1
        } else {
          current_hashes++
          in_cont = has_cont
        }
      } else {
        printf "unpinned or invalid requirement line: %s\n", line
        bad = 1
      }
    }
    END {
      if (in_cont) {
        print "file ends with a dangling backslash continuation"
        bad = 1
      }
      if (pkg_count == 0) {
        print "no pinned packages (name==X.Y.Z) found"
        bad = 1
      } else if (current_hashes == 0) {
        printf "package %s is missing --hash=sha256:<64-hex>\n", current_pkg
        bad = 1
      }
      exit bad
    }
  ' "$req_file" 2>&1) || {
    while IFS= read -r problem; do
      [[ -z "$problem" ]] && continue
      error "$req_file: $problem"
    done <<< "$problems"
  }
}

echo "=== dependency hardening check ==="
echo ""

if [[ ! -f "$CI_FILE" ]]; then
  error "Missing $CI_FILE"
  exit 1
fi

# Collect every `pip install` invocation across target workflow(s) so each one
# is held to the same hardening bar (no unpinned / source-buildable install slips in).
WORKFLOW_TARGETS=("$CI_FILE")
if [[ $# -eq 0 && -d ".github/workflows" ]]; then
  WORKFLOW_TARGETS=(.github/workflows/*.yml)
fi

PIP_LINES=()
for wf in "${WORKFLOW_TARGETS[@]}"; do
  [[ -f "$wf" ]] || continue
  while IFS= read -r pip_line; do
    [[ -n "$pip_line" ]] && PIP_LINES+=("${wf}:${pip_line}")
  done < <(grep -nE 'pip[0-9]*[[:space:]]+install' "$wf" | grep -vE '^[0-9]+:[[:space:]]*(#|echo[[:space:]])' || true)
done

echo "Check 1: at least one pip install step exists to validate"
if [[ ${#PIP_LINES[@]} -eq 0 ]]; then
  error "$CI_FILE has no 'pip install' step — expected the PyYAML install"
fi
echo "$DONE_MSG"

echo "Check 2: every pip install passes --only-binary :all: (S8541)"
for entry in "${PIP_LINES[@]}"; do
  cmd="${entry#*:*:}"
  if ! grep -qE -- '--only-binary([[:space:]]+|=):all:' <<< "$cmd"; then
    error "pip install missing '--only-binary :all:': $entry"
  fi
done
echo "$DONE_MSG"

echo "Check 3: every pip install passes --require-hashes with -r <file> (Scorecard Pinned-Dependencies, S8543/S8545)"
REQ_FILES=()
for entry in "${PIP_LINES[@]}"; do
  cmd="${entry#*:*:}"
  if ! grep -qE -- '(^|[[:space:]])--require-hashes([[:space:]]|;|$)' <<< "$cmd"; then
    error "pip install missing '--require-hashes': $entry"
  fi
  req_file=$(extract_req_file "$cmd")
  if [[ -z "$req_file" ]]; then
    error "pip install missing '-r <requirements-file>': $entry"
  else
    REQ_FILES+=("$req_file")
  fi
  if has_inline_pip_args "$cmd"; then
    error "pip install passes inline package arguments outside '-r <requirements-file>': $entry"
  fi
done
echo "$DONE_MSG"

echo "Check 4: every referenced requirements file pins exact versions (==) and SHA-256 hashes (S8544, Scorecard)"
if [[ ${#REQ_FILES[@]} -eq 0 ]]; then
  error "No requirements files referenced by pip install commands"
else
  for req_file in "${REQ_FILES[@]}"; do
    validate_requirements_file "$req_file"
  done
fi
echo "$DONE_MSG"

echo "Check 5: a committed lock file accompanies package.json (S8564)"
if [[ -f "package.json" && ! -f "$LOCK_FILE" ]]; then
  error "Missing $LOCK_FILE — package.json needs a committed lock file"
fi
echo "$DONE_MSG"

echo ""
if [[ "$ERRORS" -gt 0 ]]; then
  echo "dependency hardening check failed with $ERRORS error(s)" >&2
  exit 1
else
  echo "All dependency hardening checks passed"
  exit 0
fi
