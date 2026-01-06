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

CACHE_DIR="$REPO_ROOT/tmp/update-cache"
LAZYVIM_CACHE="$CACHE_DIR/LazyVim"
STARTER_CACHE="$CACHE_DIR/starter"
MASON_CACHE="$CACHE_DIR/mason-registry"
EXTRAS_CACHE_ROOT="$CACHE_DIR/extras"
RELEASE_CACHE_ROOT="$CACHE_DIR/releases"
CACHE_SCHEMA_VERSION="2"
STARTER_REPO="https://github.com/LazyVim/starter.git"

mkdir -p "$CACHE_DIR"
mkdir -p "$RELEASE_CACHE_ROOT"
USED_RELEASE_CACHE=0

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

echo "==> Preparing LazyVim cache..."
if [ ! -d "$LAZYVIM_CACHE/.git" ]; then
    git clone --filter=blob:none "$LAZYVIM_REPO" "$LAZYVIM_CACHE"
fi

git -C "$LAZYVIM_CACHE" fetch --tags --force --prune --depth 1 origin >/dev/null 2>&1 || {
    echo "Error: Failed to update LazyVim cache"
    exit 1
}

echo "==> Getting latest LazyVim release..."
LATEST_TAG=$(git -C "$LAZYVIM_CACHE" tag -l 'v[0-9]*' | sort -rV | head -1)

if [ -z "$LATEST_TAG" ]; then
    echo "Error: Could not determine latest LazyVim release"
    exit 1
fi

git -C "$LAZYVIM_CACHE" fetch --depth 1 origin "$LATEST_TAG" >/dev/null 2>&1 || {
    echo "Error: Failed to fetch LazyVim tag $LATEST_TAG"
    exit 1
}

LAZYVIM_COMMIT=$(git -C "$LAZYVIM_CACHE" rev-parse "$LATEST_TAG^{commit}" 2>/dev/null)

if [ -z "$LAZYVIM_COMMIT" ]; then
    echo "Error: Could not resolve commit for $LATEST_TAG"
    exit 1
fi

if [ -n "$VERIFY_PACKAGES" ]; then
    VERIFY_SUFFIX="verify"
else
    VERIFY_SUFFIX="noverify"
fi

RELEASE_CACHE_KEY="${LAZYVIM_COMMIT}-${CACHE_SCHEMA_VERSION}-${VERIFY_SUFFIX}"
RELEASE_CACHE_DIR="$RELEASE_CACHE_ROOT/$RELEASE_CACHE_KEY"

echo "==> Materializing LazyVim $LATEST_TAG ($LAZYVIM_COMMIT) ..."
mkdir -p "$TEMP_DIR/LazyVim"
git -C "$LAZYVIM_CACHE" archive "$LAZYVIM_COMMIT" | tar -x -C "$TEMP_DIR/LazyVim" || {
    echo "Error: Failed to extract LazyVim working tree"
    exit 1
}

LAZYVIM_VERSION="$LATEST_TAG"

echo "    Version: $LAZYVIM_VERSION"
echo "    Commit: $LAZYVIM_COMMIT"

# Fetch LazyVim starter configuration
echo "==> Fetching LazyVim starter..."
if [ ! -d "$STARTER_CACHE/.git" ]; then
    git clone --filter=blob:none "$STARTER_REPO" "$STARTER_CACHE" >/dev/null 2>&1 || {
        echo "Error: Failed to clone LazyVim starter"
        exit 1
    }
fi

git -C "$STARTER_CACHE" fetch --force --prune --depth 1 origin main >/dev/null 2>&1 || {
    echo "Error: Failed to update LazyVim starter cache"
    exit 1
}

git -C "$STARTER_CACHE" reset --hard FETCH_HEAD >/dev/null 2>&1

STARTER_COMMIT=$(git -C "$STARTER_CACHE" rev-parse HEAD)
echo "    Starter commit: $STARTER_COMMIT"

