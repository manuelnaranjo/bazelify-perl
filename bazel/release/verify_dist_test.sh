#!/usr/bin/env bash
set -euo pipefail

TARBALL=""
for arg in "$@"; do
    if [[ "$arg" == *.tar.gz ]] && [ -f "$arg" ]; then
        TARBALL="$arg"
        break
    elif [ -f "$arg" ]; then
        TARBALL="$arg"
        break
    fi
done

if [ -z "$TARBALL" ]; then
    # Fallback to default path or glob matching
    for candidate in bazel/release/perl-*.tar.gz ./perl-*.tar.gz; do
        if [ -f "$candidate" ]; then
            TARBALL="$candidate"
            break
        fi
    done
fi

if [ -z "$TARBALL" ] || [ ! -f "$TARBALL" ]; then
    echo "Error: Tarball not provided or not found! (searched: $@)" >&2
    exit 1
fi

DEST_DIR="${TEST_TMPDIR:-$(mktemp -d)}/arbitrary_install_path"
mkdir -p "$DEST_DIR"

tar -xzf "$TARBALL" -C "$DEST_DIR"

# Detect unpacked root directory dynamically
PERL_ROOT="$(find "$DEST_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

if [ ! -x "$PERL_ROOT/bin/perl" ]; then
    echo "Error: $PERL_ROOT/bin/perl is missing or not executable!" >&2
    exit 1
fi

echo "=== 1. Checking perl -V ==="
"$PERL_ROOT/bin/perl" -V

echo "=== 2. Checking dynamic relocatability of %Config ==="
"$PERL_ROOT/bin/perl" -e '
use strict;
use warnings;
use Config;

my $expected_bin = $^X;
$expected_bin =~ s!/[^/]+$!!;
my $expected_prefix = $expected_bin;
$expected_prefix =~ s!/[^/]+$!!;

print "Runtime executable: $^X\n";
print "Runtime bin:        $expected_bin\n";
print "Config prefix:      $Config{prefix}\n";
print "Config installbin:  $Config{installbin}\n";
print "Config perlpath:    $Config{perlpath}\n";
print "Config startperl:   $Config{startperl}\n";
print "Config scriptdir:   $Config{scriptdir}\n";

die "Config{installbin} not relocated: $Config{installbin}"
    if $Config{installbin} ne $expected_bin;

die "Config{perlpath} not relocated: $Config{perlpath}"
    if $Config{perlpath} ne $^X;

die "Config{startperl} not relocated: $Config{startperl}"
    if $Config{startperl} ne "#!$^X";

die "Config{prefix} contains build path /opt/perl"
    if $Config{prefix} =~ m{^/opt/perl};

print "All %Config relocatability assertions PASSED!\n";
'

echo "=== 3. Checking core XS modules ==="
"$PERL_ROOT/bin/perl" -e '
use strict;
use warnings;
use POSIX qw(uname);
use Socket qw(inet_aton inet_ntoa);
use Fcntl qw(O_RDONLY);
use IO::Handle;
use Cwd qw(getcwd);
use File::Glob qw(bsd_glob);

my @u = uname();
print "POSIX uname: ", join(", ", @u), "\n";
print "Socket test: ", inet_ntoa(inet_aton("127.0.0.1")), "\n";
print "Fcntl O_RDONLY: ", O_RDONLY, "\n";
print "Cwd getcwd: ", getcwd(), "\n";
my @files = bsd_glob("*");
print "File::Glob found: ", scalar(@files), " files\n";
print "All core XS modules PASSED!\n";
'

echo "=== 4. Checking rewritten utility script shebangs ==="
"$PERL_ROOT/bin/prove" --version

TEST_FILE="$DEST_DIR/relocatable_smoke.t"
cat << 'EOF' > "$TEST_FILE"
print "1..2\n";
print "ok 1 - perl script executed via prove\n";
print "ok 2 - relative paths verified\n";
EOF

"$PERL_ROOT/bin/prove" --exec "$PERL_ROOT/bin/perl" "$TEST_FILE"

echo "=== All Relocatability & Packaging Verifications Succeeded! ==="
