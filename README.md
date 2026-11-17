# bazelify-perl

Building upstream relocatable Perl from source using Bazel, hermetic LLVM toolchains, and Remote Build Execution (RBE) for [`rules_perl`](https://github.com/bazel-contrib/rules_perl).

## Overview

`bazelify-perl` automates the compilation and packaging of upstream Perl directly from CPAN sources into self-contained, relocatable binaries for:
- `linux_amd64` (glibc 2.28+)
- `linux_arm64` (glibc 2.28+)
- `osx_amd64` (macOS 10.15+)
- `osx_arm64` (macOS 11.0+)

All builds run on a single host platform (Linux x86_64) using the hermetic LLVM C/C++ toolchain and BuildBuddy RBE.

## Key Features

- **Relocatable Binaries**: Follows `skaji/relocatable-perl` conventions with `-Duserelocatableinc` and runtime `@INC` resolution so tarballs can be unpacked anywhere.
- **Hermetic LLVM Toolchain**: Cross-compiles for Linux and macOS using BCR `@llvm` without compiling LLVM from source.
- **RBE Enabled**: Fully integrated with `toolchains_buildbuddy` for fast, parallel remote compilation.
- **Strict Parity**: Verified against upstream reference builds using `any2bazel`.
- **Automated CI/CD**: GitHub Actions workflows test pull requests (Perl 5.45.4) and automatically publish multi-platform releases on version tags (e.g. `v5.44.0.1`).

## Action Plan & Design

See [`docs/plan.md`](docs/plan.md) for the detailed architecture, boundary definitions, and implementation roadmap.
