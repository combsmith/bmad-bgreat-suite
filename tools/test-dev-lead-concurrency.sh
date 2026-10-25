#!/usr/bin/env bash
# Validates that .github/workflows/dev-lead.yml complies with the canonical org
# thin-caller-stub contract (combsmith/.github/standards/ci-standards.md#5-dev-lead-agent,
# combsmith/.github#402, Fleet Monitor issue #513):
#   1. Parses as valid YAML and declares NO caller-level or job-level concurrency
#      block (concurrency is centralised in dev-lead-reusable.yml with per-issue /
#      per-PR lanes so follow-up events do not cancel unrelated runs).
#   2. Uses canonical workflow name "Dev-Lead Agent" and top-level permissions: {}.
#   3. Preserves the exact org-standard on: trigger surface (pull_request on main,
#      pull_request_review, pull_request_review_comment, issue_comment, issues,
#      check_run, repository_dispatch).
#   4. Delegates jobs.dev-lead to combsmith/.github-private/.github/workflows/dev-lead-reusable.yml
#      pinned to dev-lead/v<N>-ring1 with with.agent_ref in lockstep, secrets: inherit
#      (so CLAUDE_CODE_OAUTH_TOKEN and optional secrets reach the reusable workflow,
#      preventing token-preflight dispatch failures tracked in #513), no inline steps
#      or extra job keys, and inline # NOSONAR(githubactions:S7637) /
#      # NOSONAR(githubactions:S7635) markers on the directive lines.
#   5. Grants the exact required job-level GITHUB_TOKEN permissions scopes.
#
# Usage: test-dev-lead-concurrency.sh [workflow-file]
#   (defaults to .github/workflows/dev-lead.yml)
set -euo pipefail

ERRORS=0
WORKFLOW="${1:-${WORKFLOW:-.github/workflows/dev-lead.yml}}"
readonly DONE_MARK="  done."

# Record a validation error message to stderr and increment ERRORS.
# Arguments:
#   $1 - Error message to report.
error() {
  local msg="$1"
  echo "ERROR: $msg" >&2
  ERRORS=$((ERRORS + 1))
  return 0
}

echo "=== dev-lead.yml — thin caller stub & concurrency guard check ==="
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
# or job-level concurrency block. Since combsmith/.github#402, concurrency lives
# in the reusable workflow. A caller-level block would override the reusable's
# per-lane grouping and re-introduce API-quota exhaustion (HTTP 429) or cross-lane
# cancellations.
echo "Check 1: no top-level or job-level concurrency block (concurrency is in the reusable)"
if python3 - "$WORKFLOW" << 'PY'; then
import sys
import yaml

try:
    with open(sys.argv[1]) as fh:
        doc = yaml.safe_load(fh)
