# Codex Smart Contract Audit

Run a **maximum-depth, sequential, multi-skill smart contract audit** for this pull request.

## Non-negotiable execution order

1. Review the runtime audit context appended to this prompt.
2. Run `$secure-workflow-guide`.
3. Run `$smart-contract-audit`.
4. Use any other installed helper skills only if they add signal without replacing the two required skills.
5. Merge the result into one professional report.

Do not skip either required skill. If one cannot run fully, record that in `Blocked Checks` and continue with the other analysis.

## Audit scope rules

- Be **differential first**: start with the PR diff.
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
- exploit path reasoning
- attack or call-flow analysis
- PoC or exploit sketch when realistic
- severity and impact
- remediation advice

## Report requirements

Produce **one merged audit**, not two disconnected writeups.

You must:

- put findings first
- use exact file paths and line references when possible
- clearly distinguish confirmed findings from weaker concerns
- list the contracts and files reviewed
- list the tests reviewed
- call out tests or verification that are missing
- include explicit `No findings` notes when a check ran clean
- include explicit `Blocked Checks` notes when a check could not run
- state which skill or skills contributed to each finding
- avoid fabricating PoCs; if not demonstrated, say so

## Required markdown output

Write the final merged markdown report to:

`audit-report.md`

Use this structure:

1. Executive Summary
2. Scope
3. PR / Diff Context
4. Blast Radius
5. Skills / Checks Run
6. Findings Table
7. Detailed Findings
8. Attack Paths / PoC Notes
9. Security Properties to Add
10. Tests / Verification Gaps
11. Blocked Checks
12. Recommended Next Actions

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
      "notes": "string"
    },
    {
      "name": "smart-contract-audit",
      "source": "forefy",
      "status": "passed|findings|blocked",
      "notes": "string"
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
      "description": "string",
      "impact": "string",
      "exploitability": "string",
      "remediation": "string",
      "poc": "string or null",
      "attack_path": "string or null",
      "files": [
        {
          "path": "contracts/X.sol",
          "line": 42
        }
      ],
      "source_skills": [
        "secure-workflow-guide",
        "smart-contract-audit"
      ]
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
  ]
}
```

## Quality bar

- Do not return only generic advice.
- Do not claim a check ran if it did not.
- Do not hide uncertainty.
- Do not emit duplicate findings if two skills discovered the same root issue.
- Normalize severity across the merged report.
- Prefer concise, technically dense writing over filler.

## Final step

Before finishing:

1. Confirm `audit-report.md` exists.
2. Confirm `audit-report.json` exists and is valid JSON.
3. In your final response, briefly state:
   - overall status
   - finding counts by severity
   - blocked check count
   - whether both required skills ran
