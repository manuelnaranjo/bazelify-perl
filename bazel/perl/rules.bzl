"""Hermetic Starlark rules for building Perl and its core extensions."""

load("@aspect_bazel_lib//lib:copy_file.bzl", _copy_file = "copy_file")
load("@bazel_skylib//rules:write_file.bzl", _write_file = "write_file")
load(":providers.bzl", _PerlVersionInfo = "PerlVersionInfo")

PerlVersionInfo = _PerlVersionInfo

copy_file = _copy_file
write_file = _write_file

_MINIPERL_ENV = {
    "LC_ALL": "C",
    "PERL_HASH_SEED": "0",
    "SOURCE_DATE_EPOCH": "0",
    "TZ": "UTC",
}

def _find_perl_root(ctx):
    if ctx.label.workspace_root:
        return ctx.label.workspace_root
    return "."

def _perl_configpm_impl(ctx):
    out_pm = ctx.outputs.config_pm
    out_heavy = ctx.outputs.config_heavy_pl
    out_pod = ctx.outputs.config_pod

    miniperl = ctx.executable.miniperl
    config_sh = ctx.file.config_sh
    glossary = ctx.file.glossary
    config_git = ctx.file.config_git

    root_dir = _find_perl_root(ctx)

    cmd = """
set -euo pipefail
MINIPERL="$1"
CONFIG_SH="$2"
ROOT="$3"
OUT_PM="$4"
OUT_HEAVY="$5"
OUT_POD="$6"
CONFIG_GIT="${7:-}"

cp "$CONFIG_SH" "$ROOT/config.sh"
if [ -n "$CONFIG_GIT" ] && [ -f "$CONFIG_GIT" ]; then
    cp "$CONFIG_GIT" "$ROOT/lib/Config_git.pl"
fi
(cd "$ROOT" && "$OLDPWD/$MINIPERL" -Ilib configpm)
cp "$ROOT/lib/Config.pm" "$OUT_PM"
cp "$ROOT/lib/Config_heavy.pl" "$OUT_HEAVY"
cp "$ROOT/lib/Config.pod" "$OUT_POD"
"""
    inputs = ctx.files.library_files + [
        config_sh,
        ctx.file.configpm_script,
        glossary,
        ctx.file.myconfig_sh,
    ]
    args = [
        miniperl.path,
        config_sh.path,
        root_dir,
        out_pm.path,
        out_heavy.path,
        out_pod.path,
    ]
    if config_git:
        inputs.append(config_git)
        args.append(config_git.path)

    ctx.actions.run_shell(
        outputs = [out_pm, out_heavy, out_pod],
        inputs = inputs,
        tools = [miniperl],
        command = cmd,
        arguments = args,
        env = _MINIPERL_ENV,
        mnemonic = "PerlConfigPm",
        progress_message = "Generating Config.pm and Config_heavy.pl",
    )
    return [DefaultInfo(files = depset([out_pm, out_heavy, out_pod]))]

perl_configpm = rule(
    implementation = _perl_configpm_impl,
    attrs = {
        "miniperl": attr.label(
            executable = True,
            cfg = "exec",
            mandatory = True,
        ),
        "config_sh": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "configpm_script": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "config_git": attr.label(
            allow_single_file = True,
        ),
        "glossary": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "myconfig_sh": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "library_files": attr.label_list(
            allow_files = True,
            default = [],
        ),
    },
    outputs = {
        "config_pm": "lib/Config.pm",
        "config_heavy_pl": "lib/Config_heavy.pl",
        "config_pod": "lib/Config.pod",
    },
)

def _perl_main_impl(ctx):
    out = ctx.outputs.out
    miniperl = ctx.executable.miniperl
    cfg_dir = ctx.files.configpm[0].dirname
    root = _find_perl_root(ctx)

    cmd = """
set -euo pipefail
MINIPERL="$1"
CFGDIR="$2"
ROOT="$3"
OUT="$4"

ROOT_ABS="$(pwd)/$ROOT"
CFGDIR_ABS="$(pwd)/$CFGDIR"
MINIPERL_ABS="$(pwd)/$MINIPERL"
OUT_ABS="$(pwd)/$OUT"

INCS="-I$CFGDIR_ABS"
for d in "$ROOT_ABS"/lib "$ROOT_ABS"/cpan/*/lib "$ROOT_ABS"/dist/*/lib "$ROOT_ABS"/ext/*/lib "$ROOT_ABS"/cpan/* "$ROOT_ABS"/dist/* "$ROOT_ABS"/ext/*; do
    if [ -d "$d" ]; then
        INCS="$INCS -I$d"
    fi
done

"$MINIPERL_ABS" $INCS -MExtUtils::Miniperl -e 'writemain(@ARGV)' DynaLoader > "$OUT_ABS"
"""
    ctx.actions.run_shell(
        outputs = [out],
        inputs = ctx.files.library_files + ctx.files.configpm,
        tools = [miniperl],
        command = cmd,
        arguments = [
            miniperl.path,
            cfg_dir,
            root,
            out.path,
        ],
        env = _MINIPERL_ENV,
        mnemonic = "PerlMainGen",
        progress_message = "Generating perlmain.c",
    )
    return [DefaultInfo(files = depset([out]))]

