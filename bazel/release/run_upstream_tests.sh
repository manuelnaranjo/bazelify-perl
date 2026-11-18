#!/usr/bin/env bash
# run_upstream_tests.sh - Execute Perl upstream unit test suite across target platforms
set -euo pipefail

TARBALL=""
TEST_ARCHIVE=""
TEST_MODE="${3:-core}"

# 1. Parse arguments or discover candidate archives
for arg in "$@"; do
    if [[ "$arg" == *test-suite*.tar.gz ]]; then
        TEST_ARCHIVE="$arg"
    elif [[ "$arg" == *.tar.gz ]]; then
        TARBALL="$arg"
    fi
done

if [ -z "$TARBALL" ]; then
    for candidate in dist/perl-5*.tar.gz bazel-out/*/bin/bazel/release/perl-5*.tar.gz bazel/release/perl-5*.tar.gz ./perl-5*.tar.gz; do
        if [ -f "$candidate" ] && [[ "$candidate" != *test-suite* ]]; then
            TARBALL="$candidate"
            break
        fi
    done
fi

if [ -z "$TARBALL" ] || [ ! -f "$TARBALL" ]; then
    echo "Error: Target distribution tarball not found! (searched args: $@)" >&2
    exit 1
fi

TARBALL="$(cd "$(dirname "$TARBALL")" && pwd)/$(basename "$TARBALL")"

if [ -z "$TEST_ARCHIVE" ]; then
    for candidate in dist/perl-test-suite.tar.gz bazel-bin/bazel/release/perl-test-suite.tar.gz bazel-out/*/bin/bazel/release/perl-test-suite.tar.gz ./perl-test-suite.tar.gz; do
        if [ -f "$candidate" ]; then
            TEST_ARCHIVE="$candidate"
            break
        fi
    done
fi

if [ -n "$TEST_ARCHIVE" ]; then
    if [ ! -f "$TEST_ARCHIVE" ]; then
        echo "Error: Test suite archive '$TEST_ARCHIVE' not found!" >&2
        ls -la dist/ 2>/dev/null || true
        exit 1
    fi
    TEST_ARCHIVE="$(cd "$(dirname "$TEST_ARCHIVE")" && pwd)/$(basename "$TEST_ARCHIVE")"
fi

WORKDIR="${TEST_TMPDIR:-$(mktemp -d)}/upstream_tests"
mkdir -p "$WORKDIR"

echo "================================================================="
echo "Perl Upstream Unit Test Runner"
echo "Target Tarball:   ${TARBALL}"
echo "Test Archive:     ${TEST_ARCHIVE:-<local sources>}"
echo "Working Dir:      ${WORKDIR}"
echo "Mode:             ${TEST_MODE}"
echo "================================================================="

# 2. Extract distribution
DIST_DIR="$WORKDIR/dist"
mkdir -p "$DIST_DIR"
tar -xzf "$TARBALL" -C "$DIST_DIR"

