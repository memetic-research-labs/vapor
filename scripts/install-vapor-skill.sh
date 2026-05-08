#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OPENCODE_SKILL_DIR="$HOME/.opencode/skills/vapor-agent-memory"
CLAUDE_SKILL_DIR="$HOME/.claude/skills/vapor-agent-memory"
SOURCE_SKILL_DIR="$REPO_ROOT/.opencode/skills/vapor-agent-memory"

install_skill() {
    local target_dir="$1"
    local label="$2"

    if [ -d "$target_dir" ]; then
        echo "$label skill already exists at $target_dir (skipping)"
    else
        mkdir -p "$target_dir"
        cp "$SOURCE_SKILL_DIR/SKILL.md" "$target_dir/SKILL.md"
        echo "Installed $label skill to $target_dir"
    fi
}

if [ ! -f "$SOURCE_SKILL_DIR/SKILL.md" ]; then
    echo "Error: Source skill not found at $SOURCE_SKILL_DIR/SKILL.md" >&2
    exit 1
fi

install_skill "$OPENCODE_SKILL_DIR" "OpenCode"
install_skill "$CLAUDE_SKILL_DIR" "Claude Code"

echo ""
echo "Done. Both skills are now available to agents launched from this machine."
echo "Ensure Vapor is running and the session has been indexed before searching."