perl_main = rule(
    implementation = _perl_main_impl,
    attrs = {
        "miniperl": attr.label(
            executable = True,
            cfg = "exec",
            mandatory = True,
        ),
        "configpm": attr.label(
            mandatory = True,
        ),
        "library_files": attr.label_list(
            allow_files = True,
            default = [],
        ),
        "out": attr.output(
            mandatory = True,
        ),
    },
)

def _perl_ppport_impl(ctx):
    out = ctx.outputs.out
    miniperl = ctx.executable.miniperl
    cfg_dir = ctx.files.configpm[0].dirname
    root = _find_perl_root(ctx)

    cmd = """
set -euo pipefail
MINIPERL="$1"
CFGDIR="$2"
ROOT="$3"
OUT="$4"

ROOT_ABS="$(pwd)/$ROOT"
CFGDIR_ABS="$(pwd)/$CFGDIR"
MINIPERL_ABS="$(pwd)/$MINIPERL"
OUT_ABS="$(pwd)/$OUT"

SANDBOX_DIR="_build_ppport"
mkdir -p "$SANDBOX_DIR"
cp -r --no-preserve=mode "$ROOT_ABS"/dist/Devel-PPPort/* "$SANDBOX_DIR"/
(
    cd "$SANDBOX_DIR"
    "$MINIPERL_ABS" -I"$CFGDIR_ABS" -I"$ROOT_ABS/lib" PPPort_pm.PL
    "$MINIPERL_ABS" -I"$CFGDIR_ABS" -I"$ROOT_ABS/lib" -I. ppport_h.PL
)
cp "$SANDBOX_DIR/ppport.h" "$OUT_ABS"
"""
    ctx.actions.run_shell(
        outputs = [out],
        inputs = ctx.files.library_files + ctx.files.configpm + ctx.files.ppport_srcs,
        tools = [miniperl],
        command = cmd,
        arguments = [
            miniperl.path,
            cfg_dir,
            root,
            out.path,
        ],
        env = _MINIPERL_ENV,
        mnemonic = "PerlPpportGen",
        progress_message = "Generating ppport.h",
    )
    return [DefaultInfo(files = depset([out]))]

perl_ppport = rule(
    implementation = _perl_ppport_impl,
    attrs = {
        "miniperl": attr.label(
            executable = True,
            cfg = "exec",
            mandatory = True,
        ),
        "configpm": attr.label(
            mandatory = True,
        ),
        "library_files": attr.label_list(
            allow_files = True,
            default = [],
        ),
        "ppport_srcs": attr.label_list(
            allow_files = True,
            default = [],
        ),
        "out": attr.output(
            mandatory = True,
        ),
    },
)