PERL_ROOT=""
for d in "$DIST_DIR"/*; do
    if [ -d "$d" ]; then
        PERL_ROOT="$d"
        break
    fi
done

if [ -z "$PERL_ROOT" ] || [ ! -x "$PERL_ROOT/bin/perl" ]; then
    echo "Error: Failed to find executable perl binary in $DIST_DIR" >&2
    exit 1
fi

PERL_BIN="$PERL_ROOT/bin/perl"
echo "Found Perl interpreter: $PERL_BIN"
"$PERL_BIN" -V

# 3. Setup test workspace
RUN_DIR="$WORKDIR/run"
mkdir -p "$RUN_DIR"

if [ -n "$TEST_ARCHIVE" ] && [ -f "$TEST_ARCHIVE" ]; then
    echo "Extracting test suite archive ${TEST_ARCHIVE}..."
    tar -xzf "$TEST_ARCHIVE" -C "$RUN_DIR"
else
    # Fallback to local checkout if available
    LOCAL_PERL_SRC=""
    for candidate in external/+perl_dist+perl bazel-main/external/+perl_dist+perl; do
        if [ -d "$candidate/t" ]; then
            LOCAL_PERL_SRC="$candidate"
            break
        fi
    done

    if [ -n "$LOCAL_PERL_SRC" ]; then
        echo "Using local Perl sources from ${LOCAL_PERL_SRC}..."
        cp -r "$LOCAL_PERL_SRC/t" "$RUN_DIR/"
        cp "$LOCAL_PERL_SRC/TestInit.pm" "$RUN_DIR/"
        for d in cpan dist ext Porting; do
            if [ -d "$LOCAL_PERL_SRC/$d" ]; then
                cp -r "$LOCAL_PERL_SRC/$d" "$RUN_DIR/"
            fi
        done
    else
        echo "Error: Neither test suite archive nor local source tree found!" >&2
        exit 1
    fi
fi

# 4. Stage libraries into test run tree
mkdir -p "$RUN_DIR/lib" "$RUN_DIR/lib/auto"
LIB_VER_DIR=""
for candidate in "$PERL_ROOT/lib"/5.*; do
    if [ -d "$candidate" ]; then
        LIB_VER_DIR="$candidate"
        break
    fi
done

if [ -n "$LIB_VER_DIR" ] && [ -d "$LIB_VER_DIR" ]; then
    cp -r "$LIB_VER_DIR"/* "$RUN_DIR/lib/" 2>/dev/null || true
    # Find architecture directory containing auto/ (e.g. x86_64-linux, darwin-2level)
    for d in "$LIB_VER_DIR"/*; do
        if [ -d "$d" ] && [ -d "$d/auto" ]; then
            cp -r "$d"/* "$RUN_DIR/lib/" 2>/dev/null || true
            cp -r "$d/auto"/* "$RUN_DIR/lib/auto/" 2>/dev/null || true
            break
        fi
    done
fi

# Symlink perl executable for t/harness
ln -sf "$PERL_BIN" "$RUN_DIR/perl"
ln -sf "$PERL_BIN" "$RUN_DIR/t/perl"

# 5. Environment configuration for non-interactive hermetic CI execution
export PERL_SKIP_TTY_TEST=1
export HARNESS_NOTTY=1
export AUTOMATED_TESTING=1
export NONINTERACTIVE_TESTING=1
export NO_NETWORK_TESTING=1
export PERL_CORE=1
export PERL_USE_UNSAFE_INC=0
export LC_ALL=C
export LANG=C

JOBS="${TEST_JOBS:-4}"
export HARNESS_OPTIONS="j${JOBS}"

# 6. Execute selected test suites
cd "$RUN_DIR/t"

TEST_PATTERNS=(
    "base/*.t"
    "cmd/*.t"
    "comp/*.t"
    "opbasic/*.t"
    "mro/*.t"
)

# Filters for tests requiring unbuilt optional modules, Unicode tables (issue #11), or interactive TTYs
ANTI_PATTERNS=(
    "-nre=package_aliases_utf8"
    "-nre=comp/require"
)

echo "Executing Perl core unit test suites (jobs: ${JOBS})..."
LOG_FILE="$WORKDIR/test_run.log"

set +e
./perl harness "${ANTI_PATTERNS[@]}" "${TEST_PATTERNS[@]}" > "$LOG_FILE" 2>&1
TEST_STATUS=$?
set -e

cat "$LOG_FILE"

echo "================================================================="
if [ $TEST_STATUS -eq 0 ]; then
    echo "SUCCESS: All core unit test suites passed cleanly!"
else
    echo "FAILURE: One or more unit tests failed (status: $TEST_STATUS)"
fi
echo "================================================================="

# 7. Write GitHub Actions Step Summary if in CI
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    PASSED_FILES=$(grep -c " \.\. ok" "$LOG_FILE" || true)
    TOTAL_TESTS=$(grep -oE "Tests=[0-9]+" "$LOG_FILE" | head -n 1 | cut -d= -f2 || echo "N/A")
    TOTAL_FILES=$(grep -oE "Files=[0-9]+" "$LOG_FILE" | head -n 1 | cut -d= -f2 || echo "N/A")
    WALLCLOCK=$(grep -oE "[0-9]+ wallclock secs" "$LOG_FILE" | head -n 1 || echo "N/A")

    {
        echo "### 🧪 Perl Core Unit Test Suite Results"
        echo ""
        echo "| Metric | Value |"
        echo "| --- | --- |"
        echo "| **Distribution Tarball** | \`$(basename "$TARBALL")\` |"
        echo "| **Test Status** | $( [ $TEST_STATUS -eq 0 ] && echo "✅ **PASSED**" || echo "❌ **FAILED**" ) |"
        echo "| **Test Files Evaluated** | ${TOTAL_FILES} |"
        echo "| **Test Assertions** | ${TOTAL_TESTS} |"
        echo "| **Duration** | ${WALLCLOCK} |"
        echo ""
        if [ $TEST_STATUS -ne 0 ]; then
            echo "#### ⚠️ Failure Diagnostics"
            echo "\`\`\`"
            grep -E "(Dubious|Failed test|Non-zero exit status)" "$LOG_FILE" | head -n 30 || true
            echo "\`\`\`"
        fi
    } >> "$GITHUB_STEP_SUMMARY"
fi

exit $TEST_STATUS
