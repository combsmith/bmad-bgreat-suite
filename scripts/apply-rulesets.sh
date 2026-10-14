#!/usr/bin/env bash
set -euo pipefail
# apply-rulesets.sh — codified, idempotent application of the org compliance rulesets.
#
# Vendored from the canonical org tooling (combsmith/.github#580 / #575). Reads
# the codified source of truth in standards/rulesets/*.json and creates/updates the
# named ruleset on the target repo. Re-running converges to the file's desired state
# (a no-op when already in sync), so drift such as
# ruleset-drift-pr-quality-dismiss_stale_reviews_on_push self-heals on each merge.
#
# Rulesets live ON each repo: editing a JSON here changes the desired state, not any
# live ruleset, until this applier runs.
#
# Default set: with NO ruleset name, only the FLEET_RULESETS allowlist is applied.
# Pass explicit names to apply a subset (e.g. `--repo owner/repo pr-quality`).
#
# Usage:
#   GH_TOKEN=<admin> ./scripts/apply-rulesets.sh --repo owner/repo [--dry-run] [<name>...]
#   GH_TOKEN=<admin> ./scripts/apply-rulesets.sh <repo-name>       [--dry-run]   # bare name → $ORG/<name>
#
# Env:
#   GH_TOKEN       token with administration:write on the target repo (required for writes)
#   ORG            org for bare repo names (default: combsmith)
#   RULESETS_DIR   directory of ruleset JSONs (default: <repo-root>/standards/rulesets)
#   DRY_RUN        "true" → print intent, make no write calls

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ORG="${ORG:-combsmith}"
RULESETS_DIR="${RULESETS_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)/standards/rulesets}"
DRY_RUN="${DRY_RUN:-false}"

# The fleet-wide compliance rulesets applied by DEFAULT (when no ruleset name is
# given). This is an ALLOWLIST, not "every *.json in the dir".
readonly FLEET_RULESETS=(pr-quality)

# ruleset_id_by_name <repo> <name> — echo the id of an existing ruleset, or empty.
ruleset_id_by_name() {
  local repo="$1" name="$2"
  local output rc=0
  output=$(gh api --paginate "repos/${repo}/rulesets?includes_parents=false" 2>/dev/null) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "::error::failed to fetch rulesets for ${repo} (exit code ${rc})" >&2
    return "$rc"
  fi
  echo "$output" | jq -r --arg n "$name" --arg r "$repo" 'if type=="array" then .[] else . end | select(.name == $n and .source_type == "Repository" and .source == $r) | .id'
}

# apply_one <repo> <json_file> — create or update the ruleset described by json_file.
apply_one() {
  local repo="$1" file="$2"
  local name id id_rc=0
  name="$(jq -r '.name' "$file")"
  [[ -n "$name" && "$name" != "null" ]] || { echo "::error::$file has no .name" >&2; return 1; }
  id="$(ruleset_id_by_name "$repo" "$name")" && id_rc=0 || id_rc=$?
  if [[ "$id_rc" -ne 0 ]]; then
    echo "::error::failed to resolve ruleset ID for '${name}' on ${repo}" >&2
    return "$id_rc"
  fi

  if [[ -n "$id" ]]; then
    echo "  update ruleset '${name}' (id ${id}) on ${repo}"
    if [[ "$DRY_RUN" == "true" ]]; then echo "    [dry-run] PUT repos/${repo}/rulesets/${id}"; return 0; fi
    gh api --method PUT "repos/${repo}/rulesets/${id}" --input "$file" >/dev/null || {
      echo "::error::API request failed" >&2
      return 1
    }
  else
    echo "  create ruleset '${name}' on ${repo}"
    if [[ "$DRY_RUN" == "true" ]]; then echo "    [dry-run] POST repos/${repo}/rulesets"; return 0; fi
    gh api --method POST "repos/${repo}/rulesets" --input "$file" >/dev/null || {
      echo "::error::API request failed" >&2
      return 1
    }
  fi
  return 0
}

# apply_repo <repo> <file...> — apply each ruleset file to one repo.
apply_repo() {
  local repo="$1"; shift
  echo "[apply-rulesets] repo=${repo} dir=${RULESETS_DIR} dry_run=${DRY_RUN}"
  local file rc=0
  for file in "$@"; do
    apply_one "$repo" "$file" || rc=$?
  done
  return "$rc"
}

# resolve_repo <arg> — echo owner/repo: pass through an owner/repo, else prefix $ORG.
resolve_repo() {
  local arg="$1"
  case "$arg" in */*) printf '%s' "$arg" ;; *) printf '%s/%s' "$ORG" "$arg" ;; esac
}

main() {
  local target=""
  local names=()
  while [[ $# -gt 0 ]]; do
    local arg="$1"
    case "$arg" in
      --repo)
        [[ "$#" -ge 2 ]] || { echo "::error::--repo requires a value" >&2; return 2; }
        local value="$2"
        [[ "$value" != --* ]] || { echo "::error::--repo requires a repository value, not a flag: $value" >&2; return 2; }
        target="$value"; shift 2 ;;
      --dry-run) DRY_RUN=true; shift ;;
      --*)       echo "::error::unknown flag: $arg" >&2; return 2 ;;
      *)
        # A bare token is the target repo unless --repo already set it, in which case
        # remaining bare tokens filter which ruleset names to apply.
        if [[ -z "$target" ]]; then target="$arg"; else names+=("$arg"); fi
        shift ;;
    esac
  done

  gh auth status >/dev/null 2>&1 || { echo "::error::GitHub authentication failed — set GH_TOKEN or run 'gh auth login'" >&2; return 1; }
  [[ -d "$RULESETS_DIR" ]] || { echo "::error::rulesets dir not found: $RULESETS_DIR" >&2; return 1; }
  [[ -n "$target" ]] || { echo "::error::usage: $0 --repo owner/repo | <repo-name> [--dry-run] [<name>...]" >&2; return 2; }

  # Select the ruleset files: the named ones, else the fleet allowlist.
  local files=()
  if [[ "${#names[@]}" -eq 0 ]]; then names=("${FLEET_RULESETS[@]}"); fi
  local n
  for n in "${names[@]}"; do
    if [[ -f "${RULESETS_DIR}/${n}.json" ]]; then
      files+=("${RULESETS_DIR}/${n}.json")
    else
      echo "::error::no ruleset file ${n}.json in ${RULESETS_DIR}" >&2
      return 1
    fi
  done
  [[ "${#files[@]}" -gt 0 ]] || { echo "  no ruleset files to apply"; return 0; }

  apply_repo "$(resolve_repo "$target")" "${files[@]}"
  echo "[apply-rulesets] done (${#files[@]} ruleset(s))"
}

# Source-guard: tests source this to exercise ruleset_id_by_name / apply_one.
if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  main "$@"
fi