except (yaml.YAMLError, OSError) as e:
    print(f"Invalid YAML syntax: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(doc, dict):
    print("workflow did not parse to a mapping", file=sys.stderr)
    sys.exit(1)

if doc.get("concurrency") is not None:
    print(
        "top-level 'concurrency:' key found — remove it; concurrency is "
        "centralised in the reusable workflow (combsmith/.github#402)",
        file=sys.stderr,
    )
    sys.exit(1)

jobs = doc.get("jobs")
if isinstance(jobs, dict):
    for job_name, job_cfg in jobs.items():
        if isinstance(job_cfg, dict) and job_cfg.get("concurrency") is not None:
            print(
                f"job '{job_name}' declares a 'concurrency:' key — remove it; "
                "concurrency is centralised in the reusable workflow (combsmith/.github#402)",
                file=sys.stderr,
            )
            sys.exit(1)
PY
  echo "$DONE_MARK"
else
  error "$WORKFLOW has a concurrency block or invalid YAML that must be fixed"
fi

# Check 2: canonical workflow name ("Dev-Lead Agent"), top-level permissions: {},
# and no unexpected top-level keys.
echo ""
echo "Check 2: $WORKFLOW declares canonical name 'Dev-Lead Agent' and top-level permissions: {}"
if python3 - "$WORKFLOW" << 'PY'; then
import sys
import yaml

try:
    with open(sys.argv[1]) as fh:
        doc = yaml.safe_load(fh)
except (yaml.YAMLError, OSError):
    sys.exit(1)

if not isinstance(doc, dict):
    sys.exit(1)

normalized_keys = {"on" if k is True else k for k in doc.keys()}
expected_top_keys = {"name", "on", "permissions", "jobs"}
if normalized_keys != expected_top_keys:
    print(
        f"unexpected top-level keys: expected {sorted(expected_top_keys)}, got {sorted(str(k) for k in normalized_keys)}",
        file=sys.stderr,
    )
    sys.exit(1)

if doc.get("name") != "Dev-Lead Agent":
    print(
        f"expected workflow name 'Dev-Lead Agent', got {doc.get('name')!r}",
        file=sys.stderr,
    )
    sys.exit(1)

top_perms = doc.get("permissions")
if not isinstance(top_perms, dict) or len(top_perms) != 0:
    print(
        f"expected top-level 'permissions: {{}}', got {top_perms!r}",
        file=sys.stderr,
    )
    sys.exit(1)
PY
  echo "$DONE_MARK"
else
  error "$WORKFLOW does not declare canonical name 'Dev-Lead Agent' and top-level 'permissions: {}'"
fi

# Check 3: canonical on: trigger surface (not repo-adjustable per ci-standards.md).
echo ""
echo "Check 3: $WORKFLOW preserves the canonical on: trigger surface"
if python3 - "$WORKFLOW" << 'PY'; then
import sys
import yaml

EXPECTED_ON = {
    "pull_request": {
        "branches": ["main"],
        "types": ["opened", "reopened", "synchronize"],
    },
    "pull_request_review": {"types": ["submitted"]},
    "pull_request_review_comment": {"types": ["created"]},
    "issue_comment": {"types": ["created"]},
    "issues": {"types": ["labeled"]},
    "check_run": {"types": ["completed"]},
    "repository_dispatch": {
        "types": [
            "dev-lead-ci-failure",
            "dev-lead-reviews-retry",
            "dev-lead-issue-retry",
        ]
    },
}

try:
    with open(sys.argv[1]) as fh:
        doc = yaml.safe_load(fh)
except (yaml.YAMLError, OSError):
    sys.exit(1)

if not isinstance(doc, dict):
    sys.exit(1)

on_block = doc.get("on") if "on" in doc else doc.get(True)
if not isinstance(on_block, dict):
    print("missing or invalid 'on:' trigger mapping", file=sys.stderr)
    sys.exit(1)

if set(on_block.keys()) != set(EXPECTED_ON.keys()):
    missing = sorted(set(EXPECTED_ON.keys()) - set(on_block.keys()))
    extra = sorted(set(on_block.keys()) - set(EXPECTED_ON.keys()))
    print(
        f"on: trigger keys drifted from canonical stub (missing={missing}, extra={extra})",
        file=sys.stderr,
    )
    sys.exit(1)

for trig, expected_cfg in EXPECTED_ON.items():
    actual_cfg = on_block.get(trig)
    if actual_cfg != expected_cfg:
        print(
            f"on.{trig} drifted: expected {expected_cfg!r}, got {actual_cfg!r}",
            file=sys.stderr,
        )
        sys.exit(1)
PY
  echo "$DONE_MARK"
else
  error "$WORKFLOW on: triggers drifted from the canonical Dev-Lead caller stub"
fi

# Check 4: jobs.dev-lead delegates to dev-lead-reusable.yml@dev-lead/v<N>-ring1
# with agent_ref in lockstep, secrets: inherit, no inline steps, and NOSONAR markers.
echo ""
echo "Check 4: $WORKFLOW delegates to dev-lead-reusable.yml with agent_ref in lockstep and secrets: inherit"
if python3 - "$WORKFLOW" << 'PY'; then
import re
import sys
import yaml

REUSABLE_PREFIX = "combsmith/.github-private/.github/workflows/dev-lead-reusable.yml@"
CHANNEL_RE = re.compile(r"^dev-lead/v[0-9]+-ring1$")
USES_LINE_RE = re.compile(
    r"^\s*uses:\s*"
    + re.escape(REUSABLE_PREFIX)
    + r"dev-lead/v[0-9]+-ring1\s+#\s*NOSONAR\(githubactions:S7637\)"
)
SECRETS_LINE_RE = re.compile(
    r"^\s*secrets:\s*inherit\s+#\s*NOSONAR\(githubactions:S7635\)"
)

try:
    with open(sys.argv[1]) as fh:
        raw = fh.read()
    doc = yaml.safe_load(raw)
except (yaml.YAMLError, OSError):
    sys.exit(1)

if not isinstance(doc, dict):
    sys.exit(1)

jobs = doc.get("jobs")
if not isinstance(jobs, dict) or set(jobs.keys()) != {"dev-lead"}:
    print(
        f"expected jobs mapping with sole job 'dev-lead', got {list(jobs.keys()) if isinstance(jobs, dict) else jobs!r}",
        file=sys.stderr,
    )
    sys.exit(1)

job = jobs["dev-lead"]
if not isinstance(job, dict):
    print("jobs.dev-lead must be a mapping", file=sys.stderr)
    sys.exit(1)

uses = str(job.get("uses", ""))
if not uses.startswith(REUSABLE_PREFIX):
    print(
        f"jobs.dev-lead.uses must start with '{REUSABLE_PREFIX}', got {uses!r}",
        file=sys.stderr,
    )
    sys.exit(1)

channel = uses.split("@", 1)[1]
if not CHANNEL_RE.match(channel):
    print(
        f"jobs.dev-lead.uses channel must match 'dev-lead/v<N>-ring1' for this ring1 repo, got {channel!r}",
        file=sys.stderr,
    )
    sys.exit(1)

with_block = job.get("with")
if not isinstance(with_block, dict) or with_block.get("agent_ref") != channel or set(with_block.keys()) != {"agent_ref"}:
    print(
        f"jobs.dev-lead.with must be {{'agent_ref': {channel!r}}} in lockstep with uses:, got {with_block!r}",
        file=sys.stderr,
    )
    sys.exit(1)

if job.get("secrets") != "inherit":
    print(
        f"jobs.dev-lead.secrets must be 'inherit' so CLAUDE_CODE_OAUTH_TOKEN reaches dev-lead-reusable (#513), got {job.get('secrets')!r}",
        file=sys.stderr,
    )
    sys.exit(1)

if "steps" in job:
    print(
        "jobs.dev-lead must not define inline 'steps:' (thin caller stub delegates all execution to the reusable)",
        file=sys.stderr,
    )
    sys.exit(1)

expected_job_keys = {"uses", "with", "secrets", "permissions"}
if set(job.keys()) != expected_job_keys:
    extra_keys = sorted(set(job.keys()) - expected_job_keys)
    missing_keys = sorted(expected_job_keys - set(job.keys()))
    print(
        f"jobs.dev-lead keys drifted (missing={missing_keys}, extra={extra_keys})",
        file=sys.stderr,
    )
    sys.exit(1)

has_s7637 = any(USES_LINE_RE.match(line) for line in raw.splitlines())
has_s7635 = any(SECRETS_LINE_RE.match(line) for line in raw.splitlines())
if not has_s7637:
    print("missing inline '# NOSONAR(githubactions:S7637)' marker on jobs.dev-lead.uses line", file=sys.stderr)
    sys.exit(1)
if not has_s7635:
    print("missing inline '# NOSONAR(githubactions:S7635)' marker on jobs.dev-lead.secrets line", file=sys.stderr)
    sys.exit(1)
PY
  echo "$DONE_MARK"
else
  error "$WORKFLOW jobs.dev-lead reusable delegation, agent_ref lockstep, secrets: inherit, or NOSONAR markers failed validation"
fi

# Check 5: jobs.dev-lead.permissions grants the exact required GITHUB_TOKEN scopes.
echo ""
echo "Check 5: $WORKFLOW grants exact required jobs.dev-lead.permissions scopes"
if python3 - "$WORKFLOW" << 'PY'; then
import sys
import yaml

EXPECTED_PERMISSIONS = {
    "contents": "write",
    "pull-requests": "write",
    "issues": "write",
    "actions": "read",
    "checks": "read",
    "statuses": "read",
}

try:
    with open(sys.argv[1]) as fh:
        doc = yaml.safe_load(fh)
except (yaml.YAMLError, OSError):
    sys.exit(1)

if not isinstance(doc, dict):
    sys.exit(1)

jobs = doc.get("jobs") if isinstance(doc.get("jobs"), dict) else {}
job = jobs.get("dev-lead") if isinstance(jobs.get("dev-lead"), dict) else {}
perms = job.get("permissions")

if perms != EXPECTED_PERMISSIONS:
    print(
        f"jobs.dev-lead.permissions drifted: expected {EXPECTED_PERMISSIONS!r}, got {perms!r}",
        file=sys.stderr,
    )
    sys.exit(1)
PY
  echo "$DONE_MARK"
else
  error "$WORKFLOW jobs.dev-lead.permissions drifted from canonical caller stub"
fi

echo ""
if [[ "$ERRORS" -gt 0 ]]; then
  echo "dev-lead concurrency guard check failed with $ERRORS error(s)" >&2
  exit 1
else
  echo "dev-lead concurrency guard check passed"
  exit 0
fi
