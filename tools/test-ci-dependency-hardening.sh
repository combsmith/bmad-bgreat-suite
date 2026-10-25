#!/usr/bin/env bash
# Validates that dependency installs across .github/workflows/*.yml and
# .github/workflows/*.yaml (or a single workflow passed as $1) are hardened
# against OpenSSF Scorecard Pinned-Dependencies findings (issue #378) and
# SonarCloud GitHub Actions / dependency-hardening findings (issue #358):
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

# Joins backslash-continued lines and YAML folded `run: >` blocks before
# scanning for `pip install`, emitting `<start-line>:<logical-line>`.
collect_pip_lines_from_file() {
  local wf="$1"
  awk '
    function flush_buf() {
      if (buf != "") {
        if (buf ~ /(^|[^[:alnum:]_.-])pip[0-9]*[[:space:]]+install([[:space:]]|$)/ &&
            buf !~ /^[[:space:]]*(#|echo[[:space:]])/) {
          printf "%d:%s\n", start_nr, buf
        }
        buf = ""
        start_nr = 0
      }
    }
    BEGIN {
      buf = ""
      start_nr = 0
      in_folded = 0
      folded_indent = 0
    }
    {
      sub(/\r$/, "")
      raw = $0
      match(raw, /^[[:space:]]*/)
      indent = RLENGTH
      trimmed = substr(raw, indent + 1)

      if (in_folded) {
        if (trimmed == "") {
          flush_buf()
          next
        }
        if (indent <= folded_indent) {
          flush_buf()
          in_folded = 0
        } else {
          sub(/[[:space:]]*\\$/, "", trimmed)
          if (buf == "") {
            buf = trimmed
            start_nr = NR
          } else {
            buf = buf " " trimmed
          }
          next
        }
      }

      if (raw ~ /^[[:space:]]*(-[[:space:]]+)?run:[[:space:]]*>[+-]?[[:space:]]*$/) {
        flush_buf()
        in_folded = 1
        folded_indent = indent
        if (raw ~ /^[[:space:]]*-[[:space:]]+run:/) {
          match(raw, /^[[:space:]]*-[[:space:]]+/)
          folded_indent = RLENGTH - 1
        }
        next
      }

      if (trimmed ~ /^#/) {
        next
      }

      has_cont = (trimmed ~ /\\$/)
      if (has_cont) {
        sub(/[[:space:]]*\\$/, "", trimmed)
      }

      if (buf == "") {
        buf = trimmed
        start_nr = NR
      } else {
        buf = buf " " trimmed
      }

      if (!has_cont) {
        flush_buf()
      }
    }
    END {
      flush_buf()
    }
  ' "$wf"
}

# Extracts every `-r <file>` / `--requirement <file>` (or `=file`) path from a
# `pip install` command segment, one per line.
extract_req_files() {
  local cmd="$1"
  awk '
    function unquote(s) {
      sub(/^["'"'"']/, "", s)
      sub(/["'"'"']$/, "", s)
      return s
    }
    {
      sub(/^.*pip[0-9]*[[:space:]]+install([[:space:]]+|$)/, "")
      sub(/[;&|].*$/, "")
      n = split($0, tok, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        t = tok[i]
        if (t == "-r" || t == "--requirement") {
          if (i + 1 <= n) {
            val = unquote(tok[++i])
            if (val != "" && val !~ /^-/) print val
          }
        } else if (t ~ /^(-r|--requirement)=/) {
          sub(/^(-r|--requirement)=/, "", t)
          val = unquote(t)
          if (val != "") print val
        } else if (t ~ /^-r.+/) {
          sub(/^-r/, "", t)
          val = unquote(t)
          if (val != "") print val
        }
      }
    }
  ' <<< "$cmd"
}

# Returns 0 (true) if the `pip install` command has inline package arguments or
# unsupported flags outside `-r <requirements-file>` and the allowed flag set.
has_inline_pip_args() {
  local cmd="$1"
  awk '
    function unquote(s) {
      sub(/^["'"'"']/, "", s)
      sub(/["'"'"']$/, "", s)
      return s
    }
    {
      sub(/^.*pip[0-9]*[[:space:]]+install([[:space:]]+|$)/, "")
      sub(/[;&|].*$/, "")
      n = split($0, tok, /[[:space:]]+/)
      bad = 0
      for (i = 1; i <= n; i++) {
        t = unquote(tok[i])
        if (t == "") continue
        if (t ~ /^(--require-hashes|-q|--quiet|-v|--verbose|--no-cache-dir|--disable-pip-version-check|--no-deps|--isolated|--no-input|--no-color|--prefer-binary|-U|--upgrade|--force-reinstall|--ignore-installed|--no-warn-script-location)$/) {
          continue
        }
        if (t == "--only-binary") {
          if (i + 1 <= n && unquote(tok[i + 1]) == ":all:") {
            i++
            continue
          }
          bad = 1
          break
        }
        if (t == "--only-binary=:all:") {
          continue
        }
        if (t == "-r" || t == "--requirement") {
          if (i + 1 <= n && unquote(tok[i + 1]) != "" && unquote(tok[i + 1]) !~ /^-/) {
            i++
            continue
          }
          bad = 1
          break
        }
        if (t ~ /^(-r|--requirement)=.+$/ || t ~ /^-r[^=].*$/) {
          continue
        }
        if (t ~ /^(--retries|--timeout|--index-url|--extra-index-url|--find-links|-f|--trusted-host|--target|-t|--root|--prefix|--cache-dir|--abi|--platform|--python-version|--implementation|--root-user-action)$/) {
          if (i + 1 <= n && unquote(tok[i + 1]) != "") {
            i++
            continue
          }
          bad = 1
          break
        }
        if (t ~ /^(--retries|--timeout|--index-url|--extra-index-url|--find-links|--trusted-host|--target|--root|--prefix|--cache-dir|--abi|--platform|--python-version|--implementation|--root-user-action)=.+$/) {
          continue
        }
        bad = 1
        break
      }
      exit (bad ? 0 : 1)
    }
  ' <<< "$cmd"
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
      sub(/[[:space:]]+#.*$/, "", line)
      has_cont = (line ~ /\\$/)
      if (has_cont) {
        sub(/[[:space:]]*\\$/, "", line)
      }

      if (in_cont) {
        if (line ~ /^[A-Za-z0-9._-]+(\[[A-Za-z0-9._,-]+\])?==/) {
          printf "expected --hash continuation before new package: %s\n", line
          bad = 1
          in_cont = has_cont
          next
        }
        n = split(line, htoks, /[[:space:]]+/)
        cont_ok = (n > 0)
        for (i = 1; i <= n; i++) {
          if (htoks[i] !~ /^--hash=sha256:[0-9a-fA-F]{64}$/) {
            cont_ok = 0
          } else {
            current_hashes++
          }
        }
        if (!cont_ok) {
          printf "unpinned or invalid requirement continuation line: %s\n", line
          bad = 1
        }
        in_cont = has_cont
        next
      }

      if (line ~ /^--hash=/) {
        printf "hash line without preceding backslash continuation: %s\n", line
        bad = 1
        next
      }

      if (pkg_count > 0 && current_hashes == 0) {
        printf "package %s is missing --hash=sha256:<64-hex>\n", current_pkg
        bad = 1
      }

      rest = line
      line_hashes = 0
      line_bad_hash = 0
      while (match(rest, /(^|[[:space:]])--hash=[^[:space:]]+/)) {
        hstart = RSTART
        hlen = RLENGTH
        htok = substr(rest, hstart, hlen)
        sub(/^[[:space:]]+/, "", htok)
        if (htok ~ /^--hash=sha256:[0-9a-fA-F]{64}$/) {
          line_hashes++
        } else {
          line_bad_hash = 1
        }
        rest = substr(rest, 1, hstart - 1) " " substr(rest, hstart + hlen)
      }

      sub(/^[[:space:]]+/, "", rest)
      sub(/[[:space:]]+$/, "", rest)

      line_bad_marker = 0
      semi = index(rest, ";")
      if (semi > 0) {
        marker = substr(rest, semi + 1)
        rest = substr(rest, 1, semi - 1)
        sub(/^[[:space:]]+/, "", marker)
        sub(/[[:space:]]+$/, "", marker)
        sub(/[[:space:]]+$/, "", rest)
        if (marker == "" || marker ~ /(^|[[:space:]])--/) {
          line_bad_marker = 1
        }
      }

      if (!line_bad_hash && !line_bad_marker &&
          rest ~ /^[A-Za-z0-9._-]+(\[[A-Za-z0-9._,-]+\])?==[0-9][0-9A-Za-z._+!-]*$/) {
        pkg_count++
        current_pkg = rest
        current_hashes = line_hashes
        in_cont = has_cont
      } else {
        printf "unpinned or invalid requirement line: %s\n", line
        bad = 1
        pkg_count++
        current_pkg = rest != "" ? rest : line
        current_hashes = (line_hashes > 0 ? line_hashes : 1)
        in_cont = has_cont
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
SCAN_DESC="$CI_FILE"
if [[ $# -eq 0 && -d ".github/workflows" ]]; then
  WORKFLOW_TARGETS=()
  for candidate in .github/workflows/*.yml .github/workflows/*.yaml; do
    [[ -f "$candidate" ]] && WORKFLOW_TARGETS+=("$candidate")
  done
  SCAN_DESC=".github/workflows/*.{yml,yaml}"
fi

PIP_LINES=()
for wf in "${WORKFLOW_TARGETS[@]}"; do
  [[ -f "$wf" ]] || continue
  while IFS= read -r pip_line; do
    [[ -n "$pip_line" ]] && PIP_LINES+=("${wf}:${pip_line}")
  done < <(collect_pip_lines_from_file "$wf")
done

echo "Check 1: at least one pip install step exists to validate"
if [[ ${#PIP_LINES[@]} -eq 0 ]]; then
  error "$SCAN_DESC has no 'pip install' step — expected the PyYAML install"
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
  cmd_req_files=()
  while IFS= read -r req_file; do
    [[ -n "$req_file" ]] && cmd_req_files+=("$req_file")
  done < <(extract_req_files "$cmd")
  if [[ ${#cmd_req_files[@]} -eq 0 ]]; then
    error "pip install missing '-r <requirements-file>': $entry"
  else
    REQ_FILES+=("${cmd_req_files[@]}")
  fi
  if has_inline_pip_args "$cmd"; then
    error "pip install has inline package or unsupported arguments outside '-r <requirements-file>': $entry"
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
