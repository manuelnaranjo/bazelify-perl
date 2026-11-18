#!/usr/bin/env bash
# test_miniperl_reproducibility.sh - Automated reproducibility and determinism verification for miniperl-generated artifacts
set -euo pipefail

MINIPERL=""
CONFIG_SH=""
CONFIG_GIT=""
GENERATED_FILES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --miniperl)
            MINIPERL="$2"
            shift 2
            ;;
        --config-sh)
            CONFIG_SH="$2"
            shift 2
            ;;
        --config-git)
            CONFIG_GIT="$2"
            shift 2
            ;;
        --files)
            shift
            while [[ $# -gt 0 ]] && [[ "$1" != --* ]]; do
                GENERATED_FILES+=("$1")
                shift
            done
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$MINIPERL" ] || [ ! -f "$MINIPERL" ]; then
    echo "Error: miniperl binary not found: '$MINIPERL'" >&2
    exit 1
fi

if [ -z "$CONFIG_SH" ] || [ ! -f "$CONFIG_SH" ]; then
    echo "Error: config.sh not found: '$CONFIG_SH'" >&2
    exit 1
fi

if [ ${#GENERATED_FILES[@]} -eq 0 ]; then
    echo "Error: No generated files passed to verify!" >&2
    exit 1
fi

echo "================================================================="
echo " Miniperl Generated Artifacts Reproducibility & Determinism Test "
echo "================================================================="
echo "Miniperl binary : $MINIPERL"
echo "Config.sh       : $CONFIG_SH"
echo "Artifact count  : ${#GENERATED_FILES[@]}"
echo ""

# -----------------------------------------------------------------------------
# Stage 1: Inspect generated artifacts for machine-specific / non-hermetic paths
# -----------------------------------------------------------------------------
echo "=== Stage 1: Inspecting artifacts for non-hermetic paths ==="
FORBIDDEN_PATTERNS=(
    "/buildbuddy"
    "buildbuddy-execroot"
    "/execroot/"
    "/home/"
    "/Users/"
    "bazel-out"
    "/tmp/"
)

FAILED_PATHS=0
for file in "${GENERATED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "Error: generated file '$file' does not exist!" >&2
        exit 1
    fi

    for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
        if grep -F -q "$pattern" "$file"; then
            echo "[-] FAIL: Machine-specific path pattern '$pattern' found in $file:" >&2
            grep -F -n "$pattern" "$file" | head -n 5 >&2
            FAILED_PATHS=$((FAILED_PATHS + 1))
        fi
    done

    # Specifically check #line directives in C source files
    if [[ "$file" == *.c ]]; then
        if grep -E '^#line [0-9]+ "/' "$file" >/dev/null 2>&1; then
            echo "[-] FAIL: Absolute path in #line directive in $file:" >&2
            grep -E -n '^#line [0-9]+ "/' "$file" | head -n 5 >&2
            FAILED_PATHS=$((FAILED_PATHS + 1))
        fi
    fi
done

if [ "$FAILED_PATHS" -gt 0 ]; then
    echo "[-] Stage 1 failed with $FAILED_PATHS path leaks!" >&2
    exit 1
fi
echo "[+] Stage 1 PASSED: All ${#GENERATED_FILES[@]} artifacts are clean of machine-specific paths."
echo ""

# -----------------------------------------------------------------------------
# Stage 2: Independent multi-stage re-generation & bit-for-bit SHA256 validation
# -----------------------------------------------------------------------------
echo "=== Stage 2: Bit-for-bit SHA-256 Reproducibility Verification ==="

TMP_BASE="${TEST_TMPDIR:-$(mktemp -d)}/repro_test"
mkdir -p "$TMP_BASE"

# Discover source root containing perl source tree
# Find where Porting/Glossary and configpm live
PERL_SRC_ROOT=""
for candidate in \
    "$(dirname "$MINIPERL")" \
    "$(dirname "$MINIPERL")/external/+perl_dist+perl" \
    "external/+perl_dist+perl" \
    "external/perl" \
    "../+perl_dist+perl" \
    "."; do
    if [ -f "$candidate/configpm" ] && [ -f "$candidate/Porting/Glossary" ]; then
        PERL_SRC_ROOT="$(cd "$candidate" && pwd)"
        break
    fi
done

if [ -z "$PERL_SRC_ROOT" ]; then
    CANDIDATE="$(find . -name "Porting" -type d 2>/dev/null | head -n 1)"
    if [ -n "$CANDIDATE" ]; then
        PERL_SRC_ROOT="$(cd "$(dirname "$CANDIDATE")" && pwd)"
    fi
fi

if [ -z "$PERL_SRC_ROOT" ] || [ ! -f "$PERL_SRC_ROOT/configpm" ]; then
    echo "Error: Could not locate Perl source tree in runfiles!" >&2
    find . -maxdepth 3 -ls >&2
    exit 1
fi

echo "Perl source root located at: $PERL_SRC_ROOT"

MINIPERL_ABS="$(cd "$(dirname "$MINIPERL")" && pwd)/$(basename "$MINIPERL")"
CONFIG_SH_ABS="$(cd "$(dirname "$CONFIG_SH")" && pwd)/$(basename "$CONFIG_SH")"
CONFIG_GIT_ABS=""
if [ -n "$CONFIG_GIT" ] && [ -f "$CONFIG_GIT" ]; then
    CONFIG_GIT_ABS="$(cd "$(dirname "$CONFIG_GIT")" && pwd)/$(basename "$CONFIG_GIT")"
fi

# Function to run an independent regeneration pass
regenerate_pass() {
    local STAGE_DIR="$1"
    local NONCE="$2"

    mkdir -p "$STAGE_DIR"
    local TREE="$STAGE_DIR/tree"
    mkdir -p "$TREE"
    cp -r -L --no-preserve=mode "$PERL_SRC_ROOT"/* "$TREE"/
    chmod -R u+w "$TREE"

    export LC_ALL=C
    export PERL_HASH_SEED=0
    export TZ=UTC
    export SOURCE_DATE_EPOCH="$NONCE"

    # 1. Config.pm, Config_heavy.pl, Config.pod
    cp "$CONFIG_SH_ABS" "$TREE/config.sh"
    if [ -n "$CONFIG_GIT_ABS" ]; then
        rm -f "$TREE/lib/Config_git.pl"
        cp -f "$CONFIG_GIT_ABS" "$TREE/lib/Config_git.pl"
    fi
    (
        cd "$TREE"
        "$MINIPERL_ABS" -Ilib configpm >/dev/null 2>&1
    )

    local CFGDIR="$TREE/lib"
    local INCS="-I$CFGDIR"
    for d in "$TREE"/lib "$TREE"/cpan/*/lib "$TREE"/dist/*/lib "$TREE"/ext/*/lib "$TREE"/cpan/* "$TREE"/dist/* "$TREE"/ext/*; do
        if [ -d "$d" ]; then
            INCS="$INCS -I$d"
        fi
    done

    # 2. perlmain.c
    "$MINIPERL_ABS" $INCS -MExtUtils::Miniperl -e 'writemain(@ARGV)' DynaLoader > "$TREE/perlmain.c"

    # 3. ppport.h
    local PPPORT_BUILD="$STAGE_DIR/_build_ppport"
    mkdir -p "$PPPORT_BUILD"
    cp -r --no-preserve=mode "$TREE/dist/Devel-PPPort"/* "$PPPORT_BUILD"/
    (
        cd "$PPPORT_BUILD"
        "$MINIPERL_ABS" -I"$CFGDIR" -I"$TREE/lib" PPPort_pm.PL >/dev/null 2>&1
        "$MINIPERL_ABS" -I"$CFGDIR" -I"$TREE/lib" -I. ppport_h.PL >/dev/null 2>&1
    )
    mkdir -p "$TREE/dist/Devel-PPPort"
    cp "$PPPORT_BUILD/ppport.h" "$TREE/dist/Devel-PPPort/ppport.h"

    # 4. DynaLoader.c
    local XSUBPP="$TREE/dist/ExtUtils-ParseXS/lib/ExtUtils/xsubpp"
    local CORE_TYPEMAP="$TREE/lib/ExtUtils/typemap"
    (
        cd "$TREE/ext/DynaLoader"
        "$MINIPERL_ABS" $INCS "$XSUBPP" -noprototypes -typemap "$CORE_TYPEMAP" dl_dlopen.xs > DynaLoader.c
    )

    # 5. IO.c (needs ppport.h)
    cp "$TREE/dist/Devel-PPPort/ppport.h" "$TREE/dist/IO/"
    (
        cd "$TREE/dist/IO"
        "$MINIPERL_ABS" $INCS "$XSUBPP" -noprototypes -typemap "$CORE_TYPEMAP" IO.xs > IO.c
    )

    # 6. Cwd.c (needs ppport.h)
    cp "$TREE/dist/Devel-PPPort/ppport.h" "$TREE/dist/PathTools/"
    (
        cd "$TREE/dist/PathTools"
        "$MINIPERL_ABS" $INCS "$XSUBPP" -noprototypes -typemap "$CORE_TYPEMAP" Cwd.xs > Cwd.c
    )

    # 7. mro.c
    (
        cd "$TREE/ext/mro"
        "$MINIPERL_ABS" $INCS "$XSUBPP" -noprototypes -typemap "$CORE_TYPEMAP" mro.xs > mro.c
    )

    # 8. POSIX (with Makefile.PL)
    local POSIX_BUILD="$STAGE_DIR/_build_ext_POSIX"
    mkdir -p "$POSIX_BUILD/lib/ExtUtils" "$POSIX_BUILD/ext/POSIX"
    touch "$POSIX_BUILD/config_h.SH" "$POSIX_BUILD/perl.h" "$POSIX_BUILD/cflags"
    cp -r --no-preserve=mode "$TREE/lib"/* "$POSIX_BUILD/lib/"
    cp -r --no-preserve=mode "$CFGDIR"/* "$POSIX_BUILD/lib/"
    for d in "$TREE"/cpan/*/lib/* "$TREE"/dist/*/lib/* "$TREE"/ext/*/lib/*; do
        if [ -e "$d" ]; then cp -r --no-preserve=mode "$d" "$POSIX_BUILD/lib/"; fi
    done
    for d in "$TREE"/cpan/*/*.pm "$TREE"/dist/*/*.pm "$TREE"/ext/*/*.pm; do
        if [ -f "$d" ]; then cp --no-preserve=mode "$d" "$POSIX_BUILD/lib/"; fi
    done
    cp -r --no-preserve=mode "$TREE/ext/POSIX"/* "$POSIX_BUILD/ext/POSIX/"
    (
        cd "$POSIX_BUILD/ext/POSIX"
        PERL_CORE=1 "$MINIPERL_ABS" -I../../lib Makefile.PL >/dev/null 2>&1
        "$MINIPERL_ABS" -I../../lib "$XSUBPP" -noprototypes -typemap "$CORE_TYPEMAP" -typemap typemap POSIX.xs > POSIX.c
    )
    cp "$POSIX_BUILD/ext/POSIX/POSIX.c" "$TREE/ext/POSIX/POSIX.c"
    cp "$POSIX_BUILD/ext/POSIX/const-c.inc" "$TREE/ext/POSIX/const-c.inc"

    # 9. Socket (with Makefile.PL)
    local SOCKET_BUILD="$STAGE_DIR/_build_cpan_Socket"
    mkdir -p "$SOCKET_BUILD/lib/ExtUtils" "$SOCKET_BUILD/cpan/Socket"
    touch "$SOCKET_BUILD/config_h.SH" "$SOCKET_BUILD/perl.h" "$SOCKET_BUILD/cflags"
    cp -r --no-preserve=mode "$TREE/lib"/* "$SOCKET_BUILD/lib/"
    cp -r --no-preserve=mode "$CFGDIR"/* "$SOCKET_BUILD/lib/"
    for d in "$TREE"/cpan/*/lib/* "$TREE"/dist/*/lib/* "$TREE"/ext/*/lib/*; do
        if [ -e "$d" ]; then cp -r --no-preserve=mode "$d" "$SOCKET_BUILD/lib/"; fi
    done
    for d in "$TREE"/cpan/*/*.pm "$TREE"/dist/*/*.pm "$TREE"/ext/*/*.pm; do
        if [ -f "$d" ]; then cp --no-preserve=mode "$d" "$SOCKET_BUILD/lib/"; fi
    done
    cp -r --no-preserve=mode "$TREE/cpan/Socket"/* "$SOCKET_BUILD/cpan/Socket/"
    (
        cd "$SOCKET_BUILD/cpan/Socket"
        PERL_CORE=1 "$MINIPERL_ABS" -I../../lib Makefile.PL >/dev/null 2>&1
        "$MINIPERL_ABS" -I../../lib "$XSUBPP" -noprototypes -typemap "$CORE_TYPEMAP" -typemap typemap Socket.xs > Socket.c
    )
    cp "$SOCKET_BUILD/cpan/Socket/Socket.c" "$TREE/cpan/Socket/Socket.c"
    cp "$SOCKET_BUILD/cpan/Socket/const-c.inc" "$TREE/cpan/Socket/const-c.inc"

    # 10. Fcntl (with Makefile.PL)
    local FCNTL_BUILD="$STAGE_DIR/_build_ext_Fcntl"
    mkdir -p "$FCNTL_BUILD/lib/ExtUtils" "$FCNTL_BUILD/ext/Fcntl"
    touch "$FCNTL_BUILD/config_h.SH" "$FCNTL_BUILD/perl.h" "$FCNTL_BUILD/cflags"
    cp -r --no-preserve=mode "$TREE/lib"/* "$FCNTL_BUILD/lib/"
    cp -r --no-preserve=mode "$CFGDIR"/* "$FCNTL_BUILD/lib/"
    for d in "$TREE"/cpan/*/lib/* "$TREE"/dist/*/lib/* "$TREE"/ext/*/lib/*; do
        if [ -e "$d" ]; then cp -r --no-preserve=mode "$d" "$FCNTL_BUILD/lib/"; fi
    done
    for d in "$TREE"/cpan/*/*.pm "$TREE"/dist/*/*.pm "$TREE"/ext/*/*.pm; do
        if [ -f "$d" ]; then cp --no-preserve=mode "$d" "$FCNTL_BUILD/lib/"; fi
    done
    cp -r --no-preserve=mode "$TREE/ext/Fcntl"/* "$FCNTL_BUILD/ext/Fcntl/"
    (
        cd "$FCNTL_BUILD/ext/Fcntl"
        PERL_CORE=1 "$MINIPERL_ABS" -I../../lib Makefile.PL >/dev/null 2>&1
        "$MINIPERL_ABS" -I../../lib "$XSUBPP" -noprototypes -typemap "$CORE_TYPEMAP" Fcntl.xs > Fcntl.c
    )
    cp "$FCNTL_BUILD/ext/Fcntl/Fcntl.c" "$TREE/ext/Fcntl/Fcntl.c"
    cp "$FCNTL_BUILD/ext/Fcntl/const-c.inc" "$TREE/ext/Fcntl/const-c.inc"

    # 11. File-Glob (with Makefile.PL)
    local GLOB_BUILD="$STAGE_DIR/_build_ext_File-Glob"
    mkdir -p "$GLOB_BUILD/lib/ExtUtils" "$GLOB_BUILD/ext/File-Glob"
    touch "$GLOB_BUILD/config_h.SH" "$GLOB_BUILD/perl.h" "$GLOB_BUILD/cflags"
    cp -r --no-preserve=mode "$TREE/lib"/* "$GLOB_BUILD/lib/"
    cp -r --no-preserve=mode "$CFGDIR"/* "$GLOB_BUILD/lib/"
    for d in "$TREE"/cpan/*/lib/* "$TREE"/dist/*/lib/* "$TREE"/ext/*/lib/*; do
        if [ -e "$d" ]; then cp -r --no-preserve=mode "$d" "$GLOB_BUILD/lib/"; fi
    done
    for d in "$TREE"/cpan/*/*.pm "$TREE"/dist/*/*.pm "$TREE"/ext/*/*.pm; do
        if [ -f "$d" ]; then cp --no-preserve=mode "$d" "$GLOB_BUILD/lib/"; fi
    done
    cp -r --no-preserve=mode "$TREE/ext/File-Glob"/* "$GLOB_BUILD/ext/File-Glob/"
    (
        cd "$GLOB_BUILD/ext/File-Glob"
        PERL_CORE=1 "$MINIPERL_ABS" -I../../lib Makefile.PL >/dev/null 2>&1
        "$MINIPERL_ABS" -I../../lib "$XSUBPP" -noprototypes -typemap "$CORE_TYPEMAP" Glob.xs > Glob.c
    )
    cp "$GLOB_BUILD/ext/File-Glob/Glob.c" "$TREE/ext/File-Glob/Glob.c"
    cp "$GLOB_BUILD/ext/File-Glob/const-c.inc" "$TREE/ext/File-Glob/const-c.inc"

    # 12. List-Util (with Makefile.PL)
    local LISTUTIL_BUILD="$STAGE_DIR/_build_cpan_Scalar-List-Utils"
    mkdir -p "$LISTUTIL_BUILD/lib/ExtUtils" "$LISTUTIL_BUILD/cpan/Scalar-List-Utils"
    touch "$LISTUTIL_BUILD/config_h.SH" "$LISTUTIL_BUILD/perl.h" "$LISTUTIL_BUILD/cflags"
    cp -r --no-preserve=mode "$TREE/lib"/* "$LISTUTIL_BUILD/lib/"
    cp -r --no-preserve=mode "$CFGDIR"/* "$LISTUTIL_BUILD/lib/"
    for d in "$TREE"/cpan/*/lib/* "$TREE"/dist/*/lib/* "$TREE"/ext/*/lib/*; do
        if [ -e "$d" ]; then cp -r --no-preserve=mode "$d" "$LISTUTIL_BUILD/lib/"; fi
    done
    for d in "$TREE"/cpan/*/*.pm "$TREE"/dist/*/*.pm "$TREE"/ext/*/*.pm; do
        if [ -f "$d" ]; then cp --no-preserve=mode "$d" "$LISTUTIL_BUILD/lib/"; fi
    done
    cp -r --no-preserve=mode "$TREE/cpan/Scalar-List-Utils"/* "$LISTUTIL_BUILD/cpan/Scalar-List-Utils/"
    (
        cd "$LISTUTIL_BUILD/cpan/Scalar-List-Utils"
        PERL_CORE=1 "$MINIPERL_ABS" -I../../lib Makefile.PL >/dev/null 2>&1
        "$MINIPERL_ABS" -I../../lib "$XSUBPP" -noprototypes -typemap "$CORE_TYPEMAP" ListUtil.xs > ListUtil.c
    )
    cp "$LISTUTIL_BUILD/cpan/Scalar-List-Utils/ListUtil.c" "$TREE/cpan/Scalar-List-Utils/ListUtil.c"
}

echo "Running regeneration pass 1..."
regenerate_pass "$TMP_BASE/run1" "0"

echo "Running regeneration pass 2 (different working dir, timestamp, environment)..."
regenerate_pass "$TMP_BASE/run2" "123456789"

# Artifact mapping relative to tree root
declare -A REL_MAP=(
    ["lib/Config.pm"]="lib/Config.pm"
    ["lib/Config_heavy.pl"]="lib/Config_heavy.pl"
    ["lib/Config.pod"]="lib/Config.pod"
    ["perlmain.c"]="perlmain.c"
    ["ppport.h"]="dist/Devel-PPPort/ppport.h"
    ["DynaLoader.c"]="ext/DynaLoader/DynaLoader.c"
    ["POSIX.c"]="ext/POSIX/POSIX.c"
    ["POSIX/const-c.inc"]="ext/POSIX/const-c.inc"
    ["Socket.c"]="cpan/Socket/Socket.c"
    ["Socket/const-c.inc"]="cpan/Socket/const-c.inc"
    ["Fcntl.c"]="ext/Fcntl/Fcntl.c"
    ["Fcntl/const-c.inc"]="ext/Fcntl/const-c.inc"
    ["IO.c"]="dist/IO/IO.c"
    ["Cwd.c"]="dist/PathTools/Cwd.c"
    ["Glob.c"]="ext/File-Glob/Glob.c"
    ["File-Glob/const-c.inc"]="ext/File-Glob/const-c.inc"
    ["ListUtil.c"]="cpan/Scalar-List-Utils/ListUtil.c"
    ["mro.c"]="ext/mro/mro.c"
)

echo ""
echo "=== Comparison Results ==="
printf "%-35s %-64s %s\n" "Artifact" "SHA-256 Checksum" "Status"
printf "%-35s %-64s %s\n" "-----------------------------------" "----------------------------------------------------------------" "------"

MISMATCH_COUNT=0
for bazel_file in "${GENERATED_FILES[@]}"; do
    filename="$(basename "$bazel_file")"
    parent="$(basename "$(dirname "$bazel_file")")"

    key="$filename"
    if [ "$filename" = "const-c.inc" ]; then
        key="$parent/const-c.inc"
    elif [ "$filename" = "Config.pm" ] || [ "$filename" = "Config_heavy.pl" ] || [ "$filename" = "Config.pod" ]; then
        key="lib/$filename"
    fi

    rel_path="${REL_MAP[$key]:-}"
    if [ -z "$rel_path" ]; then
        echo "Warning: Unmapped file key '$key' for file '$bazel_file'!" >&2
        rel_path="$key"
    fi

    file1="$TMP_BASE/run1/tree/$rel_path"
    file2="$TMP_BASE/run2/tree/$rel_path"

    hash_bazel="$(sha256sum "$bazel_file" | awk '{print $1}')"
    hash_run1="$(sha256sum "$file1" | awk '{print $1}')"
    hash_run2="$(sha256sum "$file2" | awk '{print $1}')"

    if [ "$hash_bazel" != "$hash_run1" ] || [ "$hash_run1" != "$hash_run2" ]; then
        printf "%-35s %-64s %s\n" "$rel_path" "$hash_bazel" "MISMATCH"
        echo "[-] Diff between Bazel output and Run 1 for $rel_path:" >&2
        diff -u "$bazel_file" "$file1" | head -n 30 >&2 || true
        MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
    else
        printf "%-35s %-64s %s\n" "$rel_path" "$hash_bazel" "PASS"
    fi
done

echo ""
if [ "$MISMATCH_COUNT" -gt 0 ]; then
    echo "[-] FAILED: $MISMATCH_COUNT artifact(s) showed non-deterministic outputs!" >&2
    exit 1
fi

echo "[+] SUCCESS: All ${#GENERATED_FILES[@]} miniperl-generated artifacts are 100% reproducible and bit-for-bit identical!"
exit 0
