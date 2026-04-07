# codex-smart-contract-auditor

`codex-smart-contract-auditor` is a reusable GitHub Actions repository for **maximum-depth, sequential smart contract audits on pull requests and branch snapshots**.

It wires together two required audit skill families:

- Trail of Bits `building-secure-contracts`, especially `$secure-workflow-guide`
- forefy `.context`, especially `$smart-contract-audit`

The goal is simple: let an EVM repository drop in **one workflow file** and get a merged audit report in both Markdown and JSON, plus an optional sticky PR summary comment.

The reusable workflow supports both OpenAI-hosted Responses and Venice-hosted Responses.

## What This Repo Does

The reusable workflow:

1. Checks out the caller repository.
2. Installs deterministic audit prerequisites such as Slither.
3. Installs external skill packs from their upstream repositories at pinned refs.
4. Exposes the selected skills to Codex through repo-scoped `.agents/skills`.
5. Builds a runtime audit prompt with audit mode, scope context, blast radius, entry-point surfaces, token surfaces, and upgrade surfaces.
6. Runs a **sequential** Codex audit:
   - `$secure-workflow-guide`
   - `$smart-contract-audit`
   - deterministically triggered helper skills when needed, such as `$token-integration-analyzer`, `$entry-point-analyzer`, and `$foundry-poc`
   - merged final report
7. Uploads:
   - `audit-report.md`
   - `audit-report.json`
   - `.codex-smart-contract-auditor/preflight/`
   - `.context/outputs/`
8. Optionally updates a sticky PR comment with severity counts and blocked-check status.

## Why Sequential

This v1 design is intentionally **sequential only**.

That is the better reusable default for smart contract audits:

- one shared preflight
- one deterministic prompt
- fewer race conditions
- simpler artifact handling
- cleaner merged output
- easier debugging when a required skill is blocked
- better preservation of raw audit evidence

Parallel execution is possible later, but it adds duplication, merging complexity, and more ways for a reusable workflow to fail noisily.

## Consumer Setup

Add one workflow file to the repository you want to audit:

```yaml
name: Smart Contract Audit

on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]

permissions:
  contents: read
  issues: write
  pull-requests: write

jobs:
  audit:
    uses: MikeHathaway/smart-contract-auditor/.github/workflows/codex-smart-contract-audit.yml@main
    with:
      provider: auto
      audit-mode: pr
      model: ""
      effort: ""
      severity-threshold: medium
      fail-on-severity: high
      post-pr-comment: true
      pr-number: ${{ github.event.pull_request.number }}
      base-sha: ${{ github.event.pull_request.base.sha }}
      head-sha: ${{ github.event.pull_request.head.sha }}
    secrets:
      OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
      VENICE_API_KEY: ${{ secrets.VENICE_API_KEY }}
```

Ready-to-copy consumer workflows:

- generic provider-aware example: [`.github/workflows/example-consumer.yml`](/home/mike/Projects-2026/smart-contract-auditor/.github/workflows/example-consumer.yml)
- Venice-only example: [`.github/workflows/example-consumer-venice.yml`](/home/mike/Projects-2026/smart-contract-auditor/.github/workflows/example-consumer-venice.yml)
- manual branch snapshot example: [`.github/workflows/example-consumer-manual-snapshot.yml`](/home/mike/Projects-2026/smart-contract-auditor/.github/workflows/example-consumer-manual-snapshot.yml)

If you are consuming this repository directly, keep the `uses:` target pointed at `MikeHathaway/smart-contract-auditor`. Only change it if you fork or republish the reusable workflow under a different owner, repository, or ref.

## Provider Secrets

- `OPENAI_API_KEY` for OpenAI-hosted Responses
- `VENICE_API_KEY` for Venice-hosted Responses

Store these as **GitHub Actions repository secrets** by default:

- repository: `Settings` -> `Secrets and variables` -> `Actions` -> `Repository secrets`

That is the intended default for this workflow. It does not require GitHub Actions environments.

Both secrets are optional so the workflow can degrade cleanly for environments like forked PRs. If the selected provider key is not available, it still emits deterministic artifacts with a `Blocked Checks` section instead of failing silently.

If `provider: venice` is selected and `VENICE_API_KEY` is not set, the workflow falls back to `OPENAI_API_KEY` as a compatibility escape hatch. That is useful if you already store a Venice key under the older secret name, but `VENICE_API_KEY` is the cleaner long-term setup.

Use an organization secret if you want to share one provider key across multiple repositories. Use an environment secret only if you intentionally want environment-level approvals or scoping and are also wiring `environment:` into the caller workflow.

## Quick Setup Guide

For a typical Venice-backed pull request setup:

1. In the repository you want to audit, go to `Settings` -> `Secrets and variables` -> `Actions`.
2. Under `Repository secrets`, create `VENICE_API_KEY`.
3. Add a workflow that calls:
   `MikeHathaway/smart-contract-auditor/.github/workflows/codex-smart-contract-audit.yml@main`
