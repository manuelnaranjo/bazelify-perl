# bazelify-perl

Hermetic, relocatable Perl distributions built directly from upstream CPAN sources using Bazel 9, hermetic LLVM toolchains, and Remote Build Execution (RBE). Designed for seamless consumption by [`rules_perl`](https://github.com/bazel-contrib/rules_perl) and standalone relocatable deployments.

---

## Overview

`bazelify-perl` automates the cross-compilation and packaging of upstream Perl from source into fully self-contained, relocatable binary archives. All target platforms are cross-compiled from a single Linux host using the hermetic LLVM C/C++ toolchain and BuildBuddy RBE—requiring no host-installed Perl, C compiler, or platform-specific SDKs.

### Supported Platforms & Targets

All distributions are built across four target platforms, available in both standard POSIX threads and lightweight non-threaded configurations:

| Target Platform | Architecture | OS / Minimum ABI | Build Flag |
|---|---|---|---|
| `linux_amd64` | `x86_64` | Linux (glibc 2.28+) | `--config=linux_amd64` |
| `linux_arm64` | `aarch64` | Linux (glibc 2.28+) | `--config=linux_arm64` |
| `osx_amd64` | `x86_64` | macOS (10.15+ Catalina) | `--config=osx_amd64` |
| `osx_arm64` | `aarch64` | macOS (11.0+ Big Sur / Apple Silicon) | `--config=osx_arm64` |

---

## Key Features

- **True Relocatability**: Follows `skaji/relocatable-perl` conventions:
  - Compiled with `-Duserelocatableinc` for relative runtime directory resolution.
  - Rewrites `Config.pm` and `Config_heavy.pl` with dynamic `relocate_inc` anchors (`.../perl`, `.../../bin`).
  - Rewrites bundled executable scripts (`cpan`, `perldoc`, `pod2man`, etc.) with portable relative shebangs (`#!/usr/bin/env perl`).
  - Tarballs can be extracted to any directory and executed immediately without environment modifications.
- **Single-Host Multi-Target Cross-Compilation**:
  - Uses the hermetic LLVM 18+ toolchain via `@llvm` from BCR.
  - Cross-compiles for Linux (`x86_64` and `aarch64`) against hermetic glibc 2.28 sysroots.
  - Cross-compiles for macOS Darwin (`x86_64` and `arm64`) using hermetic Apple SDK stubs and frameworks (`CoreFoundation`, `Foundation`, `Security`, `SystemConfiguration`).
- **Core XS Modules & C Headers (`CORE/`)**:
  - Compiles and packages essential XS shared extensions: `POSIX`, `Socket`, `IO`, `Fcntl`, `Cwd`, `File::Glob`, `List::Util`, and `mro`.
  - Packages complete Perl `CORE/` C headers (`perl.h`, `EXTERN.h`, etc.) into `lib/<version>/<archname>/CORE/`, enabling downstream C/XS extension compilation.
- **Configurable Threading Support**:
  - Configurable build setting `--//bazel:use_pthread` (defaults to `true`).
  - Aggregated release targets build both threaded (`perl-<version>-<platform>.tar.*`) and non-threaded (`perl-<version>-<platform>-nopthread.tar.*`) archives in a single invocation.
- **Strict Parity with Upstream (`any2bazel`)**:
  - Build actions, compiler flags, macros, and include paths are rigorously compared against upstream `./Configure && make` builds using `any2bazel`, achieving 100% convergence with zero unverified discrepancies.
- **Hermetic Reproducibility**:
  - Validates bit-identical artifact generation by `miniperl` for bootstrap code-generation steps (`keywords.c`, `opcode.h`, `regnodes.h`).
- **End-to-End Validation with `rules_perl`**:
  - Includes an end-to-end integration test workspace (`e2e/`) verifying direct consumption and execution of prebuilt distributions with `rules_perl` v2.1.0 (`perl_binary` and `perl_test`).
- **Remote Build Execution (RBE)**:
  - Fully integrated with `toolchains_buildbuddy` for fast, parallel remote compilation and remote caching.

---

## Quickstart & Usage

### Prerequisites

- [Bazelisk](https://github.com/bazelbuild/bazelisk) (or Bazel `9.3.2+`)
- Linux x86_64 host system (or RBE container)

### Building Distributions

Build all platform archives (all 4 platforms, threaded and non-threaded, `.tar.gz` and `.tar.xz`, plus the test suite archive) in a single command:

```bash
bazel build //bazel/release:dist
```

Build a specific platform distribution:

```bash
# Linux x86_64 (default)
bazel build //bazel/release:dist_pkg

# Linux ARM64
bazel build --config=linux_arm64 //bazel/release:dist_pkg

# macOS ARM64 (Apple Silicon)
bazel build --config=osx_arm64 //bazel/release:dist_pkg

# Disable POSIX threads (build nopthread variant)
bazel build --//bazel:use_pthread=false //bazel/release:dist_pkg
```

With Remote Build Execution (RBE):

```bash
bazel build --config=rbe //bazel/release:dist
```

### Running Tests

```bash
# Verify runtime relocatability and execution in an isolated directory
bazel test //bazel/release:verify_dist_test
bazel test //bazel/release:verify_dist_nopthread_test

# Run upstream Perl unit test suite across core modules
bazel test //bazel/release:upstream_unit_test
bazel test //bazel/release:upstream_unit_nopthread_test

# Validate miniperl code-generation reproducibility
bazel test //bazel/perl:miniperl_reproducibility_test

# Run rules_perl end-to-end integration smoke test
./e2e/run_e2e_test.sh bazel-bin/bazel/release/dist_linux_amd64/perl-5.45.4-linux_amd64.tar.gz
```

---

## Using with `rules_perl`

The produced distribution archives are directly compatible with [`rules_perl`](https://github.com/bazel-contrib/rules_perl).

### Example Toolchain Definition

In your downstream repository:

```starlark
# local_perl.bzl
def _local_perl_impl(repository_ctx):
    repository_ctx.extract(repository_ctx.attr.archive)
    repository_ctx.file("BUILD.bazel", """
package(default_visibility = ["//visibility:public"])
load("@rules_perl//perl:toolchain.bzl", "perl_toolchain")

filegroup(name = "runtime", srcs = glob(["**/*"]))

perl_toolchain(
    name = "toolchain_impl",
    perl = "bin/perl",
    runtime = [":runtime"],
)
""")

local_perl = repository_rule(
    implementation = _local_perl_impl,
    attrs = {"archive": attr.label(mandatory = True)},
)
```

In your `BUILD.bazel`:

```starlark
toolchain(
    name = "custom_perl_toolchain",
    exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    target_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    toolchain = "@local_perl//:toolchain_impl",
    toolchain_type = "@rules_perl//perl:toolchain_type",
)
```

See [`e2e/`](e2e/) for a complete working smoke test workspace demonstrating `perl_binary` and `perl_test` usage.

---

## Distribution Archive Structure

Unpacked archives follow the standard Perl directory hierarchy with relocatable paths:

```
perl-<version>-<platform>/
├── bin/
│   ├── perl
│   ├── perl<version> -> perl
│   ├── cpan
│   └── perldoc
└── lib/
    └── <version>/
        ├── Config.pm
        ├── Config_heavy.pl
        ├── <archname>/
        │   ├── CORE/                # C header files (perl.h, EXTERN.h, etc.)
        │   └── auto/                # Shared XS extensions (.so / .bundle)
        │       ├── POSIX/
        │       ├── Socket/
        │       ├── IO/
        │       └── ...
        └── ...
```

---

## Repository Structure

```
.
├── bazel/
│   ├── config/             # Platform-specific config.h and config.sh headers
│   ├── patches/perl/       # Upstream source patches
│   ├── perl/               # Perl BUILD targets, miniperl, rules, and reproducibility tests
│   ├── private/            # Source archive repository rules and checksum definitions
│   ├── release/            # Distribution packaging, transitions, and verification tests
│   ├── BUILD.bazel         # Platform definitions and configurable flags (use_pthread)
│   └── extensions.bzl      # Bzlmod perl_dist module extension
├── e2e/                    # End-to-end rules_perl integration test workspace
├── tools/                  # Packaging scripts, Config_heavy patching, and shebang rewrite tools
├── any2bazel.json          # any2bazel parity configuration and triage decisions
├── .github/workflows/
│   ├── ci.yml              # CI PR verification, RBE builds, and multi-platform runner tests
│   └── release.yml         # Automated GitHub Releases on v5.* tags with SHA256 checksums
└── MODULE.bazel            # Bzlmod dependencies (LLVM, BuildBuddy, rules_cc, platforms)
```

---

## CI/CD Pipeline

- **Pull Request Validation (`ci.yml`)**:
  - Builds Perl 5.45.4 across all four platforms on BuildBuddy RBE.
  - Verifies miniperl reproducibility.
  - Runs relocatability verification and upstream test suite tests (both threaded and non-threaded).
  - Executes the `rules_perl` end-to-end smoke test.
  - Validates distribution archives on native GitHub runners for `ubuntu-24.04-arm` (Linux ARM64) and `macos-14` (Apple Silicon M1).
- **Release Automation (`release.yml`)**:
  - Automatically triggers on version tags (e.g. `v5.44.0.1`, `v5.45.4.1`).
  - Packages multi-platform archives (`.tar.gz` and `.tar.xz`) for threaded and non-threaded targets.
  - Generates `SHA256SUMS` manifests.
  - Publishes assets directly to GitHub Releases.

---

## License

This project is licensed under the Apache 2.0 License. Perl itself is licensed under the Artistic License 1.0 or GNU GPL v1+.
