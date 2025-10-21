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
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --verify         Enable nixpkgs package verification"
            echo "  --help           Show this help message"
            exit 0
            ;;
    esac
done

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "==> Getting latest LazyVim release..."
# Use git ls-remote to avoid GitHub API rate limits
LATEST_TAG=$(git ls-remote --tags https://github.com/LazyVim/LazyVim 2>/dev/null | \
    sed 's/.*refs\/tags\///' | \
    grep -E '^v[0-9]+\.[0-9]+' | \
    sort -rV | \
    head -1)

if [ -z "$LATEST_TAG" ]; then
    echo "Error: Could not fetch latest LazyVim release"
    exit 1
fi

echo "==> Cloning LazyVim $LATEST_TAG..."
git clone --depth 1 --branch "$LATEST_TAG" "$LAZYVIM_REPO" "$TEMP_DIR/LazyVim"

echo "==> Getting LazyVim version..."
cd "$TEMP_DIR/LazyVim"
LAZYVIM_VERSION="$LATEST_TAG"
LAZYVIM_COMMIT=$(git rev-parse HEAD)

echo "    Version: $LAZYVIM_VERSION"
echo "    Commit: $LAZYVIM_COMMIT"

echo "==> Extracting plugin specifications..."
echo "    (including user-defined plugins from ~/.config/nvim/lua/plugins/)"
cd "$REPO_ROOT"

# Add suggest-mappings.lua and scan-user-plugins.lua to the Lua path
export LUA_PATH="$SCRIPT_DIR/?.lua;${LUA_PATH:-}"

# Set verification environment variable if requested
if [ -n "$VERIFY_PACKAGES" ]; then
    export VERIFY_NIXPKGS_PACKAGES="1"
fi

# Run the enhanced plugin extractor with two-pass processing
nvim --headless -u NONE \
    -c "set runtimepath+=$TEMP_DIR/LazyVim" \
    -c "luafile $SCRIPT_DIR/extract-plugins.lua" \
    -c "lua ExtractLazyVimPlugins('$TEMP_DIR/LazyVim', '$REPO_ROOT/data/plugins.json.tmp', '$LAZYVIM_VERSION', '$LAZYVIM_COMMIT')" \
    -c "quit" || {
        echo "Error: Failed to extract LazyVim plugins"
        exit 1
    }

# Validate the generated JSON
if ! jq . "$REPO_ROOT/data/plugins.json.tmp" > /dev/null 2>&1; then
    echo "Error: Generated plugins.json is not valid JSON"
    exit 1
fi

echo "==> Extracting treesitter parser mappings..."
# Extract treesitter mappings from LazyVim
cd "$REPO_ROOT"
lua scripts/extract-treesitter.lua "$TEMP_DIR/LazyVim" || {
    echo "Error: Failed to extract treesitter mappings"
    exit 1
}

# Validate the generated treesitter mappings JSON
if ! jq . "$REPO_ROOT/data/treesitter.json" > /dev/null 2>&1; then
    echo "Error: Generated treesitter-mappings.json is not valid JSON"
    exit 1
fi

# Check if we got any plugins
PLUGIN_COUNT=$(jq '.plugins | length' "$REPO_ROOT/data/plugins.json.tmp")
if [ "$PLUGIN_COUNT" -eq 0 ]; then
    echo "Error: No plugins found in generated JSON"
    exit 1
fi

echo "==> Found $PLUGIN_COUNT plugins"

# Check extraction report for unmapped plugins
UNMAPPED_COUNT=$(jq '.extraction_report.unmapped_plugins' "$REPO_ROOT/data/plugins.json.tmp" 2>/dev/null || echo "0")
MAPPED_COUNT=$(jq '.extraction_report.mapped_plugins' "$REPO_ROOT/data/plugins.json.tmp" 2>/dev/null || echo "0")
MULTI_MODULE_COUNT=$(jq '.extraction_report.multi_module_plugins' "$REPO_ROOT/data/plugins.json.tmp" 2>/dev/null || echo "0")

echo "==> Extraction Report:"
echo "    Mapped plugins: $MAPPED_COUNT"
echo "    Unmapped plugins: $UNMAPPED_COUNT"
echo "    Multi-module plugins: $MULTI_MODULE_COUNT"

# Handle unmapped plugins
if [ "$UNMAPPED_COUNT" -gt 0 ]; then
    echo ""
    echo "⚠️  WARNING: $UNMAPPED_COUNT plugins are unmapped"
    echo "    Check data/mapping-analysis-report.md for suggested mappings"
    echo "    Consider updating plugin-mappings.nix before committing"
    echo ""
    
    # Show suggested mappings count if available
    SUGGESTIONS_COUNT=$(jq '.extraction_report.mapping_suggestions | length' "$REPO_ROOT/data/plugins.json.tmp" 2>/dev/null || echo "0")
    if [ "$SUGGESTIONS_COUNT" -gt 0 ]; then
        echo "    Generated $SUGGESTIONS_COUNT mapping suggestions"
        echo "    Review and add approved mappings to plugin-mappings.nix"
        echo ""
    fi
fi

# Move the temporary file to the final location
mv "$REPO_ROOT/data/plugins.json.tmp" "$REPO_ROOT/data/plugins.json"

# Get treesitter stats
CORE_PARSERS=$(jq '.core | length' "$REPO_ROOT/data/treesitter.json")
EXTRA_PARSERS=$(jq '[.extras | values[]] | length' "$REPO_ROOT/data/treesitter.json")

echo "==> Successfully updated plugins.json and treesitter-mappings.json"
echo "    Version: $LAZYVIM_VERSION"
echo "    Plugins: $PLUGIN_COUNT"
echo "    Core parsers: $CORE_PARSERS"
echo "    Extra parsers: $EXTRA_PARSERS"

# Generate a summary of changes
if git diff --quiet data/plugins.json data/treesitter.json 2>/dev/null; then
    echo "==> No changes detected"
else
    echo "==> Changes detected:"
    git diff --stat data/plugins.json data/treesitter.json 2>/dev/null || true
fi

# Remind about next steps if there are unmapped plugins
if [ "$UNMAPPED_COUNT" -gt 0 ]; then
    echo ""
    echo "📋 Next Steps:"
    echo "1. Review mapping-analysis-report.md"
    echo "2. Update plugin-mappings.nix with approved mappings"
    echo "3. Re-run this script to regenerate plugins.json"
    echo "4. Commit both data/plugins.json and data/mappings.json together"
fi

# Note: Version information is now fetched during extraction
echo "==> Plugin extraction with version information completed"