#!/usr/bin/env bash
set -euo pipefail

workdir="${INPUT_WORKING_DIRECTORY:-.}"
preflight_dir="${PREFLIGHT_DIR:-.codex-smart-contract-auditor/preflight}"
runtime_context_path="${RUNTIME_CONTEXT_PATH:-.codex-smart-contract-auditor/runtime-context.md}"
has_foundry="${HAS_FOUNDRY:-false}"
audit_mode="${INPUT_AUDIT_MODE:-pr}"
cost_profile="${INPUT_COST_PROFILE:-balanced}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  }
}

write_output() {
  local key="$1"
  local value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
  fi
}

safe_line_count() {
  local file="$1"
  if [[ -f "$file" ]]; then
    wc -l < "$file" | tr -d ' '
  else
    printf '0'
  fi
}

emit_preview_section() {
  local heading="$1"
  local file="$2"
  local limit="$3"

  local count
  count="$(safe_line_count "$file")"

  echo "## $heading"
  echo "- Count: $count"
  echo "- Full artifact: \`$file\`"

  if [[ -s "$file" ]]; then
    echo "- Preview:"
    head -n "$limit" "$file" | sed 's/^/  - /'
    if (( count > limit )); then
      echo "  - ... ($((count - limit)) more line(s))"
    fi
  else
    echo "- Preview: none"
  fi

  echo
}

run_preflight_scan() {
  local label="$1"
  shift

  local out="$preflight_dir/${label}.txt"
  local err="$preflight_dir/${label}.stderr"

  if timeout 600s "$@" >"$out" 2>"$err"; then
    printf -- '- %s: ok\n' "$label" >> "$checks_path"
  else
    printf -- '- %s: blocked\n' "$label" >> "$checks_path"
    {
      printf '## %s\n' "$label"
      if [[ -s "$err" ]]; then
        head -40 "$err"
      else
        printf 'Command exited without stderr output.\n'
      fi
      printf '\n'
    } >> "$blockers_path"
    rm -f "$out"
  fi
}

require_cmd git
require_cmd find
require_cmd jq
require_cmd rg

[[ -d "$workdir" ]] || {
  printf 'working directory does not exist: %s\n' "$workdir" >&2
  exit 1
}

mkdir -p "$preflight_dir"

changed_files="$preflight_dir/changed-files.txt"
solidity_changes="$preflight_dir/solidity-changes.txt"
contract_files="$preflight_dir/contract-files.txt"
test_files="$preflight_dir/test-files.txt"
script_files="$preflight_dir/script-files.txt"
entry_points="$preflight_dir/public-entry-points.txt"
privileged_entry_points="$preflight_dir/privileged-entry-points.txt"
token_surface="$preflight_dir/token-surface.txt"
upgrade_surface="$preflight_dir/upgrade-surface.txt"
access_control_surface="$preflight_dir/access-control-surface.txt"
blast_radius="$preflight_dir/blast-radius-seeds.txt"
layout_files="$preflight_dir/layout-files.txt"
summary_path="$preflight_dir/summary.md"
checks_path="$preflight_dir/preflight-checks.md"
blockers_path="$preflight_dir/tool-blockers.md"

base_sha="${INPUT_BASE_SHA:-}"
head_sha="${INPUT_HEAD_SHA:-}"
pr_number="${INPUT_PR_NUMBER:-}"
severity_threshold="${INPUT_SEVERITY_THRESHOLD:-medium}"

case "$audit_mode" in
  pr|snapshot)
    ;;
  *)
    printf 'unsupported audit mode: %s\n' "$audit_mode" >&2
    exit 1
    ;;
esac

if [[ "$audit_mode" == "pr" ]]; then
  if [[ -z "$base_sha" && -n "${GITHUB_EVENT_PATH:-}" && -f "$GITHUB_EVENT_PATH" ]]; then
    base_sha="$(jq -r '.pull_request.base.sha // empty' "$GITHUB_EVENT_PATH")"
  fi
  if [[ -z "$head_sha" && -n "${GITHUB_EVENT_PATH:-}" && -f "$GITHUB_EVENT_PATH" ]]; then
    head_sha="$(jq -r '.pull_request.head.sha // empty' "$GITHUB_EVENT_PATH")"
  fi
  if [[ -z "$pr_number" && -n "${GITHUB_EVENT_PATH:-}" && -f "$GITHUB_EVENT_PATH" ]]; then
    pr_number="$(jq -r '.pull_request.number // empty' "$GITHUB_EVENT_PATH")"
  fi
