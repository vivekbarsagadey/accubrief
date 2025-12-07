#!/bin/bash
# Spell check script for Algo Trading System
# This script runs spell checking across the entire project

echo "🔍 Running spell check across the project..."
echo ""

# Check if cspell is installed
if ! command -v cspell &> /dev/null; then
    echo "❌ cspell is not installed."
    echo "📦 Installing cspell globally..."
    npm install -g cspell
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to install cspell. Please install it manually:"
        echo "   npm install -g cspell"
        exit 1
    fi
    echo "✅ cspell installed successfully!"
    echo ""
fi

# Run spell check
echo "Running spell check on:"
echo "  - Documentation files (docs/**/*.md)"
echo "  - Python files (backend/**/*.py)"
echo "  - Configuration files (*.json, *.yaml, *.toml)"
echo ""

cspell "docs/**/*.md" \
       "backend/**/*.py" \
       "*.md" \
       "*.json" \
       "*.yaml" \
       "*.toml" \
       --config ./cspell.json \
       --no-progress \
       --show-context

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Spell check completed successfully! No spelling errors found."
    exit 0
else
    echo ""
    echo "⚠️  Spell check found some issues. Please review the output above."
    echo ""
    echo "To add words to the dictionary, edit: cspell.json or .vscode/settings.json"
    exit 1
fi
