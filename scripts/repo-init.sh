#!/bin/bash
set -euo pipefail

# repo-init.sh — Initialize a repository for Iron Tech Forge
# Usage: ./scripts/repo-init.sh <owner/repo> <issue-id>

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source .env if it exists
if [ -f "${PROJECT_ROOT}/.env" ]; then
  set -a
  source "${PROJECT_ROOT}/.env"
  set +a
elif [ -f "${PROJECT_ROOT}/.env.local" ]; then
  set -a
  source "${PROJECT_ROOT}/.env.local"
  set +a
fi

if [ $# -lt 2 ]; then
  echo "Usage: $0 <owner/repo> <issue-id>"
  exit 1
fi

REPO="$1"
ISSUE_ID="$2"
CONFIG_FILE="${PROJECT_ROOT}/.forge-master/config.yml"

# Extract labels from config.yml or use defaults
LABEL_TRIGGER=$(grep 'trigger:' "$CONFIG_FILE" | awk '{print $2}' | tr -d '"' || echo "forge-fix")
LABEL_IN_PROGRESS=$(grep 'in_progress:' "$CONFIG_FILE" | awk '{print $2}' | tr -d '"' || echo "forge-in-progress")
LABEL_PR_READY=$(grep 'pr_ready:' "$CONFIG_FILE" | awk '{print $2}' | tr -d '"' || echo "forge-pr-ready")
LABEL_NEEDS_HUMAN=$(grep 'needs_human:' "$CONFIG_FILE" | awk '{print $2}' | tr -d '"' || echo "forge-needs-human")

echo "Initializing labels for ${REPO}..."

# Define labels and colors
declare -A LABELS
LABELS["$LABEL_TRIGGER"]="0E8A16"
LABELS["$LABEL_IN_PROGRESS"]="FBCA04"
LABELS["$LABEL_NEEDS_HUMAN"]="D93F0B"
LABELS["$LABEL_PR_READY"]="1D76DB"

for L in "${!LABELS[@]}"; do
  COLOR="${LABELS[$L]}"
  echo "Checking label: $L"
  # Try to create, if exists it will fail gently
  gh label create "$L" --color "$COLOR" -R "$REPO" 2>/dev/null || \
  gh label edit "$L" --color "$COLOR" -R "$REPO" 2>/dev/null || true
done

gh issue comment "$ISSUE_ID" -R "$REPO" --body "✅ **Iron Tech Forge initialized!** 

I've created the necessary labels in this repository:
- \`$LABEL_TRIGGER\`: Add this label to any issue you want me to work on.
- \`$LABEL_IN_PROGRESS\`: I'll add this when I start working.
- \`$LABEL_NEEDS_HUMAN\`: I'll add this if I get stuck.

Happy forging! ⚒️"

gh issue close "$ISSUE_ID" -R "$REPO"

echo "✅ Repository ${REPO} initialized."
