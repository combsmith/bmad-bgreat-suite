#!/usr/bin/env bash
# Validates that .github/workflows/copilot-setup-steps.yml contains a job named
# exactly `copilot-setup-steps`. GitHub's Copilot cloud agent only picks up the
# file when this exact job name is present; a missing/renamed job silently
# disables the bootstrap. The org weekly compliance audit flags this as the
# `copilot-setup-steps-invalid-job-name` error — this guard catches a regression
# in PR CI instead of waiting for the next audit.
#
# Detection mirrors the org audit (combsmith/.github
# scripts/compliance-audit.sh): an indentation-based parser, not a loose grep,
# so comments or similarly named keys elsewhere cannot falsely satisfy it.
set -euo pipefail

WORKFLOW=".github/workflows/copilot-setup-steps.yml"

echo "=== copilot-setup-steps.yml — required job name check ==="

if [[ ! -f "$WORKFLOW" ]]; then
  echo "ERROR: Missing $WORKFLOW" >&2
  exit 1
fi

if python3 - "$WORKFLOW" <<'PY'
import re
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    lines = f.read().splitlines()
jobs_indent = None
child_indent = None
in_jobs = False
found = False

for raw in lines:
    # Skip empty lines and comments
    if re.match(r"^[ \t]*(#.*)?$", raw):
        continue

    indent = len(raw) - len(raw.lstrip(" \t"))
    line = raw.strip()

    if not in_jobs:
        if re.match(r"^jobs:[ \t]*(#.*)?$", line):
            in_jobs = True
            jobs_indent = indent
        continue

    # Left the jobs section
    if indent <= jobs_indent:
        break

    # Determine direct-child indentation under jobs (first mapping key)
    if child_indent is None and re.match(r"^[^:#][^:]*:[ \t]*(#.*)?$", line):
        child_indent = indent

    # Match the exact required direct child key (quoted or unquoted YAML key)
    if child_indent is not None and indent == child_indent and re.match(r"^[\"']?copilot-setup-steps[\"']?:[ ]*(#.*)?$", line):
        found = True
        break

sys.exit(0 if found else 1)
PY
then
  echo "  done. Job 'copilot-setup-steps' is present."
  exit 0
else
  echo "ERROR: $WORKFLOW does not contain a job named 'copilot-setup-steps' —" \
       "GitHub requires this exact job name to pick up the file." >&2
  exit 1
fi
