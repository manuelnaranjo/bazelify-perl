#!/usr/bin/env python3
"""Extract CanonicalModel for reference Perl build."""

import sys
import os

sys.path.append("/home/manuel/.gemini/skills/any2bazel/scripts")
from model import (
    Action,
    BuildSystem,
    CanonicalModel,
    Dependency,
    Target,
    TargetKind,
    TargetRole,
)
from serialize import dump_model

_COMMON_SRCS = [
    "av.c", "builtin.c", "caretx.c", "class.c", "deb.c", "doio.c", "doop.c",
    "dquote.c", "dump.c", "globals.c", "gv.c", "hv.c", "keywords.c", "locale.c",
    "long_names.c", "mathoms.c", "mg.c", "mro_core.c", "numeric.c", "pad.c",
    "peep.c", "perlio.c", "perly.c", "pp.c", "pp_ctl.c", "pp_hot.c", "pp_pack.c",
    "pp_sort.c", "pp_sys.c", "reentr.c", "regcomp.c", "regcomp_debug.c",
    "regcomp_invlist.c", "regcomp_study.c", "regcomp_trie.c", "regexec.c",
    "run.c", "scope.c", "sv.c", "taint.c", "time64.c", "toke.c", "utf8.c",
    "util.c",
]

_CORE_CFLAGS = [
    "-DPERL_CORE", "-fwrapv", "-fno-strict-aliasing", "-pipe",
    "-fstack-protector-strong", "-D_LARGEFILE_SOURCE", "-D_FILE_OFFSET_BITS=64",
    "-std=c99", "-O2", "-Wall", "-Werror=pointer-arith", "-Werror=vla", "-Wextra",
    "-Wno-long-long", "-Wno-declaration-after-statement", "-Wno-nonnull-compare",
    "-Wc++-compat", "-Wwrite-strings",
]

_EXT_CFLAGS = [
    "-fwrapv", "-fno-strict-aliasing", "-pipe",
    "-fstack-protector-strong", "-D_LARGEFILE_SOURCE", "-D_FILE_OFFSET_BITS=64",
    "-Wall", "-Werror=pointer-arith", "-Werror=vla", "-Wextra", "-Wno-long-long",
    "-Wno-declaration-after-statement", "-Wno-nonnull-compare", "-Wc++-compat",
    "-Wwrite-strings", "-O2", "-fPIC",
]

