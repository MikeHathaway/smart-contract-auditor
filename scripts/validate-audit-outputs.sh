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
final_message_path=".codex-smart-contract-auditor/final-message.md"

report_md_present=false
report_json_present=false
report_json_valid=false
final_message_present=false
report_md_source="workspace"
report_json_source="workspace"

[[ -f audit-report.md ]] && report_md_present=true
[[ -f audit-report.json ]] && report_json_present=true
if [[ "$report_json_present" == "true" ]] && jq empty audit-report.json >/dev/null 2>&1; then
  report_json_valid=true
fi
[[ -f "$final_message_path" ]] && final_message_present=true

extract_marked_block() {
  local start_marker="$1"
  local end_marker="$2"

  [[ "$final_message_present" == "true" ]] || return

  awk -v start="$start_marker" -v end="$end_marker" '
    $0 == start { capture=1; next }
    $0 == end { capture=0; exit }
    capture { print }
  ' "$final_message_path"
}

normalize_json_block() {
  sed '/^```json[[:space:]]*$/d; /^```[[:space:]]*$/d'
}

attempt_final_message_recovery() {
  [[ "$final_message_present" == "true" ]] || return

  if [[ "$report_md_present" != "true" ]]; then
    local recovered_report
    recovered_report="$(extract_marked_block "BEGIN AUDIT REPORT" "END AUDIT REPORT")"
    if [[ -n "$recovered_report" ]]; then
      printf '%s\n' "$recovered_report" > audit-report.md
      report_md_present=true
      report_md_source="final-message-tagged-block"
    fi
  fi

  if [[ "$report_json_valid" != "true" ]]; then
    local recovered_json
    recovered_json="$(extract_marked_block "BEGIN AUDIT JSON" "END AUDIT JSON" | normalize_json_block)"
    if [[ -n "$recovered_json" ]] && printf '%s\n' "$recovered_json" | jq empty >/dev/null 2>&1; then
      printf '%s\n' "$recovered_json" > audit-report.json
      report_json_present=true
      report_json_valid=true
      report_json_source="final-message-tagged-block"
    fi
  fi
}

attempt_final_message_recovery

output_contract_summary() {
  printf 'audit-report.md=%s(%s); audit-report.json=%s(%s); audit-report.json.valid=%s; final-message=%s' \
    "$report_md_present" "$report_md_source" "$report_json_present" "$report_json_source" "$report_json_valid" "$final_message_present"
}

output_contract_reason() {
  if [[ "$api_key_present" != "true" ]]; then
    printf 'No API key was provided for provider %s.' "$provider"
    return
  fi

  if [[ "$codex_outcome" == "failure" ]]; then
    printf "Codex action for provider '%s' failed before producing the required output files." "$provider"
    return
  fi

  if [[ "$provider" == "venice" && "$final_message_present" == "true" && "$report_md_present" != "true" && "$report_json_valid" != "true" ]]; then
    printf "Codex action for provider '%s' returned a final assistant message but did not create the required report files or tagged fallback blocks. This usually indicates partial Responses compatibility without full Codex workspace-write behavior." "$provider"
    return
  fi

  local failures=()
  [[ "$report_md_present" == "true" ]] || failures+=("missing audit-report.md")
  [[ "$report_json_present" == "true" ]] || failures+=("missing audit-report.json")
  if [[ "$report_json_present" == "true" && "$report_json_valid" != "true" ]]; then
    failures+=("invalid audit-report.json")
  fi

  if [[ ${#failures[@]} -eq 0 ]]; then
    printf "Codex output validation failed for an unknown reason."
  else
    printf "Codex action for provider '%s' completed with outcome '%s' but violated the output contract: %s." \
      "$provider" "${codex_outcome:-unknown}" "$(IFS=', '; echo "${failures[*]}")"
  fi
}

final_message_excerpt() {
  if [[ "$final_message_present" != "true" ]]; then
    return
  fi

  awk 'NR<=20 { print }' "$final_message_path" | sed 's/\r$//' | sed '/^[[:space:]]*$/d' | head -10
}

blocked_reason="$(output_contract_reason)"
contract_summary="$(output_contract_summary)"

if [[ "$report_md_present" != "true" ]]; then
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
    printf '  - Reason: %s\n' "$blocked_reason"
    printf '  - Output contract: %s\n' "$contract_summary"
    if [[ "$final_message_present" == "true" ]]; then
      printf '  - Final message path: %s\n' "$final_message_path"
      printf '  - Final message excerpt:\n'
      while IFS= read -r line; do
        printf '    %s\n' "$line"
      done < <(final_message_excerpt)
    else
      printf '  - Final message path: missing\n'
    fi
    printf '  - Next step: Provide a valid provider API key, confirm repository prompts are valid, and re-run the workflow.\n'
  } > audit-report.md
fi

if [[ "$report_json_valid" != "true" ]]; then
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
    --arg codex_outcome "${codex_outcome:-}" \
    --arg severity_threshold "${severity_threshold}" \
    --arg blocked_reason "$blocked_reason" \
    --arg output_contract_summary "$contract_summary" \
    --arg final_message_path "$final_message_path" \
    --arg final_message_present "$final_message_present" \
    --arg final_message_excerpt "$(final_message_excerpt)" \
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
      codex_outcome: (if $codex_outcome == "" then null else $codex_outcome end),
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
          output_contract: $output_contract_summary,
          final_message_path: (if $final_message_present == "true" then $final_message_path else null end),
          final_message_excerpt: (if $final_message_excerpt == "" then null else $final_message_excerpt end),
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
