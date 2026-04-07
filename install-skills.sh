#!/usr/bin/env bash
set -euo pipefail

# codex-smart-contract-auditor skill installer
#
# This script installs external skill packs into deterministic locations and then
# exposes the selected skills to Codex through repo-scoped `.agents/skills`
# symlinks. Future packs should be added by editing only the manifest and the
# registration calls near the bottom of this file.

REPO_ROOT="${REPO_ROOT:-$(pwd)}"
WORKSPACE_SKILLS_DIR="${WORKSPACE_SKILLS_DIR:-$REPO_ROOT/.agents/skills}"
STATE_DIR="${STATE_DIR:-$REPO_ROOT/.codex-smart-contract-auditor}"
VENDOR_DIR="${VENDOR_DIR:-$STATE_DIR/vendor}"
TRAILOFBITS_HOME="${TRAILOFBITS_HOME:-$VENDOR_DIR/trailofbits-skills}"
FOREFY_CONTEXT_HOME="${FOREFY_CONTEXT_HOME:-$HOME/.context}"

# Manifest format:
#   pack_name|repo_url|pinned_ref|destination|description
PACKS=(
  "trailofbits|https://github.com/trailofbits/skills.git|d7f76b5|$TRAILOFBITS_HOME|Trail of Bits Codex skills (pinned)"
  "forefy|https://github.com/forefy/.context|6cc33df|$FOREFY_CONTEXT_HOME|forefy audit skill pack (pinned)"
)

log() {
  printf '[install-skills] %s\n' "$*"
}

fail() {
  printf '[install-skills] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

ensure_parent_dirs() {
  mkdir -p "$WORKSPACE_SKILLS_DIR" "$VENDOR_DIR" "$STATE_DIR"
}

validate_ref() {
  local ref="$1"
  [[ -n "$ref" ]] || fail "empty git ref in manifest"
  [[ "$ref" != TODO_* ]] || fail "manifest ref '$ref' is a placeholder, update install-skills.sh before using this pack"
}

clone_or_update_repo() {
  local pack="$1"
  local repo_url="$2"
  local ref="$3"
  local dest="$4"

  validate_ref "$ref"

  if [[ -d "$dest/.git" ]]; then
    local existing_remote
    existing_remote="$(git -C "$dest" remote get-url origin 2>/dev/null || true)"
    if [[ "$existing_remote" != "$repo_url" ]]; then
      fail "destination '$dest' already exists with remote '$existing_remote', expected '$repo_url'"
    fi
    log "updating $pack in $dest"
    git -C "$dest" fetch --tags --force origin >/dev/null 2>&1
  else
    if [[ -e "$dest" ]]; then
      fail "destination '$dest' exists but is not a git checkout"
    fi
    log "cloning $pack into $dest"
    git clone --quiet "$repo_url" "$dest"
  fi

  git -C "$dest" checkout --quiet "$ref"
}

link_skill() {
  local skill_source="$1"
  local skill_name="$2"
  local dest="$WORKSPACE_SKILLS_DIR/$skill_name"

  [[ -f "$skill_source/SKILL.md" ]] || fail "skill '$skill_name' missing SKILL.md at '$skill_source'"

  mkdir -p "$WORKSPACE_SKILLS_DIR"
  rm -rf "$dest"
  ln -s "$skill_source" "$dest"
  log "linked skill '$skill_name' -> $skill_source"
}

install_pack_from_manifest() {
  local entry="$1"
  IFS='|' read -r pack repo_url ref dest description <<<"$entry"
  log "installing pack '$pack': $description"
  clone_or_update_repo "$pack" "$repo_url" "$ref" "$dest"
}

install_selected_skills() {
  # Trail of Bits: keep the required secure workflow plus a few audit-deepening
  # helpers from the same maintained repository.
  link_skill "$TRAILOFBITS_HOME/plugins/building-secure-contracts/skills/secure-workflow-guide" "secure-workflow-guide"
  link_skill "$TRAILOFBITS_HOME/plugins/building-secure-contracts/skills/token-integration-analyzer" "token-integration-analyzer"
  link_skill "$TRAILOFBITS_HOME/plugins/entry-point-analyzer/skills/entry-point-analyzer" "entry-point-analyzer"
  link_skill "$TRAILOFBITS_HOME/plugins/building-secure-contracts/skills/guidelines-advisor" "guidelines-advisor"

  # forefy ships a real skill layout rooted at `.context/skills/...`; expose the
  # primary smart-contract audit skill to Codex via repo-scoped discovery while
  # preserving the source layout the skill expects internally.
  link_skill "$FOREFY_CONTEXT_HOME/skills/smart-contract-audit" "smart-contract-audit"
  link_skill "$FOREFY_CONTEXT_HOME/skills/foundry-poc" "foundry-poc"
  link_skill "$FOREFY_CONTEXT_HOME/skills/tiny-auditor" "tiny-auditor"
}

write_install_summary() {
  local summary_file="$STATE_DIR/installed-skills.txt"
  {
    printf 'installed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'workspace_skills_dir=%s\n' "$WORKSPACE_SKILLS_DIR"
    printf 'trailofbits_home=%s\n' "$TRAILOFBITS_HOME"
    printf 'forefy_context_home=%s\n' "$FOREFY_CONTEXT_HOME"
    printf 'skills:\n'
    find "$WORKSPACE_SKILLS_DIR" -mindepth 1 -maxdepth 1 -type l -printf '  - %f -> %l\n' | sort
  } >"$summary_file"
  log "wrote install summary to $summary_file"
}

main() {
  require_cmd git
  require_cmd ln
  require_cmd find
  ensure_parent_dirs

  for entry in "${PACKS[@]}"; do
    install_pack_from_manifest "$entry"
  done

  install_selected_skills
  write_install_summary
  log "skill installation complete"
}

main "$@"
