# AGENTS.md

Notes for LLM agents working on this repository (`CLAUDE.md`, `CODEX.md`, and `GEMINI.md` are symlinks to this file).

## Ground Rules

- **Bazel Invocation Protocol (Mandatory):**
  Whenever invoking `bazel` (`build`, `test`, `run`, `cquery`, `query`, etc.):
  1. Generate an invocation ID with `uuidgen`: `INVOCATION_ID=$(uuidgen)`
  2. Print it: `echo "Invocation ID: ${INVOCATION_ID}"`
  3. Pass it immediately after the command: `bazel <command> --invocation_id=${INVOCATION_ID} <args>`
- **Path Handling Protocol:**
  Relative paths only. Never hardcode absolute paths; all paths must be relative to the repository root.
- **Timezone & Date Localization Protocol:**
  Always display all dates, times, and timestamps localized to `Europe/Amsterdam` (CET/CEST) in user-facing summaries.
- **BuildBuddy Remote Execution (RBE):**
  The build cluster is accessed via `--config=rbe`. Never print or overwrite `.bazelrc.user`, which holds the user's remote execution credentials.
- **Hermetic LLVM Toolchain:**
  Use `@llvm` from BCR for C/C++ compilation. Never compile LLVM from source.
- **Single-Platform Multi-Target:**
  All four target platforms (`linux_amd64`, `linux_arm64`, `osx_amd64`, `osx_arm64`) must cross-compile from a single Linux platform using the hermetic LLVM toolchain.
- **Upstream Source & Patches:**
  Upstream Perl sources are fetched from `https://www.cpan.org/src/5.0`. All patches applied to Perl must live under `bazel/patches/perl/`.
- **Relocatability:**
  Follow `perl-relocatable` (`-Duserelocatableinc`, relative `@INC`, patched `Config_heavy.pl` / `Config.pm`, and portable shebangs).
- **Parity with any2bazel:**
  The Bazel build actions must match the reference build actions via the `any2bazel` differ, recording decisions and rationales in `any2bazel.json`.
- **Git Worktrees:**
  Create all git worktrees under `.worktrees/`.
- **Untether Outbox:**
  Deliver files for user review to `.untether-outbox/`.