4. Set `provider: venice`.
5. Leave `model: ""` and `effort: ""` if you want the workflow’s Venice defaults.
6. Pass the secret with:
   `VENICE_API_KEY: ${{ secrets.VENICE_API_KEY }}`
7. Open or update a pull request to trigger the audit.

## Required Permissions

Caller workflow:

- `contents: read`
- `issues: write` if you want sticky PR comments
- `pull-requests: write` if you want sticky PR comments

The audit job itself uses only `contents: read`. PR write access is isolated to the separate comment job.

## Inputs

The reusable workflow supports these inputs:

- `provider`: `auto`, `openai`, or `venice`; defaults to `auto`
- `audit-mode`: `pr` or `snapshot`; defaults to `pr`
- `model`: optional Codex model override
- `effort`: optional Codex reasoning effort override
- `responses-api-endpoint`: optional Responses API endpoint override
- `working-directory`: repository subdirectory to prioritize
- `severity-threshold`: summary emphasis threshold, defaults to `medium`
- `fail-on-severity`: fail the workflow when findings at or above this severity exist
- `post-pr-comment`: enable or disable sticky PR comments
- `extra-audit-instructions`: append extra markdown instructions to the runtime prompt
- `base-sha`: optional explicit base SHA, primarily for `audit-mode: pr`
- `head-sha`: optional explicit head SHA
- `pr-number`: optional explicit pull request number, primarily for `audit-mode: pr`

Provider defaults are intentionally asymmetric:

- `provider: auto` prefers OpenAI when both `OPENAI_API_KEY` and `VENICE_API_KEY` are present
- OpenAI: if `model` and `effort` are blank, the action uses Codex defaults
- Venice: if `model` is blank, the workflow uses `openai-gpt-54`
- Venice: if `effort` is blank, the workflow uses `high`
- Venice: if `responses-api-endpoint` is blank, the workflow uses `https://api.venice.ai/api/v1/responses`

That keeps OpenAI behavior cleaner while making Venice deterministic enough to work reliably with `openai/codex-action`.

## Workflow Internals

The reusable workflow still exposes one public entrypoint, but the largest implementation sections now live in repo-local helper scripts for maintainability:

- `scripts/run-preflight.sh`
- `scripts/validate-audit-outputs.sh`
- `scripts/upsert-pr-comment.cjs`

That keeps provider selection, preflight logic, fallback artifact generation, and sticky-comment behavior easier to review and change without growing the workflow YAML further.

## Branch Snapshot Mode

The reusable workflow now supports a first-class snapshot mode:

- `audit-mode: pr`
  - differential-first pull request review
  - uses PR context when available
  - PR comments make sense here
- `audit-mode: snapshot`
  - full checked-out branch audit
  - no PR context is assumed
  - best for manual `main` or release-branch audits

In snapshot mode, the workflow treats the entire checked-out tree as in-scope rather than pretending there is a meaningful PR diff.

There is a ready-to-copy manual snapshot example in [`.github/workflows/example-consumer-manual-snapshot.yml`](/home/mike/Projects-2026/smart-contract-auditor/.github/workflows/example-consumer-manual-snapshot.yml).

To audit a specific branch snapshot, select that branch in the GitHub Actions "Run workflow" branch picker, or run the workflow from CLI with `gh workflow run ... --ref <branch>`.

## Venice Setup

To force Venice as the backing Responses provider:

```yaml
jobs:
  audit:
    uses: MikeHathaway/smart-contract-auditor/.github/workflows/codex-smart-contract-audit.yml@main
    with:
      provider: venice
      audit-mode: pr
      model: ""
      effort: ""
    secrets:
      VENICE_API_KEY: ${{ secrets.VENICE_API_KEY }}
```

With those settings, the workflow resolves these Venice defaults automatically:

- endpoint: `https://api.venice.ai/api/v1/responses`
- model: `openai-gpt-54`
- effort: `high`

If you need a different Venice model or endpoint, pass `model` or `responses-api-endpoint` explicitly.

If both provider secrets are configured and you still want Venice, set `provider: venice` explicitly.

There is also a dedicated copy-paste Venice consumer workflow in [`.github/workflows/example-consumer-venice.yml`](/home/mike/Projects-2026/smart-contract-auditor/.github/workflows/example-consumer-venice.yml).

## Evidence Artifacts

This repo now preserves more than the merged summary.

Uploaded artifacts include:

- `audit-report.md`
- `audit-report.json`
- `.codex-smart-contract-auditor/preflight/` for deterministic preflight evidence
- `.context/outputs/` for raw forefy output directories

That matters because the upstream forefy framework expects persistent numbered audit outputs, and the Trail of Bits workflow is materially stronger when the generated summaries and diagrams are kept instead of paraphrased away.

## What The Report Contains

`audit-report.md` contains the merged human-readable report with these sections:

1. Executive Summary
2. Scope
3. PR / Diff Context or Snapshot Context
4. Blast Radius
5. Skills / Checks Run
6. Findings Table
7. Detailed Findings
8. Attack Paths / PoC Notes
9. Security Properties to Add
10. Tests / Verification Gaps
11. Blocked Checks
12. Recommended Next Actions

