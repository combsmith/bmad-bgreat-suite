#!/usr/bin/env bash
# Validates that .github/workflows/pr-review.yml skips Dependabot-context events.
#
# Dependabot-triggered pull_request events run in a restricted secret context
# where the org PAT forwarded via `secrets: inherit` (DON_PETRY_BOT_GH_PAT_CLASSIC)
# is unavailable, so the reusable workflow's "Verify auth scopes" step fails and
# the run turns red (Fleet Monitor issue #398). This test asserts pr-review.yml
# carries a guard that skips them, in either accepted form:
#
#   - the org-standard actor form synced from
#     combsmith/.github standards/workflows/pr-review.yml:
#       if: ${{ github.actor != 'dependabot[bot]' }}
#     It skips events Dependabot itself triggers (the restricted-secret context)
#     and lets a human-triggered event on a Dependabot PR run with secrets.
#   - the stricter head-ref form this repo used before the template (#501):
#       if: "!startsWith(github.event.pull_request.head.ref, 'dependabot/')"
#
# pr-review.yml is a synced stub, so this guard must accept what the template
# ships rather than requiring a local divergence (issue #501).
#
# Usage: test-pr-review-dependabot-skip.sh [workflow-file]
#   (defaults to .github/workflows/pr-review.yml)
set -euo pipefail

ERRORS=0
WORKFLOW="${1:-.github/workflows/pr-review.yml}"

error() {
  echo "ERROR: $1" >&2
  ERRORS=$((ERRORS + 1))
}

echo "=== pr-review.yml — Dependabot skip guard check ==="
echo ""

if [[ ! -f "$WORKFLOW" ]]; then
  error "Missing $WORKFLOW"
  exit 1
fi

if ! command -v python3 > /dev/null 2>&1; then
  error "python3 is required but not installed."
  exit 1
fi

if ! python3 -c "import yaml" > /dev/null 2>&1; then
  error "Python 'pyyaml' package is required but not installed. Please install it (e.g., pip install pyyaml)."
  exit 1
fi

# Check 1: the review job declares an if: guard that skips Dependabot events.
# Dependabot-triggered events must not run the review job, otherwise the missing
# org secret makes the reusable workflow fail (see file header / issue #398).
echo "Check 1: review job skips Dependabot events via an if: guard"
if python3 - "$WORKFLOW" << 'PY'; then
import sys
import yaml

try:
    with open(sys.argv[1]) as fh:
        doc = yaml.safe_load(fh)
except yaml.YAMLError as e:
    print(f"Invalid YAML syntax: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(doc, dict):
    print("workflow did not parse to a mapping", file=sys.stderr)
    sys.exit(1)

jobs = doc.get("jobs")
if not isinstance(jobs, dict) or "review" not in jobs:
    print("workflow has no 'review' job", file=sys.stderr)
    sys.exit(1)

review = jobs["review"]
guard = review.get("if")
if guard is None:
    print(
        "review job has no 'if:' guard — Dependabot PR events run in a "
        "restricted secret context and fail 'Verify auth scopes' (issue #398). "
        "Add the org-standard guard: if: ${{ github.actor != 'dependabot[bot]' }}",
        file=sys.stderr,
    )
    sys.exit(1)

# Normalise whitespace and quotes so the assertion is robust to formatting.
normalised = "".join(str(guard).split()).replace('"', "'")

# Strip an optional ${{ }} wrapper, then require the guard to be a pure
# conjunction (&&) of terms where at least one term is exactly an accepted skip
# form. Substring matching is not enough: a negated or OR-ed expression could
# contain the expected text yet still let Dependabot jobs run.
expr = normalised
if expr.startswith("${{") and expr.endswith("}}"):
    expr = expr[3:-2]

head_ref = "startsWith(github.event.pull_request.head.ref,'dependabot/')"
accepted_terms = {
    "github.actor!='dependabot[bot]'",
    "'dependabot[bot]'!=github.actor",
    f"!{head_ref}",
    f"not({head_ref})",
}

if "||" in expr:
    terms = []
else:
    terms = expr.split("&&")

actor_skip = any(t in accepted_terms for t in terms)
head_ref_skip = actor_skip

if not (actor_skip or head_ref_skip):
    if head_ref in normalised:
        print(
            "review job 'if:' guard does not NEGATE the dependabot head.ref check "
            "— Dependabot PRs would still run and fail",
            file=sys.stderr,
        )
    else:
        print(
            "review job 'if:' guard does not skip Dependabot events — expected "
            "github.actor != 'dependabot[bot]' (org standard) or "
            "!startsWith(github.event.pull_request.head.ref, 'dependabot/')",
            file=sys.stderr,
        )
    sys.exit(1)
PY
  echo "  done."
else
  error "pr-review.yml validation failed"
fi

echo ""
if [[ "$ERRORS" -gt 0 ]]; then
  echo "pr-review Dependabot skip guard check failed with $ERRORS error(s)" >&2
  exit 1
else
  echo "pr-review Dependabot skip guard check passed"
  exit 0
fi
