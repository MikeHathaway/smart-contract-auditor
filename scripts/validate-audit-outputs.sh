#!/usr/bin/env bash
set -euo pipefail

api_key_present="${API_KEY_PRESENT:-false}"
provider="${PROVIDER:-openai}"
provider_key_source="${PROVIDER_KEY_SOURCE:-}"
responses_api_endpoint="${RESPONSES_API_ENDPOINT:-}"
codex_outcome="${CODEX_OUTCOME:-}"
audit_mode="${AUDIT_MODE:-pr}"
base_sha="${BASE_SHA:-}"
head_sha="${HEAD_SHA:-}"
pr_number="${PR_NUMBER:-}"
model_input="${MODEL_INPUT:-}"
severity_threshold="${SEVERITY_THRESHOLD:-medium}"

if [[ ! -f audit-report.md ]]; then
  {
    printf '# Smart Contract Audit Report\n\n'
    printf '## Executive Summary\n\n'
    printf 'The reusable workflow did not receive a complete audit report from Codex. A fallback report was generated so the workflow still emits deterministic artifacts.\n\n'
    printf '## Scope\n\n'
    printf -- '- Audit mode: %s\n' "${audit_mode:-pr}"
    printf -- '- Base SHA: %s\n' "${base_sha:-unavailable}"
    printf -- '- Head SHA: %s\n' "${head_sha:-unavailable}"
    if [[ "$audit_mode" == "snapshot" ]]; then
      printf -- '- Pull request number: not applicable\n\n'
    else
      printf -- '- Pull request number: %s\n\n' "${pr_number:-unavailable}"
    fi
    printf '## Skills / Checks Run\n\n'
    printf -- '- secure-workflow-guide: blocked\n'
    printf -- '- smart-contract-audit: blocked\n\n'
    printf '## Findings Table\n\n'
    printf 'No confirmed findings were emitted because the audit did not complete.\n\n'
    printf '## Blocked Checks\n\n'
    printf -- '- Codex audit execution\n'
    printf '  - Reason: %s\n' "$(if [[ "$api_key_present" != "true" ]]; then printf 'No API key was provided for provider %s.' "$provider"; else echo "Codex action for provider '$provider' finished with outcome '$codex_outcome' or did not write the required report files."; fi)"
    printf '  - Next step: Provide a valid provider API key, confirm repository prompts are valid, and re-run the workflow.\n'
  } > audit-report.md
fi

if ! jq empty audit-report.json >/dev/null 2>&1; then
  blocked_reason="Codex did not write a valid audit-report.json file."
  if [[ "$api_key_present" != "true" ]]; then
    blocked_reason="No API key was provided for provider '$provider'."
  elif [[ "$codex_outcome" == "failure" ]]; then
    blocked_reason="Codex action for provider '$provider' failed before producing a valid JSON report."
  fi

  jq -n \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg repository "${GITHUB_REPOSITORY}" \
    --arg pr_number "${pr_number:-}" \
    --arg base_sha "${base_sha:-}" \
    --arg head_sha "${head_sha:-}" \
    --arg audit_mode "${audit_mode:-pr}" \
    --arg model "${model_input:-}" \
    --arg provider "${provider:-openai}" \
    --arg provider_key_source "${provider_key_source:-}" \
    --arg responses_api_endpoint "${responses_api_endpoint:-}" \
    --arg severity_threshold "${severity_threshold}" \
    --arg blocked_reason "$blocked_reason" \
    '{
      schema_version: "1.0",
      generated_at: $generated_at,
      repository: $repository,
      pr_number: (if $pr_number == "" then null else ($pr_number | tonumber?) end),
      base_sha: $base_sha,
      head_sha: $head_sha,
      audit_mode: $audit_mode,
      provider: $provider,
      provider_key_source: (if $provider_key_source == "" then null else $provider_key_source end),
      responses_api_endpoint: (if $responses_api_endpoint == "" then null else $responses_api_endpoint end),
      model: $model,
      severity_threshold: $severity_threshold,
      summary: {
        critical: 0,
        high: 0,
        medium: 0,
        low: 0,
        informational: 0,
        blocked_checks: 1
      },
      scope: {
        changed_files: [],
        blast_radius_files: [],
        contracts_reviewed: [],
        tests_reviewed: []
      },
      checks_run: [
        {
          name: "secure-workflow-guide",
          source: "trail-of-bits",
          status: "blocked",
          notes: $blocked_reason,
          artifact_paths: [".codex-smart-contract-auditor/preflight"]
        },
        {
          name: "smart-contract-audit",
          source: "forefy",
          status: "blocked",
          notes: $blocked_reason,
          artifact_paths: [".context/outputs"]
        }
      ],
      findings: [],
      security_properties: [],
      blocked_checks: [
        {
          check: "codex-sequential-audit",
          reason: $blocked_reason,
          next_step: "Provide a valid provider API key and re-run the workflow."
        }
      ],
      artifacts: [
        {
          path: ".codex-smart-contract-auditor/preflight",
          kind: "preflight"
        },
        {
          path: ".context/outputs",
          kind: "forefy-output"
        },
        {
          path: "audit-report.md",
          kind: "report"
        },
        {
          path: "audit-report.json",
          kind: "json"
        }
      ]
    }' > audit-report.json
fi

jq empty audit-report.json >/dev/null