# Copy starter lazy.lua to data directory
if [ -f "$STARTER_CACHE/lua/config/lazy.lua" ]; then
    cp "$STARTER_CACHE/lua/config/lazy.lua" "$REPO_ROOT/data/starter-lazy.lua"
    echo "$STARTER_COMMIT" > "$REPO_ROOT/data/starter-version.txt"
    echo "    Copied starter lazy.lua"
else
    echo "Error: Could not find lua/config/lazy.lua in starter repository"
    exit 1
fi

if [ -z "${LAZYVIM_FORCE_REGEN:-}" ] \
    && [ -f "$RELEASE_CACHE_DIR/plugins.json" ] \
    && [ -f "$RELEASE_CACHE_DIR/dependencies.json" ] \
    && [ -f "$RELEASE_CACHE_DIR/treesitter.json" ]; then
    if [ -n "$VERIFY_PACKAGES" ] && [ ! -f "$RELEASE_CACHE_DIR/dependencies-verification-report.json" ]; then
        echo "==> Release cache missing verification report; regenerating"
    else
        echo "==> Using cached metadata for LazyVim commit $LAZYVIM_COMMIT"
        cp "$RELEASE_CACHE_DIR/plugins.json" "$REPO_ROOT/data/plugins.json"
        cp "$RELEASE_CACHE_DIR/dependencies.json" "$REPO_ROOT/data/dependencies.json"
        cp "$RELEASE_CACHE_DIR/treesitter.json" "$REPO_ROOT/data/treesitter.json"
        if [ -n "$VERIFY_PACKAGES" ]; then
            cp "$RELEASE_CACHE_DIR/dependencies-verification-report.json" "$REPO_ROOT/data/dependencies-verification-report.json"
        else
            rm -f "$REPO_ROOT/data/dependencies-verification-report.json"
        fi
        USED_RELEASE_CACHE=1
    fi
fi

if [ "$USED_RELEASE_CACHE" -eq 0 ]; then
    echo "==> Extracting plugin specifications..."
    echo "    (including user-defined plugins from ~/.config/nvim/lua/plugins/)"
    cd "$REPO_ROOT"

    export LUA_PATH="$SCRIPT_DIR/?.lua;${LUA_PATH:-}"

    if [ -n "$VERIFY_PACKAGES" ]; then
        export VERIFY_NIXPKGS_PACKAGES="1"
    fi

    echo "==> Extracting system dependencies with runtime mappings..."
    echo "==> Preparing Mason registry cache..."
    if [ ! -d "$MASON_CACHE/.git" ]; then
        git clone --filter=blob:none https://github.com/mason-org/mason-registry.git "$MASON_CACHE" >/dev/null 2>&1 || {
            echo "Warning: Failed to set up Mason registry cache"
            MASON_CACHE=""
        }
    fi

    if [ -n "$MASON_CACHE" ]; then
        git -C "$MASON_CACHE" fetch --force --prune --depth 1 origin main >/dev/null 2>&1 && \
        git -C "$MASON_CACHE" reset --hard FETCH_HEAD >/dev/null 2>&1 || {
            echo "Warning: Failed to update Mason registry cache"
            MASON_CACHE=""
        }
    fi

    echo "==> Running metadata extraction pipeline..."
    nvim --headless -u NONE -l "$SCRIPT_DIR/run-update.lua" \
        "$TEMP_DIR/LazyVim" \
        "$REPO_ROOT/data/plugins.json" \
        "$REPO_ROOT/data/dependencies.json" \
        "$REPO_ROOT/data/treesitter.json" \
        "${MASON_CACHE:-}" \
        "$LAZYVIM_VERSION" \
        "$LAZYVIM_COMMIT" \
        "$EXTRAS_CACHE_ROOT" || {
            echo "Error: Failed to extract metadata"
            exit 1
        }

    if ! jq . "$REPO_ROOT/data/plugins.json" > /dev/null 2>&1; then
        echo "Error: Generated plugins.json is not valid JSON"
        exit 1
    fi

    if ! jq . "$REPO_ROOT/data/dependencies.json" > /dev/null 2>&1; then
        echo "Error: Generated dependencies.json is not valid JSON"
        exit 1
    fi

    if ! jq . "$REPO_ROOT/data/treesitter.json" > /dev/null 2>&1; then
        echo "Error: Generated treesitter.json is not valid JSON"
        exit 1
    fi
