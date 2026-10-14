#!/usr/bin/env bash
# Validates that .github/workflows/dev-lead.yml does NOT declare a top-level
# concurrency block. Since combsmith/.github#402, concurrency is centralised
# in the reusable workflow (dev-lead-reusable.yml) with per-issue / per-PR lanes.
# A local concurrency block in the caller would override the reusable's lanes and
# re-introduce the serialisation problems fixed by #402.
set -euo pipefail

ERRORS=0
WORKFLOW=".github/workflows/dev-lead.yml"

error() {
  echo "ERROR: $1" >&2
  ERRORS=$((ERRORS + 1))
}

echo "=== dev-lead.yml — concurrency guard check ==="
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

# Check 1: the workflow parses as valid YAML and does NOT declare a top-level
# concurrency block. Since combsmith/.github#402, concurrency lives in the
# reusable workflow. A caller-level block would override the reusable's per-lane
# grouping and re-introduce API-quota exhaustion (HTTP 429).
echo "Check 1: no top-level concurrency block (concurrency is in the reusable)"
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

concurrency = doc.get("concurrency")
if concurrency is not None:
    print(
        "top-level 'concurrency:' key found — remove it; concurrency is "
        "centralised in the reusable workflow (combsmith/.github#402)",
        file=sys.stderr,
    )
    sys.exit(1)
PY
  echo "  done."
else
  error "dev-lead.yml has a top-level concurrency block that must be removed"
fi

echo ""
if [[ "$ERRORS" -gt 0 ]]; then
  echo "dev-lead concurrency guard check failed with $ERRORS error(s)" >&2
  exit 1
else
  echo "dev-lead concurrency guard check passed"
  exit 0
fi
