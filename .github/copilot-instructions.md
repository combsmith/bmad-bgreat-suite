# Copilot Instructions — BMad BGreat Suite

## About

BMad BGreat Suite is a BMAD Method extension module providing three specialized AI agents (Morgan/SRE, Riley/DevOps, Sam/Security) and eight guided workflows for production readiness planning.

## Tech Stack

- **Type:** Content-only (Markdown + YAML — no compiled code)
- **Runtime:** None (workflow definitions executed by the BMAD Method runtime)
- **Validation:** PyYAML (`pip install pyyaml`) for YAML syntax checks
- **CI:** GitHub Actions — validate YAML, module structure, module-help.csv, skill integrity, gitleaks secret scan

## Project Structure

```text
src/
├── agents/           # Agent persona definitions (SKILL.md + bmad-skill-manifest.yaml)
├── workflows/        # Guided multi-step workflows
│   └── {name}/
│       ├── SKILL.md
│       ├── bmad-skill-manifest.yaml
│       ├── workflow.md
│       ├── steps/        # step-01-init.md, step-02-*.md …
│       └── templates/    # Output document templates
├── skills/           # Standalone skills (single-step, no workflow structure)
│   └── {name}/
│       ├── SKILL.md
│       ├── bmad-skill-manifest.yaml
│       └── templates/    # Optional output templates
├── templates/        # Shared templates (production readiness checklist)
├── module.yaml       # Module configuration
└── module-help.csv   # Skill registry with menu codes and dependencies
```

## Local Dev Commands

```bash
# Install validation dependency
pip install pyyaml

# Validate all YAML files
status=0
while IFS= read -r file; do
  if ! python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1]))" "$file"; then
    echo "Invalid YAML: $file"
    status=1
  fi
done < <(find . \( -name '*.yaml' -o -name '*.yml' \) -not -path '*/node_modules/*' -not -path '*/.git/*')

# Validate skill and workflow structural integrity (main test command)
bash tools/validate-skills.sh || status=1

# Validate repo-settings script coverage
bash tools/test-repo-settings.sh || status=1

exit $status
```

### Secret Scan (mirrors CI `secret-scan` job)

Run this separately before opening a PR — especially after adding templates, workflow docs, or config examples that might contain accidental credentials. Requires [gitleaks](https://github.com/gitleaks/gitleaks#installing) to be installed locally.

```bash
gitleaks detect --source . --redact --verbose --exit-code 1
```

The CI `secret-scan` job (`.github/workflows/ci.yml` lines 133–164) runs this same command and will fail the workflow on any detected secrets. Running it locally first avoids a CI-blocking failure after push.

## Required Environment Variables

None — this is a content-only repository with no runtime secrets or API keys.

## Testing Framework

No test runner. Structural validation is performed by `bash tools/validate-skills.sh`, which checks:

- SKILL.md and `bmad-skill-manifest.yaml` present for every agent and workflow
- `workflow.md`, `steps/`, `templates/` present for every workflow
- Step file naming convention (`step-NN-*.md`)
- Relative path references resolve to real files
- Template frontmatter contains required fields (`status`, `stepsCompleted`)
- Every agent, workflow, and standalone skill directory is registered in `module-help.csv`
- `module-help.csv` menu codes are unique and exactly 2 characters
- Config variable references exist in `module.yaml`

## Repo-Specific Overrides

- Markdown tables must use standard syntax (`| col | col |`) — no double pipes
- Template variables use `{{variable}}` or `{variable}` syntax consistently
- Config variables reference `{bgr_artifacts}`, `{bgr_maturity}`, `{communication_language}`, etc.
- Step files must include a mandatory execution rules block and present `[C]ontinue / [R]evise` menus

## Organization Standards

See [combsmith/.github AGENTS.md](https://github.com/combsmith/.github/blob/main/AGENTS.md) for org-level standards.
