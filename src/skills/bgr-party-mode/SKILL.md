---
name: bgr-party-mode
description: 'Multi-agent operations party mode where Morgan (SRE), Riley (DevOps), and Sam (Security) collaboratively review plans, architecture decisions, incidents, and production readiness from independent domain perspectives. Use when the user says "party mode" or "run party mode" or "multi-agent review" or "cross-domain review"'
---

# Operations Party Mode

## Overview

This skill orchestrates a multi-agent collaborative review session across the BGreat Suite personas — **Morgan** (SRE Lead), **Riley** (DevOps Lead), and **Sam** (Security Lead). Inspired by the BMAD Method party mode pattern, the orchestrator spawns independent subagents for each participating lead so they analyze operational plans, architecture decisions, incident postmortems, or production readiness from their authentic domain perspective without anchoring on or blending with one another.

This skill is read-only with respect to existing operational artifacts — it analyzes them without modification and writes a new session synthesis report to `{bgr_artifacts}/party-mode-report.md`.

## Who Can Run This

Any agent (Morgan, Riley, or Sam) or the user directly via menu code `PM`. When invoked while an agent persona is active, that agent acts as the host moderator while still contributing their unabridged domain review alongside the other participating leads.

## Use Cases

1. **Plan Review Gate** — Before marking any BGreat plan as complete, review it from all relevant perspectives (e.g., Riley and Sam reviewing Morgan's Observability Plan for infrastructure alignment and telemetry data security).
2. **Architecture Input** — All three agents contribute their domain requirements, probing questions, and constraints to system architecture decisions (`bmad-create-architecture`).
3. **Incident Post-Mortem** — Multi-perspective blameless analysis of production incidents across detection and response (Morgan), deployment and infrastructure triggers (Riley), and blast-radius or security implications (Sam).
4. **Production Readiness Assessment** — Holistic cross-domain verification across all `{bgr_artifacts}/` plans and the production readiness checklist prior to launch (`bmad-check-implementation-readiness`).

## Participating Agent Personas

Each participating agent must load and embody their full persona definition, principles, and anti-patterns:

| Agent | Persona Definition | Domain Perspective | Primary Focus Areas |
|-------|-------------------|--------------------|---------------------|
| **Morgan** (SRE Lead) | `../../agents/bgr-agent-morgan-sre/SKILL.md` | SRE Reliability | Golden Signals, SLIs/SLOs, error budgets, alerting burn rates, runbooks, blameless postmortems, blast radius, toil elimination |
| **Riley** (DevOps Lead) | `../../agents/bgr-agent-riley-devops/SKILL.md` | DevOps Operability | IaC rigor, GitOps, hermetic environment isolation, CI/CD pipeline gates, automated rollback, zero manual changes, FinOps efficiency |
| **Sam** (Security Lead) | `../../agents/bgr-agent-sam-security/SKILL.md` | Security Posture | Threat modeling (STRIDE/PASTA), defense in depth, least privilege IAM, encryption, secrets rotation, supply chain security, compliance mapping |

## Instructions

### Step 1 — Configuration & Artifact Discovery

1. Load configuration from `{project-root}/_bmad/bgr/config.yaml` and resolve:
   - `{user_name}` for addressing the user
   - `{communication_language}` for session dialogue
   - `{document_output_language}` for the generated report
   - `{bgr_artifacts}` for artifact discovery and report output
   - `{bgr_maturity}`, `{cloud_preference}`, and `{container_orchestration}` for operational context
   - `{project_knowledge}` for additional project documentation

2. Determine the session topic and use case from the user's request (or ask the user which plan, architecture decision, incident, or readiness gate they want the party to review).

3. Scan `{bgr_artifacts}/`, `{project_knowledge}/`, and `{project-root}/docs/` for relevant artifacts using the sharded-first discovery pattern (check for a sharded folder `*{name}*/index.md` first; if not found, load whole `*{name}*.md` files):

| Artifact | Expected Source Workflow |
|----------|------------------------|
| Observability Plan | `bgr-3-create-observability` |
| Incident Response Plan | `bgr-3-create-incident-response` |
| Disaster Recovery Plan | `bgr-3-create-disaster-recovery` |
| Resilience Testing Plan | `bgr-3-create-resilience-plan` |
| Chaos Game Day Plan | `bgr-3-create-chaos-gameday-plan` |
| Infrastructure Plan | `bgr-3-create-infrastructure` |
| Pipeline Plan | `bgr-3-create-pipeline` |
| Capacity Plan | `bgr-3-create-capacity-plan` |
| Cost Optimization Plan | `bgr-3-create-cost-optimization-plan` |
| Security Plan | `bgr-3-create-security-plan` |
| Production Readiness Checklist | Shared checklist (`production-readiness-checklist.md`) |

Also load `**/project-context.md` and any referenced Architecture (`*architecture*.md`) or Incident Postmortem documents when applicable.

### Step 2 — Agent Selection

Select 2–3 agents relevant to the discussion topic (unless the user explicitly specifies which agents to include):

| Topic / Target Artifact | Selected Agents | Rationale |
|-------------------------|-----------------|-----------|
| Observability Plan (`CO`) | Morgan, Riley, Sam | Morgan leads SRE review; Riley validates infrastructure/collector topology; Sam checks log PII redaction and audit trail coverage |
| Incident Response Plan (`CR`) / Post-Mortem | Morgan, Riley, Sam | Morgan leads on-call and runbooks; Riley checks pipeline rollback mechanics; Sam covers security incident escalation and breach containment |
| Disaster Recovery (`CD`) / Resilience (`CT`) / Chaos Game Day (`CG`) | Morgan, Riley, Sam | Morgan leads RTO/RPO and steady-state hypotheses; Riley verifies IaC failover automation; Sam validates failover trust boundaries and blast radius |
| Infrastructure (`CI`) / Pipeline (`CP`) | Riley, Morgan, Sam | Riley leads IaC, isolation, and CI/CD stages; Morgan checks SLO gates and canary verification; Sam enforces network segmentation, IAM, and supply chain scanning |
| Capacity Plan (`CC`) / Cost Optimization (`CF`) | Morgan, Riley (plus Sam if compliance/availability affected) | Morgan and Riley co-lead scaling vs. SLO error budgets and FinOps trade-offs; Sam joins when right-sizing or multi-tenancy touches isolation boundaries |
| Security Plan (`CS`) | Sam, Riley, Morgan | Sam leads threat model and controls; Riley validates pipeline security gates and secrets injection; Morgan aligns security alerting with on-call response |
| Architecture Input (`CA`) / Production Readiness (`IR`) | Morgan, Riley, Sam | All three domains must sign off on architecture constraints and launch readiness |

Announce the selected roster and the target artifacts to `{user_name}` before starting Round 1.

### Step 3 — Independent Multi-Agent Review (Round 1)

For each selected agent, execute an independent domain review of the target material:

1. **Spawn Independent Subagents (Preferred):**
   - If the host runtime supports subagent invocation, spawn a separate subagent for each participating lead (**Morgan**, **Riley**, **Sam**).
   - Provide each subagent with:
     - Their complete persona file (`../../agents/bgr-agent-morgan-sre/SKILL.md`, `../../agents/bgr-agent-riley-devops/SKILL.md`, or `../../agents/bgr-agent-sam-security/SKILL.md`)
     - The project configuration context (`{bgr_maturity}`, `{cloud_preference}`, `{container_orchestration}`)
     - The full text of the target artifact(s) and discussion prompt
   - Running subagents in parallel ensures genuine independent thinking without one agent anchoring on another's conclusions.
   - **Graceful Inline Fallback:** If subagent spawning is unavailable in the current environment, execute each agent's analysis sequentially with strict persona isolation, and explicitly record in the session header and output report that the review ran in inline mode rather than independent subagent mode.

2. **Present Full Unabridged Responses:**
   - Output each agent's complete, unedited review under their own heading (`### Morgan (SRE Lead)`, `### Riley (DevOps Lead)`, `### Sam (Security Lead)`).
   - **CRITICAL:** Never blend, summarize, paraphrase in third person, or water down an agent's response. Each agent must speak in their own distinct voice and communication style.
   - Each agent's review must include:
     - **Domain Verdict:** `PASS`, `PASS WITH CONCERNS`, or `BLOCKING ISSUES`
     - **Strengths & Alignment:** What the plan or design gets right from their domain lens
     - **Findings:** Concrete issues categorized as `BLOCKING`, `WARNING`, or `RECOMMENDATION`, citing specific sections or omissions
     - **Cross-Domain Questions:** 1–2 pointed questions directed at the other agents or the user

### Step 4 — Cross-Domain Conflict Analysis & Dynamic Follow-Ups

After presenting the unabridged Round 1 responses:

1. **Surface Cross-Domain Conflicts:**
   Identify and explicitly call out points where the agents' domain principles clash, such as:
   - **Reliability vs. Velocity:** Morgan requiring stricter SLO burn-rate gates or longer canary observation windows vs. Riley optimizing pipeline throughput.
   - **Security vs. Automation:** Sam requiring strict access boundaries, manual approval gates, or data redaction vs. Riley enforcing zero-touch automation or Morgan requiring deep diagnostic trace attributes.
   - **Resilience vs. Cost:** Morgan and Sam advocating multi-region active-active isolation vs. Riley and FinOps budget constraints in `{bgr_maturity}` environments.

   **Do not resolve conflicts silently.** Present the competing positions and trade-off options clearly so `{user_name}` can make an informed decision.

2. **Run Dynamic Cross-Examination:**
   Trigger targeted follow-up turns where agents respond directly to one another's concerns (e.g., *"Morgan, respond to Sam's concern about sensitive payloads in distributed traces"*, *"Riley, how does your hotfix pipeline satisfy Sam's provenance check and Morgan's error-budget freeze?"*).

3. **Interactive User Steering:**
   Invite `{user_name}` to:
   - Direct a follow-up question to a specific agent (e.g., *"Morgan, respond to Sam's concern about..."* or *"Riley, what if we use ECS instead?"*)
   - Ask two agents to debate a specific trade-off
   - Record a decision on an open cross-domain conflict
   - Conclude the session and generate the structured party mode report

### Step 5 — Consensus Synthesis & Report Generation

When `{user_name}` signals that the discussion is complete (or requests the report immediately):

1. Synthesize the session using the template at `./templates/party-mode-report.md`:
   - Populate the session metadata fields (`{use_case}`, `{participating_agents}`, `{execution_mode}`, `Project`, `Topic / Target`, `Generated`, and frontmatter `createdDate`/`lastUpdated`) from the values determined in Steps 1–3, and include only the subsections for agents that participated in the session
   - Populate the Artifact & Context Discovery table with each artifact's discovered status and file path, and replace `Artifacts found: 0 / 11` with the actual count
   - Preserve each participating agent's unabridged domain findings and populate their domain verdict placeholder (`{morgan_verdict}`, `{riley_verdict}`, `{sam_verdict}`)
   - Document every cross-domain conflict, each agent's position, the trade-off options, and any decision reached
   - Capture key exchanges from the dynamic follow-up rounds
   - Compile prioritized **Consensus Recommendations** (`Blocking`, `High Priority`, `Suggested Improvements`) with owning agents
   - Assign an overall **Gate Verdict** (`{overall_verdict}`): `APPROVED`, `APPROVED WITH CONDITIONS`, or `CHANGES REQUIRED`

2. Write the completed report to `{bgr_artifacts}/party-mode-report.md`.

3. Present a concise closing summary to `{user_name}` with:
   - Per-agent verdicts and overall Gate Verdict
   - Unresolved cross-domain trade-offs requiring user sign-off
   - Top blocking or high-priority consensus action items
   - Path to the saved report (`{bgr_artifacts}/party-mode-report.md`)