def make_ref_model(out_path: str):
    m = CanonicalModel(build_system=BuildSystem.CMAKE, repo_root="")

    prefix = "external/+perl_dist+perl/"
    gen_prefix = "bazel-out/k8-fastbuild/bin/external/+perl_dist+perl/"

    # miniperl target
    miniperl = Target(name="miniperl", kind=TargetKind.EXECUTABLE, role=TargetRole.PRODUCTION)
    for s in ["opmini.c", "perlmini.c", "universalmini.c"]:
        miniperl.actions.append(Action(
            mnemonic="CppCompile",
            arguments=tuple(_CORE_CFLAGS + ["-DPERL_IS_MINIPERL", "-DPERL_EXTERNAL_GLOB", "-I.", "-c", gen_prefix + s]),
            outputs=(gen_prefix + s.replace(".c", ".o"),),
        ))
    for s in _COMMON_SRCS + ["miniperlmain.c"]:
        miniperl.actions.append(Action(
            mnemonic="CppCompile",
            arguments=tuple(_CORE_CFLAGS + ["-DPERL_IS_MINIPERL", "-DPERL_EXTERNAL_GLOB", "-I.", "-c", prefix + s]),
            outputs=(prefix + s.replace(".c", ".o"),),
        ))
    miniperl.actions.append(Action(
        mnemonic="CppLink",
        arguments=("-fstack-protector-strong", "-o", "miniperl", "-lpthread", "-ldl", "-lm", "-lutil", "-lc"),
        outputs=("miniperl",),
    ))
    m.add(miniperl)

    # libperl target
    libperl = Target(name="libperl", kind=TargetKind.SHARED, role=TargetRole.PRODUCTION)
    for s in ["op.c", "perl.c", "universal.c"] + _COMMON_SRCS:
        libperl.actions.append(Action(
            mnemonic="CppCompile",
            arguments=tuple(_CORE_CFLAGS + ["-I.", "-c", prefix + s]),
            outputs=(prefix + s.replace(".c", ".o"),),
        ))
    libperl.actions.append(Action(
        mnemonic="CppCompile",
        arguments=tuple(_CORE_CFLAGS + ["-I.", "-c", gen_prefix + "ext/DynaLoader/DynaLoader.c"]),
        outputs=(gen_prefix + "ext/DynaLoader/DynaLoader.o",),
    ))
    libperl.actions.append(Action(
        mnemonic="CppLink",
        arguments=("-shared", "-o", "libperl.so", "-lpthread", "-ldl", "-lm", "-lutil", "-lc"),
        outputs=("libperl.so",),
    ))
    m.add(libperl)

    # perl target
    perl = Target(name="perl", kind=TargetKind.EXECUTABLE, role=TargetRole.PRODUCTION)
    perl.actions.append(Action(
        mnemonic="CppCompile",
        arguments=tuple(_CORE_CFLAGS + ["-I.", "-c", gen_prefix + "perlmain.c"]),
        outputs=(gen_prefix + "perlmain.o",),
    ))
    perl.actions.append(Action(
        mnemonic="CppLink",
        arguments=("-o", "perl", "-fstack-protector-strong", "-Wl,-E", "libperl.a", "-lpthread", "-ldl", "-lm", "-lutil", "-lc"),
        outputs=("perl",),
    ))
    m.add(perl)

    # POSIX target
    posix = Target(name="POSIX", kind=TargetKind.SHARED, role=TargetRole.PRODUCTION)
    posix.actions.append(Action(
        mnemonic="CppCompile",
        arguments=tuple(_EXT_CFLAGS + ["-I.", "-c", gen_prefix + "ext/POSIX/POSIX.c"]),
        outputs=(gen_prefix + "ext/POSIX/POSIX.o",),
    ))
    posix.actions.append(Action(
        mnemonic="CppLink",
        arguments=("-shared", "-o", "POSIX.so", "-lm"),
        outputs=("POSIX.so",),
    ))
    m.add(posix)

    # Socket target
    socket = Target(name="Socket", kind=TargetKind.SHARED, role=TargetRole.PRODUCTION)
    socket.actions.append(Action(
        mnemonic="CppCompile",
        arguments=tuple(_EXT_CFLAGS + ["-I.", "-c", gen_prefix + "cpan/Socket/Socket.c"]),
        outputs=(gen_prefix + "cpan/Socket/Socket.o",),
    ))
    socket.actions.append(Action(
        mnemonic="CppLink",
        arguments=("-shared", "-o", "Socket.so"),
        outputs=("Socket.so",),
    ))
    m.add(socket)

    # Fcntl target
    fcntl = Target(name="Fcntl", kind=TargetKind.SHARED, role=TargetRole.PRODUCTION)
    fcntl.actions.append(Action(
        mnemonic="CppCompile",
        arguments=tuple(_EXT_CFLAGS + ["-I.", "-c", gen_prefix + "ext/Fcntl/Fcntl.c"]),
        outputs=(gen_prefix + "ext/Fcntl/Fcntl.o",),
    ))
    fcntl.actions.append(Action(
        mnemonic="CppLink",
        arguments=("-shared", "-o", "Fcntl.so"),
        outputs=("Fcntl.so",),
    ))
    m.add(fcntl)

    # IO target
    io = Target(name="IO", kind=TargetKind.SHARED, role=TargetRole.PRODUCTION)
    io.actions.append(Action(
        mnemonic="CppCompile",
        arguments=tuple(_EXT_CFLAGS + ["-I.", "-c", gen_prefix + "dist/IO/IO.c"]),
        outputs=(gen_prefix + "dist/IO/IO.o",),
    ))
    io.actions.append(Action(
        mnemonic="CppCompile",
        arguments=tuple(_EXT_CFLAGS + ["-I.", "-c", prefix + "dist/IO/poll.c"]),
        outputs=(prefix + "dist/IO/poll.o",),
    ))
    io.actions.append(Action(
        mnemonic="CppLink",
        arguments=("-shared", "-o", "IO.so"),
        outputs=("IO.so",),
    ))
    m.add(io)

    # Cwd target
    cwd = Target(name="Cwd", kind=TargetKind.SHARED, role=TargetRole.PRODUCTION)
    cwd.actions.append(Action(
        mnemonic="CppCompile",
        arguments=tuple(_EXT_CFLAGS + ["-DDOUBLE_SLASHES_SPECIAL=0", "-I.", "-c", gen_prefix + "dist/PathTools/Cwd.c"]),
        outputs=(gen_prefix + "dist/PathTools/Cwd.o",),
    ))
    cwd.actions.append(Action(
        mnemonic="CppLink",
        arguments=("-shared", "-o", "Cwd.so"),
        outputs=("Cwd.so",),
    ))
    m.add(cwd)

    dump_model(m, out_path)
    print(f"wrote {out_path}")

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "model.reference.json"
    make_ref_model(out)
