"""Repository rule for fetching Perl source archives from CPAN with integrity verification."""

load(":perl_shas.bzl", "KNOWN_PERL_SHAS")

def _parse_version(version_str):
    parts = version_str.split(".")
    if len(parts) < 2:
        return 0, 0
    return int(parts[0]), int(parts[1])

def _perl_archive_impl(ctx):
    version = ctx.attr.version
    major, minor = _parse_version(version)

    # Enforce minimum supported Perl version: 5.36+
    if major < 5 or (major == 5 and minor < 36):
        fail("Only Perl versions 5.36+ are supported (version requested: %s)" % version)

    # Determine URLs
    urls = ctx.attr.urls
    if not urls:
        urls = [
            "https://www.cpan.org/src/5.0/perl-{version}.tar.gz".format(version = version),
            "https://cpan.metacpan.org/src/5.0/perl-{version}.tar.gz".format(version = version),
        ]

    # Determine sha256
    sha256 = ctx.attr.sha256
    if not sha256:
        if version in KNOWN_PERL_SHAS:
            sha256 = KNOWN_PERL_SHAS[version]
        else:
            fail("No known SHA256 checksum for Perl version %s; please provide the 'sha256' attribute explicitly." % version)

    # Download and extract tarball
    ctx.download_and_extract(
        url = urls,
        sha256 = sha256,
        stripPrefix = "perl-" + version,
    )

    # Apply patches if any
    strip_num = 1
    for arg in ctx.attr.patch_args:
        if arg.startswith("-p"):
            strip_num = int(arg[2:])

    for patch in ctx.attr.patches:
        ctx.patch(patch, strip = strip_num)

    # Setup BUILD.bazel in repository root
    if ctx.attr.build_file:
        ctx.symlink(ctx.attr.build_file, "BUILD.bazel")
    else:
        ctx.file(
            "BUILD.bazel",
            content = """# Automatically generated BUILD file for upstream Perl source repository
load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library")

package(default_visibility = ["//visibility:public"])

exports_files(glob(["**"]))

# All sources in upstream Perl distribution
filegroup(
    name = "sources",
    srcs = glob(["**"]),
)

# Header files
filegroup(
    name = "headers",
    srcs = glob([
        "*.h",
        "cpan/**/*.h",
        "dist/**/*.h",
        "ext/**/*.h",
    ]),
)

# C source translation units
filegroup(
    name = "c_sources",
    srcs = glob([
        "*.c",
        "cpan/**/*.c",
        "dist/**/*.c",
        "ext/**/*.c",
    ]),
)

# Pre-staged generated C sources and headers from upstream CPAN release
filegroup(
    name = "generated_c_sources",
    srcs = [
        "keywords.c",
        "opcode.h",
        "opnames.h",
        "regnodes.h",
    ],
)

# Host generator tool for uudmap.h, bitcount.h, and mg_data.h
cc_binary(
    name = "generate_uudmap",
    srcs = [
        "generate_uudmap.c",
        "mg_raw.h",
    ],
)

# Action to regenerate uudmap.h, bitcount.h, and mg_data.h
genrule(
    name = "regenerate_headers",
    outs = [
        "bitcount.h",
        "mg_data.h",
        "uudmap.h",
    ],
    cmd = "$(execpath :generate_uudmap) $(OUTS)",
    tools = [":generate_uudmap"],
)
""",
        )

perl_archive = repository_rule(
    implementation = _perl_archive_impl,
    attrs = {
        "version": attr.string(
            mandatory = True,
            doc = "Perl version (e.g. '5.45.4', '5.44.0', '5.38.2'). Must be 5.36+.",
        ),
        "sha256": attr.string(
            doc = "SHA256 checksum of the source archive. Optional if known.",
        ),
        "urls": attr.string_list(
            doc = "List of URLs to fetch the tarball from. Defaults to CPAN and MetaCPAN.",
        ),
        "patches": attr.label_list(
            default = [],
            doc = "List of patch labels to apply to the extracted Perl source.",
        ),
        "patch_args": attr.string_list(
            default = ["-p1"],
            doc = "Arguments passed to patch command. Defaults to ['-p1'].",
        ),
        "build_file": attr.label(
            default = Label("//bazel/perl:perl.BUILD.bazel"),
            doc = "Custom BUILD file to use in place of the default template.",
        ),
    },
    doc = "Fetches an upstream Perl source archive from CPAN and applies patches.",
)