fi

if [[ -z "$head_sha" ]]; then
  head_sha="$(git rev-parse HEAD)"
fi

if [[ "$audit_mode" == "snapshot" ]]; then
  base_sha=""
  pr_number=""
  git ls-files > "$changed_files"
  printf 'Snapshot mode: auditing full checked-out branch state at %s.\n' "$head_sha" > "$preflight_dir/diff-stat.txt"
elif [[ -n "$base_sha" ]]; then
  git diff --name-only "$base_sha" "$head_sha" > "$changed_files" || true
  git diff --stat "$base_sha" "$head_sha" > "$preflight_dir/diff-stat.txt" || true
else
  git ls-files > "$changed_files"
  printf 'PR mode without a usable base SHA: using repository file list as fallback.\n' > "$preflight_dir/diff-stat.txt"
fi

grep -E '\.(sol|vy)$' "$changed_files" > "$solidity_changes" || true

find "$workdir" -type f \( -name '*.sol' -o -name '*.vy' \) | sort > "$contract_files" || true
find "$workdir" -type f \
  \( -path '*/test/*' -o -path '*/tests/*' -o -name '*.t.sol' -o -name '*Test.sol' -o -name '*.spec.ts' -o -name '*.test.ts' -o -name '*.spec.js' -o -name '*.test.js' \) \
  | sort > "$test_files" || true
find "$workdir" -type f \
  \( -path '*/script/*' -o -path '*/scripts/*' -o -name '*Deploy*.s.sol' -o -name '*deploy*.ts' -o -name '*deploy*.js' \) \
  | sort > "$script_files" || true

rg --no-heading --line-number 'function\s+[A-Za-z0-9_]+\s*\([^)]*\)\s*(public|external)' "$workdir" > "$entry_points" || true
rg --no-heading --line-number 'function\s+[A-Za-z0-9_]+\s*\([^)]*\)[^{;]*\b(onlyOwner|onlyRole|auth|requiresAuth|governor|admin)\b' "$workdir" > "$privileged_entry_points" || true
rg --no-heading --line-number 'IERC20|IERC721|IERC1155|ERC20|ERC721|ERC1155|transferFrom|safeTransferFrom|approve\(|permit\(' "$workdir" > "$token_surface" || true
rg --no-heading --line-number 'UUPSUpgradeable|TransparentUpgradeableProxy|ERC1967|ProxyAdmin|upgradeTo|upgradeToAndCall|initializer|reinitializer' "$workdir" > "$upgrade_surface" || true
rg --no-heading --line-number 'onlyOwner|onlyRole|AccessControl|Ownable|auth|governor|timelock|multisig|pause\(|unpause\(' "$workdir" > "$access_control_surface" || true
find . -maxdepth 2 \
  \( -name 'foundry.toml' -o -name 'hardhat.config.*' -o -name 'package.json' -o -name 'pyproject.toml' -o -name 'remappings.txt' \) \
  -print | sort > "$layout_files" || true

: > "$blast_radius"
if [[ -s "$solidity_changes" ]]; then
  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    printf '%s\n' "$file" >> "$blast_radius"
    rg --no-heading --line-number '^\s*import\s+' "$file" >> "$blast_radius" || true
    rg --no-heading --line-number 'contract\s+.+\s+is\s+' "$file" >> "$blast_radius" || true
  done < "$solidity_changes"
fi

