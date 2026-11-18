#!/usr/bin/env bash
# run_e2e_test.sh - End-to-end integration smoke test with rules_perl
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TARBALL="${1:-}"

if [ -z "$TARBALL" ]; then
    for candidate in \
        "$WORKSPACE_ROOT"/dist/perl-*-linux_amd64.tar.gz \
        "$WORKSPACE_ROOT"/bazel-bin/bazel/release/perl-*-linux_amd64.tar.gz \
        $(find "$WORKSPACE_ROOT"/bazel-out/ -name "perl-*-linux_amd64.tar.gz" 2>/dev/null); do
        if [ -f "$candidate" ] && [[ "$candidate" != *nopthread* ]]; then
            TARBALL="$candidate"
            break
        fi
    done
fi

if [ -z "$TARBALL" ] || [ ! -f "$TARBALL" ]; then
    echo "No prebuilt distribution archive found. Assembling distribution in root workspace..."
    (
        cd "$WORKSPACE_ROOT"
        INVOCATION_ID=$(uuidgen)
        echo "Invocation ID: ${INVOCATION_ID}"
        bazel build --invocation_id=${INVOCATION_ID} //bazel/release:dist
    )
    TARBALL=$(find "$WORKSPACE_ROOT"/bazel-out/ -name "perl-*-linux_amd64.tar.gz" -not -path "*nopthread*" 2>/dev/null | head -n 1)
fi

if [ -z "$TARBALL" ] || [ ! -f "$TARBALL" ]; then
    echo "Error: Failed to find or build linux_amd64 distribution archive!" >&2
    exit 1
fi

TARBALL_ABS="$(cd "$(dirname "$TARBALL")" && pwd)/$(basename "$TARBALL")"
TARBALL_NAME="$(basename "$TARBALL_ABS")"
STRIP_PREFIX="${TARBALL_NAME%.tar.gz}"
SHA256="$(sha256sum "$TARBALL_ABS" | cut -d' ' -f1)"

echo "=== rules_perl E2E Smoke Test Setup ==="
echo "Tarball:      $TARBALL_ABS"
echo "Strip prefix: $STRIP_PREFIX"
echo "SHA-256:      $SHA256"

mkdir -p "$SCRIPT_DIR/dist"
cp -f "$TARBALL_ABS" "$SCRIPT_DIR/dist/perl.tar.gz"

cat <<EOF > "$SCRIPT_DIR/local_perl.bzl"
"""Generated local perl repository rule for e2e testing"""
load("@rules_perl//perl:repo.bzl", "perl_download")

def _local_perl_impl(module_ctx):
    workspace_root = module_ctx.path(Label("//:BUILD.bazel")).dirname
    perl_download(
        name = "local_perl",
        strip_prefix = "${STRIP_PREFIX}",
        urls = ["file://%s/dist/perl.tar.gz" % workspace_root],
        sha256 = "${SHA256}",
    )

local_perl = module_extension(
    implementation = _local_perl_impl,
)
EOF

echo "Running E2E tests in $SCRIPT_DIR..."
cd "$SCRIPT_DIR"

INVOCATION_ID=$(uuidgen)
echo "Invocation ID: ${INVOCATION_ID}"
bazel test --invocation_id=${INVOCATION_ID} --test_output=all //:smoke_test

INVOCATION_ID=$(uuidgen)
echo "Invocation ID: ${INVOCATION_ID}"
bazel run --invocation_id=${INVOCATION_ID} //:hello

echo "=== All rules_perl E2E Smoke Tests PASSED! ==="
