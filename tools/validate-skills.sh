#!/usr/bin/env bash
# Skill Validator for BMad BGreat Suite
# Runs deterministic structural checks on all skills and workflows.
# Exit 0 = all checks pass, Exit 1 = failures found.
set -euo pipefail

ERRORS=0
SRC="src"
readonly DONE_MARK="  done."

error() {
  local msg="$1"
  echo "ERROR: $msg" >&2
  ERRORS=$((ERRORS + 1))
}

echo "=== BMad BGreat Suite — Skill Validator ==="
echo ""

# ---------------------------------------------------------------------------
# Check 0: Required root-level files and directories exist
# (mirrors ci.yml "Validate module structure" checks at lines 41-56)
# ---------------------------------------------------------------------------
echo "Check 0: Required root-level files and directories exist"
for f in "$SRC/module.yaml" "$SRC/module-help.csv"; do
  if [[ ! -f "$f" ]]; then
    error "Missing required file: $f"
  fi
done
if [[ ! -d "$SRC/agents" ]]; then
  error "Missing required directory: $SRC/agents/"
fi
if [[ ! -d "$SRC/workflows" ]]; then
  error "Missing required directory: $SRC/workflows/"
fi
echo "$DONE_MARK"

# ---------------------------------------------------------------------------
# Check 1: Every workflow directory has SKILL.md and bmad-skill-manifest.yaml
# ---------------------------------------------------------------------------
echo "Check 1: Workflow directories have SKILL.md and bmad-skill-manifest.yaml"
for dir in "$SRC"/workflows/*/; do
  [[ -d "$dir" ]] || continue
  name=$(basename "$dir")
  if [[ ! -f "$dir/SKILL.md" ]]; then
    error "Missing SKILL.md in workflows/$name"
  fi
  if [[ ! -f "$dir/bmad-skill-manifest.yaml" ]]; then
    error "Missing bmad-skill-manifest.yaml in workflows/$name"
  fi
done
echo "$DONE_MARK"

# ---------------------------------------------------------------------------
# Check 2: Every workflow directory has workflow.md
# ---------------------------------------------------------------------------
echo "Check 2: Workflow directories have workflow.md"
for dir in "$SRC"/workflows/*/; do
  [[ -d "$dir" ]] || continue
  name=$(basename "$dir")
  if [[ ! -f "$dir/workflow.md" ]]; then
    error "Missing workflow.md in workflows/$name"
  fi
done
echo "$DONE_MARK"

