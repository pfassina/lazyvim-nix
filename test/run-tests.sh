#!/usr/bin/env bash
# Comprehensive test runner for LazyVim flake
set -euo pipefail

# Get the directory containing this script and the project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🧪 LazyVim Comprehensive Test Suite"
echo "===================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}!${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Test execution tracking
total_tests=0
passed_tests=0
failed_tests=0

run_test_suite() {
    local suite_name="$1"
    local description="$2"
    local nix_attr="$3"

    echo
    echo "📋 $description"
    echo "$(printf '%*s' "${#description}" '' | tr ' ' '-')"

    info "Running $suite_name tests..."

    if nix-build "$SCRIPT_DIR" --no-out-link -A "$nix_attr" >/dev/null 2>&1; then
        success "$suite_name tests PASSED"
        ((passed_tests++))
    else
        error "$suite_name tests FAILED"
        echo "  Run manually for details: nix-build $SCRIPT_DIR -A $nix_attr"
        ((failed_tests++))
    fi
    ((total_tests++))
}

run_individual_test() {
    local test_name="$1"
    local test_command="$2"

    echo -n "  Testing $test_name... "

    if eval "$test_command" >/dev/null 2>&1; then
        success "PASS"
        ((passed_tests++))
    else
        error "FAIL"
        ((failed_tests++))
    fi
    ((total_tests++))
}

# Parse command line arguments
RUN_SMOKE=true
RUN_UNIT=true
RUN_INTEGRATION=true
RUN_PROPERTY=true
RUN_REGRESSION=true
RUN_E2E=true
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --smoke-only)
            RUN_UNIT=false
            RUN_INTEGRATION=false
            RUN_PROPERTY=false
            RUN_REGRESSION=false
            RUN_E2E=false
            shift
            ;;
        --unit-only)
            RUN_SMOKE=false
            RUN_INTEGRATION=false
            RUN_PROPERTY=false
            RUN_REGRESSION=false
            RUN_E2E=false
            shift
            ;;
        --integration-only)
            RUN_SMOKE=false
            RUN_UNIT=false
            RUN_PROPERTY=false
            RUN_REGRESSION=false
            RUN_E2E=false
            shift
            ;;
        --no-e2e)
            RUN_E2E=false
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  --smoke-only      Run only smoke tests"
            echo "  --unit-only       Run only unit tests"
            echo "  --integration-only Run only integration tests"
            echo "  --no-e2e          Skip end-to-end tests"
            echo "  --verbose, -v     Verbose output"
            echo "  --help, -h        Show this help"
            echo
            echo "Test suites:"
            echo "  🔥 Smoke tests    - Quick validation of basic functionality"
            echo "  🧪 Unit tests     - Test individual functions and components"
            echo "  🔗 Integration    - Test module integration and configuration"
            echo "  ⚡ Property tests - Test edge cases and error conditions"
            echo "  🛡️  Regression    - Test for backwards compatibility"
            echo "  🎯 End-to-end    - Test real Neovim configurations"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "Test Configuration:"
echo "  Project root: $PROJECT_ROOT"
echo "  Test directory: $SCRIPT_DIR"
echo "  Verbose: $VERBOSE"

# Quick smoke test first
if $RUN_SMOKE; then
    echo
    echo "🔥 Smoke Test"
    echo "============="

    info "Running quick validation..."

    if nix-build "$SCRIPT_DIR" --no-out-link -A smokeTest >/dev/null 2>&1; then
        success "Smoke test PASSED"
        ((passed_tests++))
    else
        error "Smoke test FAILED - basic functionality broken!"
        echo "Stopping test execution due to smoke test failure."
        exit 1
    fi
    ((total_tests++))
fi

# Unit tests
if $RUN_UNIT; then
    run_test_suite "Unit" "Unit Tests - Core Functions" "unitTests"
fi

# Integration tests
if $RUN_INTEGRATION; then
    run_test_suite "Integration" "Integration Tests - Module Integration" "integrationTests"
fi

# Property-based tests
if $RUN_PROPERTY; then
    run_test_suite "Property" "Property Tests - Edge Cases & Error Conditions" "propertyTests"
fi

# Regression tests
if $RUN_REGRESSION; then
    run_test_suite "Regression" "Regression Tests - Backwards Compatibility" "regressionTests"
fi

# End-to-end tests
if $RUN_E2E; then
    run_test_suite "End-to-End" "End-to-End Tests - Real Configurations" "e2eTests"
fi

# Additional file structure validation (classic tests)
echo
echo "📁 File Structure Validation"
echo "============================"

run_individual_test "flake.nix exists" "[ -f '$PROJECT_ROOT/flake.nix' ]"
run_individual_test "nix/module.nix exists" "[ -f '$PROJECT_ROOT/nix/module.nix'' ]"
run_individual_test "data/plugins.json exists" "[ -f '$PROJECT_ROOT/data/plugins.json' ]"
run_individual_test "data/mappings.json exists" "[ -f '$PROJECT_ROOT/data/mappings.json' ]"
run_individual_test "update script exists" "[ -x '$PROJECT_ROOT/scripts/update-plugins.sh' ]"

echo
echo "🔍 JSON and Nix Validation"
echo "=========================="

run_individual_test "data/plugins.json is valid JSON" "jq empty '$PROJECT_ROOT/data/plugins.json'"
run_individual_test "data/plugins.json has plugins" "[ \$(jq '.plugins | length' '$PROJECT_ROOT/data/plugins.json') -gt 0 ]"
run_individual_test "data/mappings.json is valid JSON" "jq empty '$PROJECT_ROOT/data/mappings.json'"
run_individual_test "flake.nix is valid" "cd '$PROJECT_ROOT' && nix flake show --no-update-lock-file >/dev/null"

# Summary
echo
echo "📊 Test Results Summary"
echo "======================="
echo "Total test suites/tests: $total_tests"
echo "Passed: $passed_tests"
echo "Failed: $failed_tests"

if [ $failed_tests -eq 0 ]; then
    echo
    success "🎉 All tests passed! LazyVim flake is working correctly."
    echo
    echo "Next steps for manual validation:"
    echo "  1. Add this flake to your NixOS/home-manager configuration"
    echo "  2. Enable programs.lazyvim.enable = true"
    echo "  3. Rebuild your configuration"
    echo "  4. Run 'nvim' and verify LazyVim loads properly"
    echo "  5. Check that plugins are working and Mason is disabled"
    echo "  6. Test your language servers and tools"
    exit 0
else
    echo
    error "❌ $failed_tests test(s) failed. Please review the output above."
    echo
    echo "Debugging tips:"
    echo "  • Run with --verbose for more details"
    echo "  • Test individual suites: nix-build test/ -A <suiteName>Tests"
    echo "  • Check the test logs for specific error messages"
    echo "  • Verify your nixpkgs version is compatible"
    exit 1
fi