`audit-report.json` contains a deterministic machine-readable summary suitable for:

- Codex-based reviewer tooling
- future Claude reviewer integrations
- post-processing pipelines
- dashboards and policy gates

The JSON includes:

- severity counts
- audit mode
- changed and reviewed scope
- checks run
- findings with source skills
- triager status and artifact paths when available
- security properties to add
- blocked checks

## How The Skill Packs Are Incorporated

### Trail of Bits

This repo installs `trailofbits/skills` at a pinned ref and exposes selected smart-contract skills through `.agents/skills`, including:

- `secure-workflow-guide`
- `token-integration-analyzer`
- `entry-point-analyzer`
- `guidelines-advisor`

The prompt explicitly requires `$secure-workflow-guide` to run and explicitly requires the merged report to cover its 5-step workflow:

- known issues scan
- special feature checks
- visual inspection
- security properties
- manual review areas

### forefy

This repo installs `forefy/.context` at a pinned ref and exposes these repo-scoped skills:

- `smart-contract-audit`
- `foundry-poc`
- `tiny-auditor`

The prompt explicitly requires `$smart-contract-audit` and requires forefy-style outputs:

- triaged findings
- multi-expert analysis
- triager validation
- exploit path reasoning
- attack-path / call-flow analysis
- realistic PoC notes when practical
- remediation guidance

It also preserves the raw numbered `.context/outputs/X/` audit trail instead of replacing it with only a top-level summary.

## Deterministic Helper Skill Triggers

For maximum rigor, the prompt now treats certain helper-skill invocations as required when their trigger conditions are present:

- token-related blast radius -> `token-integration-analyzer`
- changed external, admin, governance, or upgrade surfaces -> `entry-point-analyzer`
- plausible high-severity exploit plus Foundry availability -> `foundry-poc`

This is a better fit for the upstream skill design than leaving helper skills entirely discretionary.

## How Skill Installation Works

`install-skills.sh` clones upstream skill repositories and then symlinks the selected skill directories into the caller repository’s `.agents/skills` folder.

That matters because Codex officially discovers repo-scoped skills from `.agents/skills` in the working tree.

The installer is:

- idempotent
- modular
- easy to extend
- pinned to concrete upstream refs

To add another skill pack later, update only:

- [`install-skills.sh`](/home/mike/Projects-2026/smart-contract-auditor/install-skills.sh)
- [`audit-prompt.md`](/home/mike/Projects-2026/smart-contract-auditor/audit-prompt.md)

## Sticky PR Comment Behavior

When `post-pr-comment` is `true`, the workflow keeps one sticky comment identified by:

```html
<!-- codex-smart-contract-audit -->
```

The comment includes:

- overall status
- severity counts
- blocked check count
- artifact name

The detailed markdown and JSON reports stay in workflow artifacts instead of spamming the PR thread.

## Security Notes

This workflow is primarily designed for untrusted pull requests, but the same trust model also matters for manual branch snapshot audits.

Safe defaults included here:

- consumer example uses `pull_request`, not `pull_request_target`
- checkout uses `persist-credentials: false`
- the audit job uses only `contents: read`
- PR write access is isolated to the comment job
- Codex runs with `safety-strategy: drop-sudo`
- Codex runs with `sandbox: workspace-write`
- no extra repo write privileges are requested
- deterministic preflight artifacts are generated before the model runs

Additional rigor-oriented setup:

- installs `graphviz` so Trail of Bits visual outputs are less likely to block
- installs Foundry with the official `foundry-rs/foundry-toolchain` action when a `foundry.toml` repo is detected
- runs best-effort preflight Slither summaries before the model starts

Also important:

- do not feed raw untrusted PR descriptions or issue bodies into the prompt without sanitizing them
- keep provider API keys scoped to the reusable workflow invocation
- remember that blocked checks are expected in some repos, especially when Slither or deeper static analysis cannot run cleanly without additional project setup

## Limitations

- This repo does **not** attempt parallel multi-agent execution in v1.
- It avoids undocumented `openai/codex-action@v1` inputs on purpose.
- Smart contract repos vary wildly. Some checks will still block on compiler or dependency layout. When that happens, the workflow reports the block instead of pretending the check ran.
- For forked PRs, GitHub often withholds secrets. In that case you still get artifacts, but the report will show Codex execution as blocked.
- Venice support depends on Venice continuing to accept Codex-compatible Responses API payloads. The workflow now targets Venice’s `/api/v1/responses` endpoint directly, but provider-specific payload differences can still affect behavior.

## Compatibility

The repo is built so the outputs can be reused outside Codex:

- the prompt is mostly reviewer-agnostic markdown
- the workflow separates orchestration from prompt content
- the installer is independent from the report format
- the final JSON is deterministic enough for future Claude or other reviewer tooling

## Upstream Skill Licensing

This repository does **not** vendor third-party skill contents into the repo tree.

Instead it installs them at runtime from upstream sources:

- Trail of Bits skills keep their upstream license and history
- forefy `.context` keeps its upstream license and history

Review those upstream repositories before pinning or redistributing modified versions.
