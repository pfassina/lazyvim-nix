#!/usr/bin/env bash
set -euo pipefail

# LazyVim plugin update script
# This script fetches the latest LazyVim plugin specifications and generates plugins.json
# 
# Options:
#   --verify    Enable nixpkgs package verification for mapping suggestions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMP_DIR=$(mktemp -d)
LAZYVIM_REPO="https://github.com/LazyVim/LazyVim.git"

# Parse command line arguments
VERIFY_PACKAGES=""
for arg in "$@"; do
    case $arg in
        --verify)
            VERIFY_PACKAGES="1"
            echo "==> Package verification enabled"
            ;;
    esac
done

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "==> Cloning LazyVim repository..."
git clone --depth 1 "$LAZYVIM_REPO" "$TEMP_DIR/LazyVim"

echo "==> Getting LazyVim version..."
cd "$TEMP_DIR/LazyVim"
LAZYVIM_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "main")
LAZYVIM_COMMIT=$(git rev-parse HEAD)

echo "    Version: $LAZYVIM_VERSION"
echo "    Commit: $LAZYVIM_COMMIT"

echo "==> Extracting plugin specifications..."
cd "$REPO_ROOT"

# Add suggest-mappings.lua to the Lua path
export LUA_PATH="$SCRIPT_DIR/?.lua;${LUA_PATH:-}"

# Set verification environment variable if requested
if [ -n "$VERIFY_PACKAGES" ]; then
    export VERIFY_NIXPKGS_PACKAGES="1"
fi

# Run the enhanced plugin extractor with two-pass processing
nvim --headless -u NONE \
    -c "set runtimepath+=$TEMP_DIR/LazyVim" \
    -c "luafile $SCRIPT_DIR/extract-plugins.lua" \
    -c "lua ExtractLazyVimPlugins('$TEMP_DIR/LazyVim', '$REPO_ROOT/plugins.json.tmp', '$LAZYVIM_VERSION', '$LAZYVIM_COMMIT')" \
    -c "quit" 2>/dev/null || {
        echo "Error: Failed to extract LazyVim plugins"
        exit 1
    }

# Validate the generated JSON
if ! jq . "$REPO_ROOT/plugins.json.tmp" > /dev/null 2>&1; then
    echo "Error: Generated plugins.json is not valid JSON"
    exit 1
fi

# Check if we got any plugins
PLUGIN_COUNT=$(jq '.plugins | length' "$REPO_ROOT/plugins.json.tmp")
if [ "$PLUGIN_COUNT" -eq 0 ]; then
    echo "Error: No plugins found in generated JSON"
    exit 1
fi

echo "==> Found $PLUGIN_COUNT plugins"

# Check extraction report for unmapped plugins
UNMAPPED_COUNT=$(jq '.extraction_report.unmapped_plugins' "$REPO_ROOT/plugins.json.tmp" 2>/dev/null || echo "0")
MAPPED_COUNT=$(jq '.extraction_report.mapped_plugins' "$REPO_ROOT/plugins.json.tmp" 2>/dev/null || echo "0")
MULTI_MODULE_COUNT=$(jq '.extraction_report.multi_module_plugins' "$REPO_ROOT/plugins.json.tmp" 2>/dev/null || echo "0")

echo "==> Extraction Report:"
echo "    Mapped plugins: $MAPPED_COUNT"
echo "    Unmapped plugins: $UNMAPPED_COUNT"
echo "    Multi-module plugins: $MULTI_MODULE_COUNT"

# Handle unmapped plugins
if [ "$UNMAPPED_COUNT" -gt 0 ]; then
    echo ""
    echo "⚠️  WARNING: $UNMAPPED_COUNT plugins are unmapped"
    echo "    Check mapping-analysis-report.md for suggested mappings"
    echo "    Consider updating plugin-mappings.nix before committing"
    echo ""
    
    # Show suggested mappings count if available
    SUGGESTIONS_COUNT=$(jq '.extraction_report.mapping_suggestions | length' "$REPO_ROOT/plugins.json.tmp" 2>/dev/null || echo "0")
    if [ "$SUGGESTIONS_COUNT" -gt 0 ]; then
        echo "    Generated $SUGGESTIONS_COUNT mapping suggestions"
        echo "    Review and add approved mappings to plugin-mappings.nix"
        echo ""
    fi
fi

# Move the temporary file to the final location
mv "$REPO_ROOT/plugins.json.tmp" "$REPO_ROOT/plugins.json"

echo "==> Successfully updated plugins.json"
echo "    Version: $LAZYVIM_VERSION"
echo "    Plugins: $PLUGIN_COUNT"

# Generate a summary of changes if plugins.json already existed
if git diff --quiet plugins.json 2>/dev/null; then
    echo "==> No changes detected"
else
    echo "==> Changes detected:"
    git diff --stat plugins.json 2>/dev/null || true
fi

# Remind about next steps if there are unmapped plugins
if [ "$UNMAPPED_COUNT" -gt 0 ]; then
    echo ""
    echo "📋 Next Steps:"
    echo "1. Review mapping-analysis-report.md"
    echo "2. Update plugin-mappings.nix with approved mappings"
    echo "3. Re-run this script to regenerate plugins.json"
    echo "4. Commit both plugins.json and plugin-mappings.nix together"
fi