{
  echo "# Runtime Audit Context"
  echo
  echo "- Audit mode: $audit_mode"
  echo "- Working directory: $workdir"
  echo "- Severity threshold: $severity_threshold"
  echo "- Cost profile: $cost_profile"
  echo "- Base SHA: ${base_sha:-unavailable}"
  echo "- Head SHA: ${head_sha:-unavailable}"
  if [[ "$audit_mode" == "snapshot" ]]; then
    echo "- Pull request number: not applicable"
  else
    echo "- Pull request number: ${pr_number:-unavailable}"
  fi
  echo
  echo "## Tool availability"
  printf -- "- slither: %s\n" "$(command -v slither >/dev/null 2>&1 && slither --version 2>/dev/null | head -1 || echo unavailable)"
  printf -- "- solc-select: %s\n" "$(command -v solc-select >/dev/null 2>&1 && solc-select --version 2>/dev/null | head -1 || echo unavailable)"
  printf -- "- forge: %s\n" "$(command -v forge >/dev/null 2>&1 && forge --version 2>/dev/null | head -1 || echo unavailable)"
  printf -- "- node: %s\n" "$(command -v node >/dev/null 2>&1 && node --version 2>/dev/null || echo unavailable)"
  echo
  echo "## Detailed preflight artifacts"
  echo "- Summary: \`$summary_path\`"
  echo "- Checks: \`$checks_path\`"
  echo "- Blockers: \`$blockers_path\`"
  echo
  emit_preview_section "Repository layout" "$layout_files" 8
  echo "## Diff stat"
  echo "- Full artifact: \`$preflight_dir/diff-stat.txt\`"
  sed 's/^/- /' "$preflight_dir/diff-stat.txt" || true
  echo
  emit_preview_section "Changed files" "$changed_files" 10
  emit_preview_section "Solidity / Vyper changes" "$solidity_changes" 10
  echo "## Surface counts"
  echo "- Contract inventory: $(safe_line_count "$contract_files") (\`$contract_files\`)"
  echo "- Test inventory: $(safe_line_count "$test_files") (\`$test_files\`)"
  echo "- Script inventory: $(safe_line_count "$script_files") (\`$script_files\`)"
  echo "- Blast radius seeds: $(safe_line_count "$blast_radius") (\`$blast_radius\`)"
  echo "- Public / external entry points: $(safe_line_count "$entry_points") (\`$entry_points\`)"
  echo "- Privileged entry points: $(safe_line_count "$privileged_entry_points") (\`$privileged_entry_points\`)"
  echo "- Token surface hits: $(safe_line_count "$token_surface") (\`$token_surface\`)"
  echo "- Upgrade surface hits: $(safe_line_count "$upgrade_surface") (\`$upgrade_surface\`)"
  echo "- Access control surface hits: $(safe_line_count "$access_control_surface") (\`$access_control_surface\`)"
} > "$runtime_context_path"

{
  echo "# Deterministic Preflight Summary"
  echo
  printf -- "- Audit mode: %s\n" "$audit_mode"
  printf -- "- Changed files: %s\n" "$(safe_line_count "$changed_files")"
  printf -- "- Solidity/Vyper changes: %s\n" "$(safe_line_count "$solidity_changes")"
  printf -- "- Contracts discovered: %s\n" "$(safe_line_count "$contract_files")"
  printf -- "- Tests discovered: %s\n" "$(safe_line_count "$test_files")"
  printf -- "- Scripts discovered: %s\n" "$(safe_line_count "$script_files")"
  printf -- "- Public/external entry points: %s\n" "$(safe_line_count "$entry_points")"
  printf -- "- Privileged entry points: %s\n" "$(safe_line_count "$privileged_entry_points")"
  printf -- "- Token surface hits: %s\n" "$(safe_line_count "$token_surface")"
  printf -- "- Upgrade surface hits: %s\n" "$(safe_line_count "$upgrade_surface")"
} > "$summary_path"

: > "$blockers_path"
: > "$checks_path"

if [[ -s "$contract_files" ]]; then
  run_preflight_scan "slither-human-summary" slither "$workdir" --exclude-dependencies --print human-summary
  run_preflight_scan "slither-contract-summary" slither "$workdir" --exclude-dependencies --print contract-summary
  run_preflight_scan "slither-function-summary" slither "$workdir" --exclude-dependencies --print function-summary
  run_preflight_scan "slither-vars-and-auth" slither "$workdir" --exclude-dependencies --print vars-and-auth
else
  printf '## slither-preflight\nNo Solidity or Vyper contracts detected under %s.\n' "$workdir" >> "$blockers_path"
fi

if [[ "$has_foundry" == "true" ]] && command -v forge >/dev/null 2>&1; then
  run_preflight_scan "forge-test-list" forge test --root "$workdir" --list
else
  printf '## forge-test-list\nFoundry not detected or forge is unavailable.\n' >> "$blockers_path"
fi

write_output "base_sha" "$base_sha"
write_output "head_sha" "$head_sha"
write_output "pr_number" "$pr_number"
write_output "audit_mode" "$audit_mode"