def _perl_xs_extension_impl(ctx):
    out_c = ctx.outputs.out_c
    outs = [out_c]
    if ctx.outputs.out_const_c:
        outs.append(ctx.outputs.out_const_c)

    miniperl = ctx.executable.miniperl
    cfg_dir = ctx.files.configpm[0].dirname
    xs = ctx.file.xs
    xsubpp = ctx.file.xsubpp
    core_typemap = ctx.file.core_typemap

    root = _find_perl_root(ctx)

    makefile_pl = ctx.file.makefile_pl
    has_makefile_pl = "1" if makefile_pl else "0"
    makefile_pl_path = makefile_pl.path if makefile_pl else ""
    out_const_c_path = ctx.outputs.out_const_c.path if ctx.outputs.out_const_c else ""

    extra_typemap_paths = [t.path for t in ctx.files.typemaps]

    cmd = """
set -euo pipefail
MINIPERL="$1"
CFGDIR="$2"
ROOT="$3"
XS="$4"
XSUBPP="$5"
CORE_TYPEMAP="$6"
HAS_MAKEFILE_PL="$7"
MAKEFILE_PL="$8"
OUT_C="$9"
OUT_CONST_C="${10}"
shift 10
EXTRA_TYPEMAPS=("$@")

ROOT_ABS="$(pwd)/$ROOT"
CFGDIR_ABS="$(pwd)/$CFGDIR"
MINIPERL_ABS="$(pwd)/$MINIPERL"
XSUBPP_ABS="$(pwd)/$XSUBPP"
CORE_TYPEMAP_ABS="$(pwd)/$CORE_TYPEMAP"
OUT_C_ABS="$(pwd)/$OUT_C"
OUT_CONST_C_ABS="${OUT_CONST_C:+$(pwd)/$OUT_CONST_C}"

TYPEMAP_ARGS="-typemap $CORE_TYPEMAP_ABS"
for t in "${EXTRA_TYPEMAPS[@]}"; do
    TYPEMAP_ARGS="$TYPEMAP_ARGS -typemap $(pwd)/$t"
done

if [ "$HAS_MAKEFILE_PL" = "1" ]; then
    EXT_DIR="$(dirname "$MAKEFILE_PL")"
    REL_DIR="${EXT_DIR#$ROOT/}"
    BUILD_TREE="_build_${REL_DIR//\\//_}"
    mkdir -p "$BUILD_TREE/lib/ExtUtils" "$BUILD_TREE/$REL_DIR"
    touch "$BUILD_TREE/config_h.SH" "$BUILD_TREE/perl.h" "$BUILD_TREE/cflags"
    cp -r --no-preserve=mode "$ROOT_ABS"/lib/* "$BUILD_TREE/lib/"
    cp -r --no-preserve=mode "$CFGDIR_ABS"/* "$BUILD_TREE/lib/"
    for d in "$ROOT_ABS"/cpan/*/lib/* "$ROOT_ABS"/dist/*/lib/* "$ROOT_ABS"/ext/*/lib/*; do
        if [ -e "$d" ]; then cp -r --no-preserve=mode "$d" "$BUILD_TREE/lib/"; fi
    done
    for d in "$ROOT_ABS"/cpan/*/*.pm "$ROOT_ABS"/dist/*/*.pm "$ROOT_ABS"/ext/*/*.pm; do
        if [ -f "$d" ]; then cp --no-preserve=mode "$d" "$BUILD_TREE/lib/"; fi
    done
    cp -r --no-preserve=mode "$EXT_DIR"/* "$BUILD_TREE/$REL_DIR/"

    (
        cd "$BUILD_TREE/$REL_DIR"
        PERL_CORE=1 "$MINIPERL_ABS" -I../../lib Makefile.PL
        "$MINIPERL_ABS" -I../../lib "$XSUBPP_ABS" -noprototypes $TYPEMAP_ARGS "$(basename "$XS")" > "$(basename "$OUT_C")"
    )

    cp "$BUILD_TREE/$REL_DIR/$(basename "$OUT_C")" "$OUT_C_ABS"
    if [ -n "$OUT_CONST_C" ] && [ -f "$BUILD_TREE/$REL_DIR/const-c.inc" ]; then
        cp "$BUILD_TREE/$REL_DIR/const-c.inc" "$OUT_CONST_C_ABS"
    fi
else
    INCS="-I$CFGDIR_ABS"
    for d in "$ROOT_ABS"/lib "$ROOT_ABS"/cpan/*/lib "$ROOT_ABS"/dist/*/lib "$ROOT_ABS"/ext/*/lib "$ROOT_ABS"/cpan/* "$ROOT_ABS"/dist/* "$ROOT_ABS"/ext/*; do
        if [ -d "$d" ]; then
            INCS="$INCS -I$d"
        fi
    done

    EXT_DIR="$(dirname "$XS")"
    (
        cd "$EXT_DIR"
        "$MINIPERL_ABS" $INCS "$XSUBPP_ABS" -noprototypes $TYPEMAP_ARGS "$(basename "$XS")" > "$OUT_C_ABS"
    )
fi
"""

    inputs = (
        ctx.files.library_files +
        ctx.files.configpm +
        ctx.files.extra_srcs +
        ctx.files.typemaps +
        [xs, xsubpp, core_typemap]
    )
    if makefile_pl:
        inputs.append(makefile_pl)

    args = [
        miniperl.path,
        cfg_dir,
        root,
        xs.path,
        xsubpp.path,
        core_typemap.path,
        has_makefile_pl,
        makefile_pl_path,
        out_c.path,
        out_const_c_path,
    ] + extra_typemap_paths

    ctx.actions.run_shell(
        outputs = outs,
        inputs = inputs,
        tools = [miniperl],
        command = cmd,
        arguments = args,
        env = _MINIPERL_ENV,
        mnemonic = "PerlXsGen",
        progress_message = "Generating C source for Perl extension %s" % xs.basename,
    )
    return [DefaultInfo(files = depset(outs))]

perl_xs_extension = rule(
    implementation = _perl_xs_extension_impl,
    attrs = {
        "miniperl": attr.label(
            executable = True,
            cfg = "exec",
            mandatory = True,
        ),
        "xs": attr.label(
            allow_single_file = [".xs"],
            mandatory = True,
        ),
        "makefile_pl": attr.label(
            allow_single_file = True,
        ),
        "typemaps": attr.label_list(
            allow_files = True,
            default = [],
        ),
        "extra_srcs": attr.label_list(
            allow_files = True,
            default = [],
        ),
        "configpm": attr.label(
            mandatory = True,
        ),
        "library_files": attr.label_list(
            allow_files = True,
            default = [],
        ),
        "core_typemap": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "xsubpp": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "out_c": attr.output(
            mandatory = True,
        ),
        "out_const_c": attr.output(),
    },
)

def _perl_version_impl(ctx):
    version = ctx.attr.version
    parts = version.split(".")
    major = int(parts[0]) if len(parts) > 0 and parts[0].isdigit() else 0
    minor = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0
    return [
        PerlVersionInfo(
            version = version,
            major = major,
            minor = minor,
        ),
    ]

perl_version = rule(
    implementation = _perl_version_impl,
    attrs = {
        "version": attr.string(
            doc = "Perl version string",
            mandatory = True,
        ),
    },
    doc = "Attaches Perl version information to PerlVersionInfo provider.",
)

