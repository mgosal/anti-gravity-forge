#!/bin/bash

# codebase-index.sh — Generates context.json for the Forge pipeline

if [ $# -lt 1 ]; then
  echo "Usage: $0 <forge-dir>"
  exit 1
fi

FORGE_DIR="$1"
META_DIR="${FORGE_DIR}/.forge-meta"
mkdir -p "$META_DIR"

cd "$FORGE_DIR"

# 1. Check for blank repo
FILE_COUNT=$(find . -type f -not -path '*/.git/*' -not -path '*/.forge-meta/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' | wc -l | tr -d ' ')
BLANK_REPO=false
if [ "$FILE_COUNT" -le 2 ]; then
  # If it's just README and/or .gitignore, treat as blank
  BLANK_REPO=true
fi

# 2. Extract File Tree
FILE_TREE=$(find . -type f -not -path '*/.git/*' -not -path '*/.forge-meta/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' | sort | head -n 300)

# 3. Detect Languages Based on Extensions
LANGUAGES=$(echo "$FILE_TREE" | awk -F. '{if (NF>1) print $NF}' | sort | uniq -c | sort -nr | head -n 5 | awk '{print $2}' | jq -R . | jq -s .)

# 4. Detect Build/Test Commands
BUILD_CMD=""
TEST_CMD=""

if [ -f "package.json" ]; then
  if grep -q '"build"' "package.json"; then BUILD_CMD="npm run build"; fi
  if grep -q '"test"' "package.json"; then TEST_CMD="npm test"; fi
elif [ -f "Cargo.toml" ]; then
  BUILD_CMD="cargo build"
  TEST_CMD="cargo test"
elif [ -f "go.mod" ]; then
  BUILD_CMD="go build ./..."
  TEST_CMD="go test ./..."
elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then
  if [ -f "Makefile" ] && grep -q '^test:' "Makefile"; then
    TEST_CMD="make test"
  else
    TEST_CMD="python -m pytest"
  fi
fi

# Fallback to Makefile if no specific ecosystem matched
if [ -z "$BUILD_CMD" ] && [ -f "Makefile" ] && grep -q '^build:' "Makefile"; then BUILD_CMD="make build"; fi
if [ -z "$TEST_CMD" ] && [ -f "Makefile" ] && grep -q '^test:' "Makefile"; then TEST_CMD="make test"; fi

# 5. Output JSON
jq -n \
  --arg blank "$BLANK_REPO" \
  --arg bcmd "$BUILD_CMD" \
  --arg tcmd "$TEST_CMD" \
  --argjson langs "$LANGUAGES" \
  --arg tree "$FILE_TREE" \
  '{
    blank_repo: ($blank == "true"),
    build_cmd: $bcmd,
    test_cmd: $tcmd,
    languages: $langs,
    file_tree: $tree
  }' > "${META_DIR}/context.json"

echo "Indexed repository context. Blank: $BLANK_REPO"
