# BMad BGreat Suite

[![Contributing](https://img.shields.io/badge/contributions-welcome-brightgreen.svg)](https://github.com/combsmith/.github/blob/main/CONTRIBUTING.md)

Additional agents to extend the [BMad Method](https://github.com/bmad-code-org/BMAD-METHOD) ecosystem.

Three specialized agents — **Morgan** (SRE Lead), **Riley** (DevOps Lead), and **Sam** (Security Lead) — with ten guided workflows, a cross-agent operations review, and multi-agent party mode that produce production-readiness artifacts alongside your architecture planning.

## What's Included

### Agents

| Agent | Role | Expertise |
|-------|------|-----------|
| **Morgan** (SRE Lead) | Observability, incident response, SLO/SLI, reliability | Golden Signals, RED/USE methods, OpenTelemetry, error budgets, chaos engineering, blameless postmortems |
| **Riley** (DevOps Lead) | Infrastructure, CI/CD, deployment, platform engineering | Terraform/Pulumi, Kubernetes, GitOps, pipeline design, blue-green/canary deployments |
| **Sam** (Security Lead) | Threat modeling, compliance, security architecture | STRIDE/PASTA, SOC2/HIPAA/PCI-DSS/GDPR compliance mapping, supply chain security |

### Workflows

| Workflow | Menu Code | Owner | Output |
|----------|-----------|-------|--------|
| Create Observability Plan | `CO` | Morgan | Metrics, logging, tracing, SLOs, dashboards, alerting strategy |
| Create Incident Response Plan | `CR` | Morgan | Severity levels, runbooks, on-call procedures, postmortem templates |
| Create Disaster Recovery Plan | `CD` | Morgan | RTO/RPO targets, backup/restore, failover procedures, DR runbooks |
| Create Resilience Testing Plan | `CT` | Morgan | Steady-state hypotheses, failure scenarios, chaos experiment procedures |
| Create Chaos Game Day Plan | `CG` | Morgan | Hypothesis-driven experiments, blast radius controls, safety gates |
| Create Infrastructure Plan | `CI` | Riley | IaC strategy, environment topology, containers, networking |
| Create Pipeline Plan | `CP` | Riley | CI/CD stages, security scanning, deployment strategy, release gates |
| Create Capacity Plan | `CC` | Morgan + Riley | Growth modeling, auto-scaling, resource scaling, load testing |
| Create Cost Optimization Plan | `CF` | Riley + Morgan | FinOps strategy, right-sizing, reserved/spot, cost governance |
| Create Security Plan | `CS` | Sam | Threat model, security controls, auth strategy, compliance mapping |
| Operations Review | `OR` | Any agent | Cross-agent consistency review, coverage gaps, staleness checks |
| Operations Party Mode | `PM` | Morgan + Riley + Sam | Multi-agent collaborative review, cross-domain conflict analysis, consensus recommendations |

### Recommended Workflow Order

```
Architecture (bmm) --> Observability (CO) --> Incident Response (CR)
                   |                      --> Chaos Game Day (CG)
                   --> Infrastructure (CI) --> Pipeline (CP)
                   |                       --> Disaster Recovery (CD)
                   |                       --> Capacity Plan (CC)
                   |                       --> Cost Optimization (CF)
                   --> Security Plan (CS)

Incident Response (CR) --> Resilience Testing (CT)

After any workflows: Operations Review (OR) / Operations Party Mode (PM)
```

Multiple tracks can run in parallel after the architecture is defined.

## Installation

Requires BMad Method **v6.7 or later** (tested on v6.12.4). Since v6.7, custom
modules install with `--custom-source`; the old `--custom-content` flag and the
community module picker are gone.

### From GitHub

```bash
npx bmad-method install --custom-source https://github.com/combsmith/bmad-bgreat-suite
```

### From a local clone

Point `--custom-source` at the **repository root** (the folder that holds
`.claude-plugin/marketplace.json`), not at `src/`. Pointing at `src/` finds no
module and installs nothing, without an error.

```bash
git clone https://github.com/combsmith/bmad-bgreat-suite
npx bmad-method install --custom-source ./bmad-bgreat-suite
```

Add `--modules bmm --tools claude-code --directory . --yes` (or your own tool
IDs) for a non-interactive install. `--directory .` is needed on installer
versions before v6.12.2, which otherwise stop at the directory prompt. The
installer marks custom modules as unverified: they have not been reviewed by
the BMad team.

**Existing installs.** If `_bmad/` already exists, the installer menu defaults
to **Quick Update**, which does not resolve `--custom-source`: the command
finishes without error and installs nothing. Select **Modify BMAD
Installation** at the menu. For a non-interactive run, add `--action update`.
This applies to both commands above.

**Installed modules can be removed.** On an existing installation, installing
with `--custom-source` keeps only `core` and the custom modules, and removes
other installed modules (such as `bmm`) without asking. `--modules` sets the
exact module set, so it removes any module it does not list. To keep your
installed modules, pass `--yes` without `--modules`, or list every module to
keep in `--modules`.

There is no npm package; install from GitHub or a local clone.

### BMad v7 preview

Not yet supported. `npx skills add combsmith/bmad-bgreat-suite` copies the
skills, but v7's `bmad setup` does not recognize them as a module: it asks
none of the configuration questions below and does not write
`_bmad/bgr/config.yaml`, which every workflow loads first. Use v6 until the
suite is ported to v7's module format.

## Configuration

During installation, the module will ask:

- **bgr_artifacts** — Where to store operations planning artifacts (default: `_bmad-output/bgr-artifacts`)
- **bgr_maturity** — Your current operations maturity level (greenfield through advanced)
- **cloud_preference** — Primary cloud provider
- **container_orchestration** — Container platform (Kubernetes, ECS, Cloud Run, etc.)

These settings shape how Morgan, Riley, and Sam tailor their guidance.

## Usage

### Wake an agent

From the BMad help menu, select:
- `MG` — Wake Morgan (SRE Lead)
- `RL` — Wake Riley (DevOps Lead)
- `SE` — Wake Sam (Security Lead)

### Run a workflow directly

Invoke any workflow by menu code:
- `CO` — Create Observability Plan
- `CR` — Create Incident Response Plan
- `CD` — Create Disaster Recovery Plan
- `CT` — Create Resilience Testing Plan
- `CG` — Create Chaos Game Day Plan
- `CI` — Create Infrastructure Plan
- `CP` — Create Pipeline Plan
- `CC` — Create Capacity Plan
- `CF` — Create Cost Optimization Plan
- `CS` — Create Security Plan
- `OR` — Operations Review
- `PM` — Operations Party Mode

### Cross-module collaboration

Morgan, Riley, and Sam can all invoke the Architecture (`CA`) and Implementation Readiness (`IR`) workflows from the core BMad Method module, bringing their operational expertise into those conversations.

## Module Structure

```
src/
  module.yaml              # Module configuration and install prompts
  module-help.csv          # Capability registry
  agents/
    bgr-agent-morgan-sre/  # SRE Lead persona
    bgr-agent-riley-devops/# DevOps Lead persona
    bgr-agent-sam-security/# Security Lead persona
  workflows/
    bgr-3-create-observability/
    bgr-3-create-incident-response/
    bgr-3-create-disaster-recovery/
    bgr-3-create-resilience-plan/
    bgr-3-create-chaos-gameday-plan/
    bgr-3-create-infrastructure/
    bgr-3-create-pipeline/
    bgr-3-create-capacity-plan/
    bgr-3-create-cost-optimization-plan/
    bgr-3-create-security-plan/
  skills/
    bgr-ops-review/        # Cross-agent artifact consistency review
    bgr-party-mode/        # Multi-agent collaborative review session
```

Each workflow follows BMAD's micro-file architecture: a `workflow.md` orchestrator, sequential `steps/` for guided discovery, and `templates/` for output documents.

## Requirements

- [BMad Method](https://github.com/bmad-code-org/BMAD-METHOD) v6.7 or later (v7 preview not yet supported)
- Core module (required)
- BMad Method module (recommended — enables CA and IR cross-references)

## Attribution

This module incorporates ideas from these MIT-licensed projects in the BMad ecosystem:

- [Ricoledan/bmad-architecture-agent](https://github.com/Ricoledan/bmad-architecture-agent) — Platform Engineering expansion pack patterns (agent "Sam")
- [bacoco/BMad-Skills](https://github.com/bacoco/BMad-Skills) — Observability readiness skill structure and reference patterns

## Commercial Support & Integration

Need enterprise SLAs, custom integrations, or managed DevOps/SRE agent workflows for the BMad Method ecosystem?

Commercial support and services are offered through **[CombSmith LLC](https://combsmith.com)**:
- **Enterprise Support SLAs:** Priority bug fixes, dedicated maintenance windows, and security updates.
- **Custom Integrations:** Bespoke SRE/DevOps agents, pipeline integrations, and custom BMad workflows.
- **Consulting & Implementation:** Architectural guidance, reliability engineering, and agentic DevOps rollout.

For commercial inquiries, email [support@combsmith.com](mailto:support@combsmith.com) or visit [combsmith.com](https://combsmith.com).

---

## Contributing

See the org-wide [Contributing Guide](https://github.com/combsmith/.github/blob/main/CONTRIBUTING.md). Contributions welcome. This module is designed to grow — new agents and workflows can be added following the patterns in `src/agents/` and `src/workflows/`.

1. Fork the repo
2. Create a feature branch
3. Follow existing conventions (SKILL.md, bmad-skill-manifest.yaml, workflow.md, steps/)
4. Submit a PR with a clear description

---

## License

MIT