# ---------------------------------------------------------------------------
# Check 3: Every workflow directory has a steps/ directory with at least step-01-init.md
# ---------------------------------------------------------------------------
echo "Check 3: Workflow directories have steps/step-01-init.md"
for dir in "$SRC"/workflows/*/; do
  [[ -d "$dir" ]] || continue
  name=$(basename "$dir")
  if [[ ! -d "$dir/steps" ]]; then
    error "Missing steps/ directory in workflows/$name"
  elif [[ ! -f "$dir/steps/step-01-init.md" ]]; then
    error "Missing steps/step-01-init.md in workflows/$name"
  fi
done
echo "$DONE_MARK"

# ---------------------------------------------------------------------------
# Check 4: Every workflow directory has a templates/ directory with at least one template
# ---------------------------------------------------------------------------
echo "Check 4: Workflow directories have templates/ with at least one file"
for dir in "$SRC"/workflows/*/; do
  [[ -d "$dir" ]] || continue
  name=$(basename "$dir")
  if [[ ! -d "$dir/templates" ]]; then
    error "Missing templates/ directory in workflows/$name"
  else
    count=$(find "$dir/templates" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
    if [[ "$count" -eq 0 ]]; then
      error "No template files found in workflows/$name/templates/"
    fi
  fi
done
echo "$DONE_MARK"

# ---------------------------------------------------------------------------
# Check 5: Step files follow naming convention (step-NN-*.md or step-NNb-*.md)
# ---------------------------------------------------------------------------
echo "Check 5: Step file naming convention"
for dir in "$SRC"/workflows/*/steps; do
  [[ -d "$dir" ]] || continue
  wf_name=$(basename "$(dirname "$dir")")
  for file in "$dir"/*; do
    [[ -f "$file" ]] || continue
    fname=$(basename "$file")
    if ! echo "$fname" | grep -qE '^step-[0-9]{2}[a-z]?-[A-Za-z0-9._-]+\.md$'; then
      error "Invalid step file name '$fname' in workflows/$wf_name/steps/ (expected step-NN-*.md or step-NNb-*.md)"
    fi
  done
done
echo "$DONE_MARK"

# ---------------------------------------------------------------------------
# Check 6: All relative path references in step files resolve to real files
# ---------------------------------------------------------------------------
echo "Check 6: Relative path references resolve to real files"
for dir in "$SRC"/workflows/*/; do
  [[ -d "$dir" ]] || continue
  wf_name=$(basename "$dir")

  # Check workflow.md for ./steps/ and ./templates/ references
  if [[ -f "$dir/workflow.md" ]]; then
    while IFS= read -r ref; do
      target="$dir/$ref"
      if [[ ! -f "$target" ]]; then
        error "Broken reference '$ref' in workflows/$wf_name/workflow.md (file not found: $target)"
      fi
    done < <(grep -oE '\./steps/[A-Za-z0-9._-]+\.md|\./templates/[A-Za-z0-9._-]+\.md' "$dir/workflow.md" 2>/dev/null || true)
  fi

  # Check step files for ../templates/ and ../../../templates/ references
  for stepfile in "$dir"/steps/*.md; do
    [[ -f "$stepfile" ]] || continue
    step_fname=$(basename "$stepfile")
    while IFS= read -r ref; do
      resolved=$(cd "$dir/steps" && realpath -q "$ref" 2>/dev/null || echo "")
      if [[ -z "$resolved" ]] || [[ ! -f "$resolved" ]]; then
        error "Broken reference '$ref' in workflows/$wf_name/steps/$step_fname (file not found)"
      fi
    done < <(grep -oE '\.\./templates/[A-Za-z0-9._-]+\.md|\.\./\.\./\.\./templates/[A-Za-z0-9._-]+\.md' "$stepfile" 2>/dev/null || true)
  done
done
echo "$DONE_MARK"

# ---------------------------------------------------------------------------
# Check 7: All templates have required frontmatter fields (status, stepsCompleted)
# ---------------------------------------------------------------------------
echo "Check 7: Template frontmatter required fields"
for dir in "$SRC"/workflows/*/templates; do
  [[ -d "$dir" ]] || continue
  wf_name=$(basename "$(dirname "$dir")")
  for tmpl in "$dir"/*.md; do
    [[ -f "$tmpl" ]] || continue
    tmpl_name=$(basename "$tmpl")
    first_line=$(head -1 "$tmpl")
    if [[ "$first_line" = "---" ]]; then
      frontmatter=$(awk 'BEGIN{f=0} /^---$/{f++; next} f==1{print} f>=2{exit}' "$tmpl")
      if ! echo "$frontmatter" | grep -q '^status:'; then
        error "Missing 'status' in frontmatter of workflows/$wf_name/templates/$tmpl_name"
      fi
      if ! echo "$frontmatter" | grep -q '^stepsCompleted:'; then
        error "Missing 'stepsCompleted' in frontmatter of workflows/$wf_name/templates/$tmpl_name"
      fi
    fi
  done
done
# Also check shared templates
for tmpl in "$SRC"/templates/*.md; do
  [[ -f "$tmpl" ]] || continue
  tmpl_name=$(basename "$tmpl")
  first_line=$(head -1 "$tmpl")
  if [[ "$first_line" = "---" ]]; then
    frontmatter=$(awk 'BEGIN{f=0} /^---$/{f++; next} f==1{print} f>=2{exit}' "$tmpl")
    if ! echo "$frontmatter" | grep -q '^status:'; then
      error "Missing 'status' in frontmatter of templates/$tmpl_name"
    fi
  fi
done
echo "$DONE_MARK"

# ---------------------------------------------------------------------------
# Check 8: module-help.csv menu codes are unique and exactly 2 characters
# ---------------------------------------------------------------------------
echo "Check 8: module-help.csv menu code uniqueness and format"
if [[ -f "$SRC/module-help.csv" ]]; then
  # Validate format using process substitution to avoid subshell
  while IFS=',' read -r _module _skill _display menu_code _rest; do
    menu_code=$(echo "$menu_code" | tr -d '[:space:]')
    [[ -z "$menu_code" ]] && continue
    if ! echo "$menu_code" | grep -qE '^[A-Za-z0-9]{2}$'; then
      error "Menu code '$menu_code' is not exactly 2 characters in module-help.csv"
    fi
  done < <(tail -n +2 "$SRC/module-help.csv")

  # Check uniqueness
  dupes=$(tail -n +2 "$SRC/module-help.csv" | awk -F',' '{gsub(/[[:space:]]/, "", $4); if ($4 != "") print $4}' | sort | uniq -d)
  if [[ -n "$dupes" ]]; then
    for d in $dupes; do
      error "Duplicate menu code '$d' in module-help.csv"
    done
  fi
else
  error "Missing $SRC/module-help.csv"
fi
echo "$DONE_MARK"

# ---------------------------------------------------------------------------
# Check 9: Every agent directory has SKILL.md and bmad-skill-manifest.yaml
# ---------------------------------------------------------------------------
echo "Check 9: Agent directories have SKILL.md and bmad-skill-manifest.yaml"
for dir in "$SRC"/agents/*/; do
  [[ -d "$dir" ]] || continue
  name=$(basename "$dir")
  if [[ ! -f "$dir/SKILL.md" ]]; then
    error "Missing SKILL.md in agents/$name"
  fi
  if [[ ! -f "$dir/bmad-skill-manifest.yaml" ]]; then
    error "Missing bmad-skill-manifest.yaml in agents/$name"
  fi
done
echo "$DONE_MARK"

# ---------------------------------------------------------------------------
# Check 10: Config variables referenced in step files exist in module.yaml
# ---------------------------------------------------------------------------
echo "Check 10: Config variable references exist in module.yaml"

known_vars=""
if [[ -f "$SRC/module.yaml" ]]; then
  yaml_keys=$(grep -E '^[a-z][a-z_]+:' "$SRC/module.yaml" | sed 's/:.*//' || true)
  inherited_keys=$(grep -E '^## [a-z]' "$SRC/module.yaml" | sed 's/^## //' || true)
  known_vars="$yaml_keys"$'\n'"$inherited_keys"
fi

skip_pattern='^(project-root)$'

for stepfile in "$SRC"/workflows/*/steps/*.md "$SRC"/workflows/*/workflow.md "$SRC"/agents/*/SKILL.md; do
  [[ -f "$stepfile" ]] || continue
  refs=$(grep -oE '`\{[a-z][a-z_-]*\}`' "$stepfile" 2>/dev/null | sed 's/[`{}]//g' | sort -u || true)
  for var in $refs; do
    if echo "$var" | grep -qE "$skip_pattern"; then
      continue
    fi
    if ! echo "$known_vars" | grep -qx "$var"; then
      rel_path=${stepfile#"$SRC"/}
      error "Config variable '{$var}' referenced in $rel_path not found in module.yaml"
    fi
  done
done
echo "$DONE_MARK"

# ---------------------------------------------------------------------------
# Check 11: Every agent, workflow, and standalone skill directory is registered
#           in module-help.csv
# ---------------------------------------------------------------------------
echo "Check 11: Agent, workflow, and skill directories registered in module-help.csv"
if [[ -f "$SRC/module-help.csv" ]]; then
  for dir in "$SRC"/agents/*/; do
    [[ -d "$dir" ]] || continue
    skill_name=$(basename "$dir")
    if ! awk -F',' -v name="$skill_name" '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 == name) { found=1; exit } } END { exit !found }' "$SRC/module-help.csv"; then
      error "Agent '$skill_name' not registered in module-help.csv"
    fi
  done
  for dir in "$SRC"/workflows/*/; do
    [[ -d "$dir" ]] || continue
    skill_name=$(basename "$dir")
    if ! awk -F',' -v name="$skill_name" '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 == name) { found=1; exit } } END { exit !found }' "$SRC/module-help.csv"; then
      error "Workflow '$skill_name' not registered in module-help.csv"
    fi
  done
  for dir in "$SRC"/skills/*/; do
    [[ -d "$dir" ]] || continue
    skill_name=$(basename "$dir")
    if ! awk -F',' -v name="$skill_name" '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 == name) { found=1; exit } } END { exit !found }' "$SRC/module-help.csv"; then
      error "Skill '$skill_name' not registered in module-help.csv"
    fi
  done
else
  error "Missing $SRC/module-help.csv"
fi
echo "$DONE_MARK"

# ---------------------------------------------------------------------------
# Check 12: copilot-setup-steps.yml has the required job name
# GitHub requires the job to be named exactly `copilot-setup-steps` to pick
# up the file for the Copilot cloud agent.
# ---------------------------------------------------------------------------
echo "Check 12: .github/workflows/copilot-setup-steps.yml has job named copilot-setup-steps"
COPILOT_WF=".github/workflows/copilot-setup-steps.yml"
if [[ ! -f "$COPILOT_WF" ]]; then
  error "Missing $COPILOT_WF"
elif ! awk '
  BEGIN { in_jobs=0; found=0 }
  /^[[:space:]]*jobs:[[:space:]]*$/ { in_jobs=1; next }
  in_jobs && /^[^[:space:]]/ { in_jobs=0 }
  in_jobs && /^[[:space:]]+copilot-setup-steps[[:space:]]*:/ { found=1; exit }
  END { exit(found ? 0 : 1) }
' "$COPILOT_WF"; then
  error "$COPILOT_WF does not contain a job named 'copilot-setup-steps' (GitHub requires this exact name)"
fi
echo "$DONE_MARK"

# ---------------------------------------------------------------------------
# Check 13: step-05-validation.md cross-workflow coherence and workflow count
# ---------------------------------------------------------------------------
echo "Check 13: step-05-validation.md workflow count and cross-plan coherence checks"
for stepfile in "$SRC"/workflows/*/steps/step-05-validation.md; do
  [[ -f "$stepfile" ]] || continue
  rel_path=${stepfile#"$SRC"/}

  # 13a: Must not reference outdated 'all 7 workflows' (checklist defines 8 plans)
  if grep -qE 'all 7 workflows' "$stepfile"; then
    error "$rel_path references 'all 7 workflows' instead of 'all 8 workflows'"
  fi

  # 13b: Any status check on Infrastructure Plan must accept 'approved' (its terminal state)
  while IFS= read -r line; do
    if ! echo "$line" | grep -qi 'approved'; then
      error "$rel_path checks Infrastructure Plan status without accepting 'approved': $line"
    fi
  done < <(grep -E 'Infrastructure Plan.*(status is|— if)' "$stepfile" 2>/dev/null || true)
done

DR_VAL="$SRC/workflows/bgr-3-create-disaster-recovery/steps/step-05-validation.md"
if [[ -f "$DR_VAL" ]]; then
  # Section 2 must lead with Infrastructure Plan and include DR-specific checks
  first_coherence_plan=$(awk '/^### 2\. Cross-Workflow Coherence Validation/{flag=1; next} flag && /^\*\*If .* Plan exists:\*\*/{print; exit}' "$DR_VAL")
  if [[ "$first_coherence_plan" != "**If Infrastructure Plan exists:**" ]]; then
    error "workflows/bgr-3-create-disaster-recovery/steps/step-05-validation.md Section 2 must lead with '**If Infrastructure Plan exists:**' (found: '$first_coherence_plan')"
  fi
  if ! grep -qF "Does the DR topology match the infrastructure architecture (multi-region, multi-AZ)?" "$DR_VAL"; then
    error "workflows/bgr-3-create-disaster-recovery/steps/step-05-validation.md missing '(multi-region, multi-AZ)' topology coherence check"
  fi
  if ! grep -qF "Is the handoff from incident response to DR activation clearly defined?" "$DR_VAL"; then
    error "workflows/bgr-3-create-disaster-recovery/steps/step-05-validation.md missing DR activation handoff coherence check"
  fi
  if ! grep -qF "Do DR failover triggers map to incident severity levels?" "$DR_VAL"; then
    error "workflows/bgr-3-create-disaster-recovery/steps/step-05-validation.md missing DR failover trigger severity mapping check"
  fi
  first_dep_plan=$(awk '/^4\. Check for cross-plan dependency gaps:/{flag=1; next} flag && /^[[:space:]]*- If .* Plan exists:/{sub(/^[[:space:]]+/, ""); print; exit}' "$DR_VAL")
  if [[ "$first_dep_plan" != "- If Infrastructure Plan exists: Verify DR topology matches infrastructure architecture, DR regions are consistent" ]]; then
    error "workflows/bgr-3-create-disaster-recovery/steps/step-05-validation.md Section 11.4 must lead with Infrastructure Plan dependency check"
  fi
fi

SEC_VAL="$SRC/workflows/bgr-3-create-security-plan/steps/step-05-validation.md"
if [[ -f "$SEC_VAL" ]]; then
  # shellcheck disable=SC2016
  if ! grep -qF '**Infrastructure Plan** — if `approved` or `complete`:' "$SEC_VAL"; then
    error "workflows/bgr-3-create-security-plan/steps/step-05-validation.md must check Infrastructure Plan status as 'approved' or 'complete'"
  fi
fi
echo "$DONE_MARK"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
if [[ "$ERRORS" -gt 0 ]]; then
  echo "Validation failed with $ERRORS error(s)" >&2
  exit 1
else
  echo "All validation checks passed"
  exit 0
fi