fi

if [ -z "$VERIFY_PACKAGES" ]; then
    rm -f "$REPO_ROOT/data/dependencies-verification-report.json"
fi

if [ "$USED_RELEASE_CACHE" -eq 0 ]; then
    mkdir -p "$RELEASE_CACHE_DIR"
    cp "$REPO_ROOT/data/plugins.json" "$RELEASE_CACHE_DIR/plugins.json"
    cp "$REPO_ROOT/data/dependencies.json" "$RELEASE_CACHE_DIR/dependencies.json"
    cp "$REPO_ROOT/data/treesitter.json" "$RELEASE_CACHE_DIR/treesitter.json"
    if [ -n "$VERIFY_PACKAGES" ] && [ -f "$REPO_ROOT/data/dependencies-verification-report.json" ]; then
        cp "$REPO_ROOT/data/dependencies-verification-report.json" "$RELEASE_CACHE_DIR/dependencies-verification-report.json"
    else
        rm -f "$RELEASE_CACHE_DIR/dependencies-verification-report.json"
    fi
fi

# Check if we got any plugins
PLUGIN_COUNT=$(jq '.plugins | length' "$REPO_ROOT/data/plugins.json")
if [ "$PLUGIN_COUNT" -eq 0 ]; then
    echo "Error: No plugins found in generated JSON"
    exit 1
fi

echo "==> Found $PLUGIN_COUNT plugins"

# Check extraction report for unmapped plugins
UNMAPPED_COUNT=$(jq '.extraction_report.unmapped_plugins' "$REPO_ROOT/data/plugins.json" 2>/dev/null || echo "0")
MAPPED_COUNT=$(jq '.extraction_report.mapped_plugins' "$REPO_ROOT/data/plugins.json" 2>/dev/null || echo "0")
MULTI_MODULE_COUNT=$(jq '.extraction_report.multi_module_plugins' "$REPO_ROOT/data/plugins.json" 2>/dev/null || echo "0")

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
    SUGGESTIONS_COUNT=$(jq '.extraction_report.mapping_suggestions | length' "$REPO_ROOT/data/plugins.json" 2>/dev/null || echo "0")
    if [ "$SUGGESTIONS_COUNT" -gt 0 ]; then
        echo "    Generated $SUGGESTIONS_COUNT mapping suggestions"
        echo "    Review and add approved mappings to plugin-mappings.nix"
        echo ""
    fi
fi

# Get dependency stats
CORE_DEPS=$(jq '.core | length' "$REPO_ROOT/data/dependencies.json")
EXTRAS_WITH_DEPS=$(jq '.extras | keys | length' "$REPO_ROOT/data/dependencies.json")

# Get treesitter stats
CORE_PARSERS=$(jq '.core | length' "$REPO_ROOT/data/treesitter.json")
EXTRA_PARSERS=$(jq '[.extras | values[]] | length' "$REPO_ROOT/data/treesitter.json")

echo "==> Successfully updated plugins.json, dependencies.json, and treesitter-mappings.json"
echo "    Version: $LAZYVIM_VERSION"
echo "    Plugins: $PLUGIN_COUNT"
echo "    Core dependencies: $CORE_DEPS"
echo "    Extras with dependencies: $EXTRAS_WITH_DEPS"
echo "    Core parsers: $CORE_PARSERS"
echo "    Extra parsers: $EXTRA_PARSERS"

# Generate a summary of changes
if git diff --quiet data/plugins.json data/dependencies.json data/treesitter.json data/starter-lazy.lua data/starter-version.txt 2>/dev/null; then
    echo "==> No changes detected"
else
    echo "==> Changes detected:"
    git diff --stat data/plugins.json data/dependencies.json data/treesitter.json data/starter-lazy.lua data/starter-version.txt 2>/dev/null || true
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
