# Codex Smart Contract Audit

Run a **maximum-depth, sequential, multi-skill smart contract audit** for the target declared in the runtime context.

The runtime context will tell you whether this is:

- a pull request audit (`audit mode: pr`)
- or a full checked-out branch snapshot audit (`audit mode: snapshot`)

## Non-negotiable execution order

1. Review the runtime audit context appended to this prompt.
2. Run `$secure-workflow-guide`.
3. Run `$smart-contract-audit`.
4. Run helper skills when the trigger conditions below are met.
5. Merge the result into one professional report.

Do not skip either required skill. If one cannot run fully, record that in `Blocked Checks` and continue with the other analysis.
Treat the appended runtime context as a compact summary. Open the referenced preflight artifacts only when you need deeper evidence.

## Audit scope rules

- If `audit mode: pr`, be **differential first**: start with the PR diff.
- If `audit mode: snapshot`, treat the full checked-out branch state as in-scope and prioritize:
  - externally callable entry points
  - privileged or governance surfaces
  - upgrade paths
  - token integrations
  - high-value state transitions
- Then expand into the true blast radius:
  - changed files
  - directly imported files
  - inherited contracts
  - interfaces used by changed contracts
  - tests covering the changed behavior
  - deployment and config scripts touched by the change
  - token integrations
  - upgrade and privileged access paths
- Inspect surrounding code when needed to avoid shallow conclusions.
- Prefer confirmed, technically grounded findings over speculative noise.

## Deterministic helper-skill triggers

If any of these conditions are true, the helper skill is required, not optional:

- Run `$token-integration-analyzer` if the runtime context or preflight artifacts show:
  - ERC20 / ERC721 / ERC1155 interfaces or implementations
  - token transfers, approvals, permits, wrappers, vault shares, fee-on-transfer handling
  - any changed or blast-radius code that integrates third-party tokens
- Run `$entry-point-analyzer` if the runtime context or preflight artifacts show:
  - changed public or external entry points
  - changed privileged entry points
  - upgrade, admin, governance, or pause-related surfaces
- Run `$foundry-poc` if:
  - you identify a plausible high- or critical-severity EVM finding
  - a Foundry project is present or `forge` is available
  - a realistic proof can be attempted without fabricating setup
- Run `$tiny-auditor` as a final critical-loss sweep when:
  - the project is EVM
  - the changed and blast-radius contract set is still tractable
  - you can use it to challenge whether any unprivileged loss-of-funds issues were missed

If a trigger fired and the helper skill still could not run, document that explicitly in `Blocked Checks`.

## Required skill behavior

### Required Trail of Bits workflow

Your merged report must explicitly cover the 5-step secure workflow wherever applicable:

1. Known issues scan
   - Slither findings
   - severity
   - exact file references
   - false-positive triage when justified
2. Special feature checks
   - upgradeability
   - ERC conformance
   - token integration
   - other feature-specific checks that apply
3. Visual security inspection
   - inheritance graph
   - function summary
   - state variable / authorization mapping
   - if CI cannot generate rendered images, produce artifact-friendly text, DOT, or markdown representations and state that clearly
4. Security properties
   - invariants
   - access-control properties
   - arithmetic / precision constraints
   - external interaction safety
   - what should be fuzzed or formally verified later
5. Manual review areas
   - privacy / secrets
   - front-running / MEV
   - cryptography misuse
   - DeFi integration risks
   - oracle / flash-loan assumptions

### Required forefy workflow

Your merged report must explicitly include forefy-style audit outputs where relevant:

- triaged findings
- multi-expert analysis
- triager validation status
- exploit path reasoning
- attack or call-flow analysis
- PoC or exploit sketch when realistic
- severity and impact
- remediation advice
- economic feasibility or disproof notes when triaging severity

## Report requirements

Produce **one merged audit**, not two disconnected writeups.

You must:

- put findings first
- use exact file paths and line references when possible
- clearly distinguish confirmed findings from weaker concerns
- list the contracts and files reviewed
- list the tests reviewed
- call out tests or verification that are missing
- preserve the raw forefy audit trail in `.context/outputs/X/`
- preserve or generate Trail of Bits evidence artifacts when available
- include explicit `No findings` notes when a check ran clean
- include explicit `Blocked Checks` notes when a check could not run
- state which skill or skills contributed to each finding
- avoid fabricating PoCs; if not demonstrated, say so
- preserve triager verdicts such as `DISMISSED`, `QUESTIONABLE`, or `RELUCTANTLY VALID`
- cite the exact artifact paths you produced or consumed

## Evidence preservation requirements

