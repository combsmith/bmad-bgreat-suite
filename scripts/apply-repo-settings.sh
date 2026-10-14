#!/usr/bin/env bash
set -euo pipefail
# apply-repo-settings.sh — Apply standard GitHub repository settings.
#
# Usage: bash scripts/apply-repo-settings.sh [repo]
#   repo  Repository name (e.g. "bmad-bgreat-suite" or "owner/repo").
#         Defaults to $GITHUB_REPOSITORY.
#
# Requires: gh CLI authenticated with a token that has admin:repo scope.

REPO="${1:-${GITHUB_REPOSITORY:-}}"

if [ -z "$REPO" ]; then
  echo "::error::Repository name required. Pass as argument or set GITHUB_REPOSITORY." >&2
  exit 1
fi

# Normalise to owner/repo form.
if [[ "$REPO" != */* ]]; then
  REPO="combsmith/$REPO"
fi

echo "Applying repository settings to ${REPO}..."

# ── Check-suite auto-trigger ──────────────────────────────────────────────────
# Disable auto-trigger for apps that enqueue phantom check suites on every push
# but never complete them, permanently blocking auto-merge:
#   - Claude GitHub App (ID 1236702)
#   - CodeRabbit (ID 347564)
gh api \
  --method PATCH \
  --header "Accept: application/vnd.github+json" \
  "/repos/${REPO}/check-suites/preferences" \
  --input - <<'JSON'
{"auto_trigger_checks":[{"app_id":1236702,"setting":false},{"app_id":347564,"setting":false}]}
JSON

echo "Done: disabled check-suite auto-trigger for Claude app (1236702) and CodeRabbit (347564) on ${REPO} [compliance: check-suite-auto-trigger-1236702, check-suite-auto-trigger-347564]."

# ── Secret scanning (baseline: push protection) ──────────────────────────────
# Enables baseline secret scanning with push protection, which prevents committing
# secrets to the repository. This is available for most repositories.
# Note: These settings may be unavailable for private repositories without GitHub Advanced Security.
if gh api \
  --method PATCH \
  --header "Accept: application/vnd.github+json" \
  "/repos/${REPO}" \
  --input - <<'JSON' 2>/dev/null; then
{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}
JSON
  echo "Done: enabled secret_scanning and secret_scanning_push_protection on ${REPO}."
else
  echo "Warning: secret_scanning baseline settings are unavailable for ${REPO} (possibly a private repository without GitHub Advanced Security)."
fi

# ── Secret scanning (advanced: AI detection + non-provider patterns) ──────────
# Enables GitHub's AI model for surfacing additional potential secrets beyond
# built-in patterns, plus detection of secrets matching custom/internal pattern
# sets via generic detectors. This may not be available for all repositories.
if gh api \
  --method PATCH \
  --header "Accept: application/vnd.github+json" \
  "/repos/${REPO}" \
  --input - <<'JSON' 2>/dev/null; then
{"security_and_analysis":{"secret_scanning_ai_detection":{"status":"enabled"},"secret_scanning_non_provider_patterns":{"status":"enabled"}}}
JSON
  echo "Done: enabled secret_scanning_ai_detection and secret_scanning_non_provider_patterns on ${REPO}."
else
  echo "Warning: advanced secret_scanning settings are unavailable for ${REPO}."
fi

# ── CodeQL default setup ──────────────────────────────────────────────────────
# Enables GitHub-managed CodeQL scanning (default setup) with the default query
# suite. Default setup auto-detects languages and manages analyzer versions,
# eliminating per-repo codeql.yml maintenance.
gh api \
  --method PATCH \
  --header "Accept: application/vnd.github+json" \
  "/repos/${REPO}/code-scanning/default-setup" \
  --input - <<'JSON'
{"state":"configured","query_suite":"default"}
JSON

echo "Done: enabled CodeQL default setup on ${REPO}."

# ── Delete branch on merge ────────────────────────────────────────────────────
# Automatically delete head branches after a pull request is merged, keeping
# the branch list tidy and matching the org standard.
gh api \
  --method PATCH \
  --header "Accept: application/vnd.github+json" \
  "/repos/${REPO}" \
  --input - <<'JSON'
{"delete_branch_on_merge":true}
JSON

echo "Done: enabled delete_branch_on_merge on ${REPO}."

# ── Dependabot vulnerability alerts ──────────────────────────────────────────
# Enable Dependabot vulnerability alerts. Available for all repositories.
if gh api \
  --method PUT \
  --header "Accept: application/vnd.github+json" \
  "/repos/${REPO}/vulnerability-alerts" 2>/dev/null; then
  echo "Done: enabled vulnerability-alerts on ${REPO}."
else
  echo "Warning: failed to enable vulnerability-alerts on ${REPO}." >&2
fi

# ── Dependabot automated security fixes ───────────────────────────────────────
# Enable Dependabot to automatically create pull requests for security updates.
# Available for all repositories.
if gh api \
  --method PUT \
  --header "Accept: application/vnd.github+json" \
  "/repos/${REPO}/automated-security-fixes" 2>/dev/null; then
  echo "Done: enabled automated-security-fixes on ${REPO}."
else
  echo "Warning: failed to enable automated-security-fixes on ${REPO}." >&2
fi
