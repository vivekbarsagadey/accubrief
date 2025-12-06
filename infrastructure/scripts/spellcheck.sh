#!/bin/bash

# AccuBrief Spell Check Script
# This script runs cspell to check spelling across the project
# Usage: ./infrastructure/scripts/spellcheck.sh [options]
#
# Options:
#   --fix       Interactively fix spelling errors
#   --quiet     Only show errors (no progress)
#   --files     Check only specific files (comma-separated)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

# Check if cspell is installed
if ! command -v cspell &> /dev/null; then
    echo -e "${YELLOW}cspell is not installed. Installing...${NC}"
    npm install -g cspell
fi

# Parse arguments
FIX_MODE=false
QUIET_MODE=false
SPECIFIC_FILES=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --fix)
            FIX_MODE=true
            shift
            ;;
        --quiet)
            QUIET_MODE=true
            shift
            ;;
        --files)
            SPECIFIC_FILES="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${GREEN}🔍 AccuBrief Spell Check${NC}"
echo "========================="

# Build cspell command
CSPELL_CMD="cspell"

if [ "$QUIET_MODE" = true ]; then
    CSPELL_CMD="$CSPELL_CMD --quiet"
fi

# File patterns to check
FILE_PATTERNS=(
    "**/*.md"
    "**/*.py"
    "**/*.ts"
    "**/*.tsx"
    "**/*.js"
    "**/*.jsx"
    "**/*.json"
    "**/*.yaml"
    "**/*.yml"
)

# Directories to exclude
EXCLUDE_PATTERNS=(
    "node_modules/**"
    ".git/**"
    "**/__pycache__/**"
    "**/.venv/**"
    "**/venv/**"
    "**/dist/**"
    "**/build/**"
    "**/*.min.js"
    "**/package-lock.json"
)

# Build exclude args
EXCLUDE_ARGS=""
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude '$pattern'"
done

if [ -n "$SPECIFIC_FILES" ]; then
    # Check specific files
    IFS=',' read -ra FILES <<< "$SPECIFIC_FILES"
    for file in "${FILES[@]}"; do
        echo -e "${YELLOW}Checking: $file${NC}"
        eval "$CSPELL_CMD '$file'" || true
    done
else
    # Check all files matching patterns
    echo -e "${YELLOW}Checking files...${NC}"
    echo ""
    
    # Run cspell with configuration
    RESULT=0
    eval "$CSPELL_CMD \
        --config '.vscode/settings.json' \
        --no-progress \
        $EXCLUDE_ARGS \
        '**/*.{md,py,ts,tsx,js,jsx,json,yaml,yml}'" || RESULT=$?
    
    if [ $RESULT -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✅ No spelling errors found!${NC}"
    else
        echo ""
        echo -e "${RED}❌ Spelling errors detected. Review the output above.${NC}"
        echo ""
        echo "To add words to the dictionary, update .vscode/settings.json:"
        echo "  \"cSpell.words\": [\"your-word\"]"
        echo ""
        echo "Or add inline comments:"
        echo "  # cspell:ignore yourword"
        echo "  // cspell:ignore yourword"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}Spell check complete!${NC}"