If the forefy skill runs, preserve its expected output structure in `.context/outputs/X/` and do not overwrite prior numbered runs.

At minimum, maintain:

- `.context/outputs/X/audit-context.md`
- `.context/outputs/X/audit-debug.md`
- `.context/outputs/X/audit-report.md`

If preflight artifacts exist in `.codex-smart-contract-auditor/preflight/`, use them. Do not ignore them.

If Trail of Bits workflow commands generate diagrams, summaries, or DOT files, keep them as artifacts and reference their paths in the merged report.

## Required markdown output

Write the final merged markdown report to:

`audit-report.md`

Use this structure:

1. Executive Summary
2. Scope
3. PR / Diff Context or Snapshot Context
4. Blast Radius
5. Skills / Checks Run
6. Trail of Bits Workflow Checklist
7. forefy Validation Summary
8. Findings Table
9. Detailed Findings
10. Attack Paths / PoC Notes
11. Security Properties to Add
12. Tests / Verification Gaps
13. Blocked Checks
14. Artifact Inventory
15. Recommended Next Actions

## Required JSON output

Write the machine-readable summary to:

`audit-report.json`

Use this schema shape:

```json
{
  "schema_version": "1.0",
  "generated_at": "ISO-8601",
  "repository": "owner/repo",
  "pr_number": 123,
  "base_sha": "abc",
  "head_sha": "def",
  "audit_mode": "pr|snapshot",
  "model": "string",
  "severity_threshold": "medium",
  "summary": {
    "critical": 0,
    "high": 0,
    "medium": 0,
    "low": 0,
    "informational": 0,
    "blocked_checks": 0
  },
  "scope": {
    "changed_files": [],
    "blast_radius_files": [],
    "contracts_reviewed": [],
    "tests_reviewed": []
  },
  "checks_run": [
    {
      "name": "secure-workflow-guide",
      "source": "trail-of-bits",
      "status": "passed|findings|blocked",
      "notes": "string",
      "artifact_paths": ["string"]
    },
    {
      "name": "smart-contract-audit",
      "source": "forefy",
      "status": "passed|findings|blocked",
      "notes": "string",
      "artifact_paths": ["string"]
    }
  ],
  "findings": [
    {
      "id": "stable-id",
      "title": "string",
      "severity": "critical|high|medium|low|informational",
      "confidence": "high|medium|low",
      "category": "access-control|reentrancy|upgradeability|oracle|mev|etc",
      "status": "open|triaged|duplicate|blocked",
      "triager_status": "DISMISSED|QUESTIONABLE|RELUCTANTLY_VALID|null",
      "description": "string",
      "impact": "string",
      "exploitability": "string",
      "remediation": "string",
      "poc": "string or null",
      "attack_path": "string or null",
      "economic_notes": "string or null",
      "files": [
        {
          "path": "contracts/X.sol",
          "line": 42
        }
      ],
      "source_skills": [
        "secure-workflow-guide",
        "smart-contract-audit"
      ],
      "artifact_paths": ["string"]
    }
  ],
  "security_properties": [
    {
      "property": "string",
      "kind": "invariant|access-control|arithmetic|external-interaction",
      "recommended_test_type": "echidna|manticore|slither-check|manual"
    }
  ],
  "blocked_checks": [
    {
      "check": "string",
      "reason": "string",
      "next_step": "string"
    }
  ],
  "artifacts": [
    {
      "path": "string",
      "kind": "preflight|diagram|forefy-output|poc|report|json|other"
    }
  ]
}
```

## Final-message fallback transport

If you cannot create one or both repository files directly, your final assistant message must include recovery blocks using these exact marker lines:

`BEGIN AUDIT REPORT`

full markdown report content

`END AUDIT REPORT`

`BEGIN AUDIT JSON`

full JSON content

`END AUDIT JSON`

Do not summarize inside those blocks. Emit the complete markdown and complete JSON so the workflow can recover the outputs.

## Quality bar

- Do not return only generic advice.
- Do not claim a check ran if it did not.
- Do not hide uncertainty.
- Do not emit duplicate findings if two skills discovered the same root issue.
- Normalize severity across the merged report.
- Prefer concise, technically dense writing over filler.
- Keep the raw evidence and merged summary consistent with each other.
- If a finding survives into the final report, it must reflect both the supporting evidence and any triager skepticism.

## Final step

Before finishing:

1. Confirm `audit-report.md` exists.
2. Confirm `audit-report.json` exists and is valid JSON.
3. In your final response, briefly state:
   - overall status
   - finding counts by severity
   - blocked check count
   - whether both required skills ran
   - which helper skills were triggered
