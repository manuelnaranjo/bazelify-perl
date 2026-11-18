#!/usr/bin/env python3
"""Hermetic packager for relocatable Perl distributions."""

import argparse
import os
import re
import shutil
import stat
import subprocess
import sys

from patch_config import patch_config_heavy, patch_config_pm

def rewrite_shebang(filepath, outpath=None):
    if outpath is None:
        outpath = filepath

    with open(filepath, "r", encoding="utf-8", errors="surrogateescape") as f:
        lines = f.readlines()

    if not lines:
        return False

    first_line = lines[0]
    if not re.match(r"^#!.*perl", first_line):
        return False

    header = [
        "#!/bin/sh\n",
        'exec "$(dirname "$0")"/perl -x "$0" "$@"\n',
        "#!perl\n",
    ]

    rest = lines[1:]
    rest_rewritten = []
    for line in rest:
        line = re.sub(r"(eval \x27exec )\S+/perl( -S \$0)", r"\1perl\2", line)
        rest_rewritten.append(line)

    content = header + rest_rewritten

    with open(outpath, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.writelines(content)

    try:
        os.chmod(outpath, 0o755)
    except OSError:
        pass

    return True

def copy_tree(src, dst):
    if not os.path.exists(src):
        return
    for root, dirs, files in os.walk(src):
        rel = os.path.relpath(root, src)
        target_dir = os.path.join(dst, rel) if rel != "." else dst
        os.makedirs(target_dir, exist_ok=True)
        for f in files:
            src_file = os.path.join(root, f)
            dst_file = os.path.join(target_dir, f)
            if not os.path.exists(dst_file):
                shutil.copy2(src_file, dst_file)

def copy_files(src_dir, dst_dir, pattern=r"\.pm$"):
    if not os.path.exists(src_dir):
        return
    for item in os.listdir(src_dir):
        full_path = os.path.join(src_dir, item)
        if os.path.isfile(full_path) and re.search(pattern, item):
            dst_file = os.path.join(dst_dir, item)
            if not os.path.exists(dst_file):
                shutil.copy2(full_path, dst_file)

def run_generator(miniperl, inc_dir, script_path, work_dir, out_file=None, dest_dir=None, extra_args=None):
    abs_script = os.path.abspath(script_path)
    if not os.path.exists(abs_script):
        return
    cmd = [
        os.path.abspath(miniperl),
        f"-I{os.path.abspath(inc_dir)}",
        abs_script,
    ]
    if extra_args:
        cmd.extend(extra_args)
    res = subprocess.run(cmd, cwd=work_dir, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Generator {script_path} failed ({res.returncode}):\n{res.stderr}\n{res.stdout}", file=sys.stderr)
    if out_file and dest_dir:
        src = os.path.join(work_dir, out_file)
        if os.path.exists(src):
            os.makedirs(dest_dir, exist_ok=True)
            dst = os.path.join(dest_dir, out_file)
            shutil.copy2(src, dst)
            try:
                os.remove(src)
            except OSError:
                pass

def generate_errno_pm(archname, osvers, dest_file):
    is_darwin = "darwin" in archname
    if is_darwin:
        errnos = [
            ("EPERM", 1), ("ENOENT", 2), ("ESRCH", 3), ("EINTR", 4), ("EIO", 5),
            ("ENXIO", 6), ("E2BIG", 7), ("ENOEXEC", 8), ("EBADF", 9), ("ECHILD", 10),
            ("EDEADLK", 11), ("ENOMEM", 12), ("EACCES", 13), ("EFAULT", 14), ("ENOTBLK", 15),
            ("EBUSY", 16), ("EEXIST", 17), ("EXDEV", 18), ("ENODEV", 19), ("ENOTDIR", 20),
            ("EISDIR", 21), ("EINVAL", 22), ("ENFILE", 23), ("EMFILE", 24), ("ENOTTY", 25),
            ("ETXTBSY", 26), ("EFBIG", 27), ("ENOSPC", 28), ("ESPIPE", 29), ("EROFS", 30),
            ("EMLINK", 31), ("EPIPE", 32), ("EDOM", 33), ("ERANGE", 34), ("EAGAIN", 35),
            ("EWOULDBLOCK", 35), ("EINPROGRESS", 36), ("EALREADY", 37), ("ENOTSOCK", 38),
            ("EDESTADDRREQ", 39), ("EMSGSIZE", 40), ("EPROTOTYPE", 41), ("ENOPROTOOPT", 42),
            ("EPROTONOSUPPORT", 43), ("ESOCKTNOSUPPORT", 44), ("ENOTSUP", 45), ("EOPNOTSUPP", 45),
            ("EPFNOSUPPORT", 46), ("EAFNOSUPPORT", 47), ("EADDRINUSE", 48), ("EADDRNOTAVAIL", 49),
            ("ENETDOWN", 50), ("ENETUNREACH", 51), ("ENETRESET", 52), ("ECONNABORTED", 53),
            ("ECONNRESET", 54), ("ENOBUFS", 55), ("EISCONN", 56), ("ENOTCONN", 57),
            ("ESHUTDOWN", 58), ("ETOOMANYREFS", 59), ("ETIMEDOUT", 60), ("ECONNREFUSED", 61),
            ("ELOOP", 62), ("ENAMETOOLONG", 63), ("EHOSTDOWN", 64), ("EHOSTUNREACH", 65),
            ("ENOTEMPTY", 66), ("EPROCLIM", 67), ("EUSERS", 68), ("EDQUOT", 69), ("ESTALE", 70),
            ("EREMOTE", 71), ("EBADRPC", 72), ("ERPCMISMATCH", 73), ("EPROGUNAVAIL", 74),
            ("EPROGMISMATCH", 75), ("EPROCUNAVAIL", 76), ("ENOLCK", 77), ("ENOSYS", 78),
            ("EFTYPE", 79), ("EAUTH", 80), ("ENEEDAUTH", 81), ("EPWROFF", 82), ("EDEVERR", 83),
            ("EOVERFLOW", 84), ("EBADEXEC", 85), ("EBADARCH", 86), ("ESHLIBVERS", 87),
            ("EBADMACHO", 88), ("ECANCELED", 89), ("EIDRM", 90), ("ENOMSG", 91), ("EILSEQ", 92),
            ("ENOATTR", 93), ("EBADMSG", 94), ("EMULTIHOP", 95), ("ENODATA", 96), ("ENOLINK", 97),
            ("ENOSR", 98), ("ENOSTR", 99), ("EPROTO", 100), ("ETIME", 101), ("ENOPOLICY", 103),
            ("ENOTRECOVERABLE", 104), ("EOWNERDEAD", 105), ("EQFULL", 106),
        ]
    else:
        errnos = [
            ("EPERM", 1), ("ENOENT", 2), ("ESRCH", 3), ("EINTR", 4), ("EIO", 5),
            ("ENXIO", 6), ("E2BIG", 7), ("ENOEXEC", 8), ("EBADF", 9), ("ECHILD", 10),
            ("EAGAIN", 11), ("EWOULDBLOCK", 11), ("ENOMEM", 12), ("EACCES", 13), ("EFAULT", 14),
            ("ENOTBLK", 15), ("EBUSY", 16), ("EEXIST", 17), ("EXDEV", 18), ("ENODEV", 19),
            ("ENOTDIR", 20), ("EISDIR", 21), ("EINVAL", 22), ("ENFILE", 23), ("EMFILE", 24),
            ("ENOTTY", 25), ("ETXTBSY", 26), ("EFBIG", 27), ("ENOSPC", 28), ("ESPIPE", 29),
            ("EROFS", 30), ("EMLINK", 31), ("EPIPE", 32), ("EDOM", 33), ("ERANGE", 34),
            ("EDEADLK", 35), ("EDEADLOCK", 35), ("ENAMETOOLONG", 36), ("ENOLCK", 37), ("ENOSYS", 38),
            ("ENOTEMPTY", 39), ("ELOOP", 40), ("ENOMSG", 42), ("EIDRM", 43), ("ECHRNG", 44),
            ("EL2NSYNC", 45), ("EL3HLT", 46), ("EL3RST", 47), ("ELNRNG", 48), ("EUNATCH", 49),
            ("ENOCSI", 50), ("EL2HLT", 51), ("EBADE", 52), ("EBADR", 53), ("EXFULL", 54),
            ("ENOANO", 55), ("EBADRQC", 56), ("EBADSLT", 57), ("EBFONT", 59), ("ENOSTR", 60),
            ("ENODATA", 61), ("ETIME", 62), ("ENOSR", 63), ("ENONET", 64), ("ENOPKG", 65),
            ("EREMOTE", 66), ("ENOLINK", 67), ("EADV", 68), ("ESRMNT", 69), ("ECOMM", 70),
            ("EPROTO", 71), ("EMULTIHOP", 72), ("EDOTDOT", 73), ("EBADMSG", 74), ("EFSBADCRC", 74),
            ("EOVERFLOW", 75), ("ENOTUNIQ", 76), ("EBADFD", 77), ("EREMCHG", 78), ("ELIBACC", 79),
            ("ELIBBAD", 80), ("ELIBSCN", 81), ("ELIBMAX", 82), ("ELIBEXEC", 83), ("EILSEQ", 84),
            ("ERESTART", 85), ("ESTRPIPE", 86), ("EUSERS", 87), ("ENOTSOCK", 88), ("EDESTADDRREQ", 89),
            ("EMSGSIZE", 90), ("EPROTOTYPE", 91), ("ENOPROTOOPT", 92), ("EPROTONOSUPPORT", 93),
            ("ESOCKTNOSUPPORT", 94), ("ENOTSUP", 95), ("EOPNOTSUPP", 95), ("EPFNOSUPPORT", 96),
            ("EAFNOSUPPORT", 97), ("EADDRINUSE", 98), ("EADDRNOTAVAIL", 99), ("ENETDOWN", 100),
            ("ENETUNREACH", 101), ("ENETRESET", 102), ("ECONNABORTED", 103), ("ECONNRESET", 104),
            ("ENOBUFS", 105), ("EISCONN", 106), ("ENOTCONN", 107), ("ESHUTDOWN", 108),
            ("ETOOMANYREFS", 109), ("ETIMEDOUT", 110), ("ECONNREFUSED", 111), ("EHOSTDOWN", 112),
            ("EHOSTUNREACH", 113), ("EALREADY", 114), ("EINPROGRESS", 115), ("ESTALE", 116),
            ("EFSCORRUPTED", 117), ("EUCLEAN", 117), ("ENOTNAM", 118), ("ENAVAIL", 119),
            ("EISNAM", 120), ("EREMOTEIO", 121), ("EDQUOT", 122), ("ENOMEDIUM", 123),
            ("EMEDIUMTYPE", 124), ("ECANCELED", 125), ("ENOKEY", 126), ("EKEYEXPIRED", 127),
            ("EKEYREVOKED", 128), ("EKEYREJECTED", 129), ("EOWNERDEAD", 130), ("ENOTRECOVERABLE", 131),
            ("ERFKILL", 132), ("EHWPOISON", 133),
        ]

    err_entries = "\n".join([f"\t{k} => {v}," for k, v in errnos])
    arch_esc = archname.replace("-", "\\-").replace(".", "\\.")
    osvers_esc = osvers.replace("-", "\\-").replace(".", "\\.")

    template = f"""# -*- buffer-read-only: t -*-
#
# This file is auto-generated for hermetic relocatable Perl.
#

package Errno;
use Exporter 'import';
use strict;

use Config;
"$Config{{'archname' Milano}}-$Config{{'osvers' Milano}}" eq
"{arch_esc}-{osvers_esc}" or
\tdie "Errno architecture ({arch_esc}-{osvers_esc}) does not match executable architecture ($Config{{'archname' Milano}}-$Config{{'osvers' Milano}})";

our $VERSION = "1.39";
$VERSION = eval $VERSION;

my %err;

BEGIN {{
    %err = (
{err_entries}
    );
    foreach my $name (keys %err) {{
        if ($Errno::{{$name}}) {{
            eval "sub $name() {{ $err{{$name}} }}; 1" or die $@;
        }} else {{
            $Errno::{{$name}} = \\$err{{$name}};
        }}
    }}
}}

our @EXPORT_OK = keys %err;

our %EXPORT_TAGS = (
    POSIX => [qw(
\tE2BIG EACCES EADDRINUSE EADDRNOTAVAIL EAFNOSUPPORT EAGAIN EALREADY
\tEBADF EBUSY ECHILD ECONNABORTED ECONNREFUSED ECONNRESET EDEADLK
\tEDESTADDRREQ EDOM EDQUOT EEXIST EFAULT EFBIG EHOSTDOWN EHOSTUNREACH
\tEINPROGRESS EINTR EINVAL EIO EISCONN EISDIR ELOOP EMFILE EMLINK
\tEMSGSIZE ENAMETOOLONG ENETDOWN ENETRESET ENETUNREACH ENFILE ENOBUFS
\tENODEV ENOENT ENOEXEC ENOLCK ENOMEM ENOPROTOOPT ENOSPC ENOSYS ENOTBLK
\tENOTCONN ENOTDIR ENOTEMPTY ENOTSOCK ENOTTY ENXIO EOPNOTSUPP EPERM
\tEPFNOSUPPORT EPIPE EPROTONOSUPPORT EPROTOTYPE ERANGE EREMOTE ERESTART
\tEROFS ESHUTDOWN ESOCKTNOSUPPORT ESPIPE ESRCH ESTALE ETIMEDOUT
\tETOOMANYREFS ETXTBSY EUSERS EWOULDBLOCK EXDEV
    )],
);

sub TIEHASH {{ bless \\%err }}

sub FETCH {{
    my (undef, $errname) = @_;
    return "" unless exists $err{{$errname}};
    my $errno = $err{{$errname}};
    return $errno == $! ? $errno : 0;
}}

sub STORE {{
    require Carp;
    Carp::confess("ERRNO hash is read only!");
}}

*CLEAR = *DELETE = \\*STORE;

sub NEXTKEY {{
    each %err;
}}

sub FIRSTKEY {{
    my $s = scalar keys %err;
    each %err;
}}

sub EXISTS {{
    my (undef, $errname) = @_;
    exists $err{{$errname}};
}}

sub _tie_it {{
    tie %{{$_[0]}}, __PACKAGE__;
}}

1;
__END__
""".replace(" Milano", "")

    os.makedirs(os.path.dirname(dest_file), exist_ok=True)
    with open(dest_file, "w") as f:
        f.write(template)

def main():
    parser = argparse.ArgumentParser(description="Assemble relocatable Perl distribution")
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--perl", required=True)
    parser.add_argument("--miniperl", required=True)
    parser.add_argument("--config-heavy", required=True)
    parser.add_argument("--config-pm", required=True)
    parser.add_argument("--config-git", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--archname", required=True)
    parser.add_argument("--dlext", default="so")
    parser.add_argument("--sample-source", required=True, help="Sample source file to deduce perl root")
    parser.add_argument("--xs-lib", action="append", default=[])

    args = parser.parse_args()

    # Deduce perl root from sample-source
    sample = args.sample_source
    if "/lib/strict.pm" in sample:
        perl_root = sample[:sample.index("/lib/strict.pm")]
    elif "/Configure" in sample:
        perl_root = sample[:sample.index("/Configure")]
    elif "/perl.c" in sample:
        perl_root = sample[:sample.index("/perl.c")]
    else:
        perl_root = os.path.dirname(os.path.dirname(sample))

    out_dir = args.out_dir
    version = args.version
    archname = args.archname
    dlext = args.dlext

    bin_dir = os.path.join(out_dir, "bin")
    lib_dir = os.path.join(out_dir, "lib", version)
    arch_dir = os.path.join(lib_dir, archname)
    auto_dir = os.path.join(arch_dir, "auto")

    os.makedirs(bin_dir, exist_ok=True)
    os.makedirs(arch_dir, exist_ok=True)
    os.makedirs(auto_dir, exist_ok=True)

    # 1. Copy perl binary
    dst_perl = os.path.join(bin_dir, "perl")
    shutil.copy2(args.perl, dst_perl)
    os.chmod(dst_perl, 0o755)

    dst_perl_ver = os.path.join(bin_dir, f"perl{version}")
    if os.path.lexists(dst_perl_ver):
        os.remove(dst_perl_ver)
    try:
        os.symlink("perl", dst_perl_ver)
    except OSError:
        shutil.copy2(dst_perl, dst_perl_ver)

    # 2. Copy standard library files
    copy_tree(os.path.join(perl_root, "lib"), lib_dir)

    for parent in ["cpan", "dist", "ext"]:
        parent_dir = os.path.join(perl_root, parent)
        if not os.path.isdir(parent_dir):
            continue
        for child in sorted(os.listdir(parent_dir)):
            child_dir = os.path.join(parent_dir, child)
            if not os.path.isdir(child_dir):
                continue
            child_lib = os.path.join(child_dir, "lib")
            if os.path.isdir(child_lib):
                copy_tree(child_lib, lib_dir)
                # Some modules have both a lib/ directory and top-level .pm files (e.g. Encode.pm, IO.pm, Cwd.pm)
                parts = child.split("-")
                prefix = os.path.join(*parts[:-1]) if len(parts) > 1 else ""
                for f in os.listdir(child_dir):
                    if f.endswith((".pm", ".pod")):
                        dst_dir = os.path.join(lib_dir, prefix) if prefix else lib_dir
                        os.makedirs(dst_dir, exist_ok=True)
                        dst_file = os.path.join(dst_dir, f)
                        if not os.path.exists(dst_file):
                            shutil.copy2(os.path.join(child_dir, f), dst_file)
            else:
                # When there is no lib/ directory, the child directory itself
                # represents the package hierarchy (hyphens map to directory separators).
                parts = child.split("-")
                prefix = os.path.join(*parts[:-1]) if len(parts) > 1 else ""
                for root, dirs, files in os.walk(child_dir):
                    rel = os.path.relpath(root, child_dir)
                    rel_parts = rel.split(os.sep) if rel != "." else []
                    if any(p in ("t", "hints", "fallback", "inc", "__examples", "devel", "parts") for p in rel_parts):
                        continue
                    sub = os.path.join(prefix, rel) if (prefix and rel != ".") else (prefix if rel == "." else rel)
                    target_dir = os.path.join(lib_dir, sub) if sub else lib_dir
                    for f in files:
                        if f.startswith("Makefile") or f.endswith(".PL") or f.startswith("0README") or f.startswith("README"):
                            continue
                        if f.endswith((".pm", ".pod", ".pl", ".txt", ".h")):
                            os.makedirs(target_dir, exist_ok=True)
                            dst_file = os.path.join(target_dir, f)
                            if not os.path.exists(dst_file):
                                shutil.copy2(os.path.join(root, f), dst_file)

    # 3. Copy & patch Config files FIRST so miniperl generators can load Config.pm
    dst_heavy = os.path.join(lib_dir, "Config_heavy.pl")
    dst_pm = os.path.join(lib_dir, "Config.pm")
    dst_git = os.path.join(lib_dir, "Config_git.pl")

    shutil.copy2(args.config_heavy, dst_heavy)
    shutil.copy2(args.config_pm, dst_pm)
    shutil.copy2(args.config_git, dst_git)

    patch_config_heavy(dst_heavy)
    patch_config_pm(dst_pm)

    with open(dst_heavy, "r", encoding="utf-8", errors="surrogateescape") as f:
        m = re.search(r"osvers='([^']+)'", f.read())
        osvers = m.group(1) if m else "2.28"

    # Also place in arch_dir
    shutil.copy2(dst_heavy, os.path.join(arch_dir, "Config_heavy.pl"))
    shutil.copy2(dst_pm, os.path.join(arch_dir, "Config.pm"))
    shutil.copy2(dst_git, os.path.join(arch_dir, "Config_git.pl"))

    # 4. Run bootstrap module generators
    work_gen = os.path.join(out_dir, "_work_gen")
    os.makedirs(work_gen, exist_ok=True)

    # XSLoader.pm
    run_generator(args.miniperl, lib_dir,
                  os.path.join(perl_root, "dist", "XSLoader", "XSLoader_pm.PL"),
                  work_gen, out_file="XSLoader.pm", dest_dir=lib_dir)

    # DynaLoader.pm
    run_generator(args.miniperl, lib_dir,
                  os.path.join(perl_root, "ext", "DynaLoader", "DynaLoader_pm.PL"),
                  work_gen, out_file="DynaLoader.pm", dest_dir=lib_dir)

    # lib.pm
    run_generator(args.miniperl, lib_dir,
                  os.path.join(perl_root, "dist", "lib", "lib_pm.PL"),
                  work_gen, out_file="lib.pm", dest_dir=lib_dir)

    # Errno.pm (generated hermetically for target arch/osvers)
    generate_errno_pm(archname, osvers, os.path.join(lib_dir, "Errno.pm"))
    generate_errno_pm(archname, osvers, os.path.join(arch_dir, "Errno.pm"))

    # Pod/Functions.pm
    pod_dir = os.path.join(lib_dir, "Pod")
    perlfunc = os.path.join(perl_root, "pod", "perlfunc.pod")
    run_generator(args.miniperl, lib_dir,
                  os.path.join(perl_root, "ext", "Pod-Functions", "Functions_pm.PL"),
                  work_gen, out_file="Functions.pm", dest_dir=pod_dir,
                  extra_args=[perlfunc] if os.path.isfile(perlfunc) else None)

    # 5. Extract utility scripts & rewrite shebangs
    work_tree = os.path.join(out_dir, "_work_tree")
    os.makedirs(work_tree, exist_ok=True)

    # Symlink cpan, dist, ext to work_tree so relative paths like ../cpan resolve
    for d in ["cpan", "dist", "ext"]:
        src = os.path.join(perl_root, d)
        if os.path.isdir(src):
            dst = os.path.join(work_tree, d)
            if not os.path.exists(dst):
                try:
                    os.symlink(os.path.abspath(src), dst)
                except OSError:
                    copy_tree(src, dst)

    dst_lib = os.path.join(work_tree, "lib")
    if not os.path.exists(dst_lib):
        try:
            os.symlink(os.path.abspath(lib_dir), dst_lib)
        except OSError:
            copy_tree(lib_dir, dst_lib)

    patchlevel_h = os.path.join(perl_root, "patchlevel.h")
    if os.path.isfile(patchlevel_h):
        dst_pl = os.path.join(work_tree, "patchlevel.h")
        if not os.path.exists(dst_pl):
            try:
                os.symlink(os.path.abspath(patchlevel_h), dst_pl)
            except OSError:
                shutil.copy2(patchlevel_h, dst_pl)

    work_utils = os.path.join(work_tree, "utils")
    os.makedirs(work_utils, exist_ok=True)
    utils_src = os.path.join(perl_root, "utils")
    if os.path.isdir(utils_src):
        for item in os.listdir(utils_src):
            s = os.path.join(utils_src, item)
            d = os.path.join(work_utils, item)
            if os.path.isfile(s):
                shutil.copy2(s, d)

        for pl_file in os.listdir(work_utils):
            if pl_file.endswith(".PL") and pl_file != "Makefile.PL":
                base_name = pl_file[:-3]
                run_generator(args.miniperl, lib_dir,
                              os.path.join(work_utils, pl_file),
                              work_utils)
                gen_script = os.path.join(work_utils, base_name)
                if os.path.isfile(gen_script):
                    dst_script = os.path.join(bin_dir, base_name)
                    rewrite_shebang(gen_script, dst_script)

    # Also extract podlators / pod scripts
    pod_scripts = [
        ("cpan/podlators/scripts/pod2man.PL", "pod2man"),
        ("cpan/podlators/scripts/pod2text.PL", "pod2text"),
        ("cpan/Pod-Usage/scripts/pod2usage.PL", "pod2usage"),
        ("cpan/Pod-Checker/scripts/podchecker.PL", "podchecker"),
    ]
    for rel_pl, name in pod_scripts:
        pl_path = os.path.join(perl_root, rel_pl)
        if os.path.isfile(pl_path):
            run_generator(args.miniperl, lib_dir, pl_path, work_gen, out_file=name)
            gen_script = os.path.join(work_gen, name)
            if os.path.isfile(gen_script):
                dst_script = os.path.join(bin_dir, name)
                rewrite_shebang(gen_script, dst_script)

    # Symlink perlthanks -> perlbug
    perlbug_path = os.path.join(bin_dir, "perlbug")
    perlthanks_path = os.path.join(bin_dir, "perlthanks")
    if os.path.isfile(perlbug_path) and not os.path.exists(perlthanks_path):
        try:
            os.symlink("perlbug", perlthanks_path)
        except OSError:
            shutil.copy2(perlbug_path, perlthanks_path)

    # 6. Copy XS shared objects
    for xs in args.xs_lib:
        base = os.path.basename(xs)
        mod = base
        if mod.startswith("lib"):
            mod = mod[3:]
        mod = mod.split(".")[0]

        # In Perl, module hierarchies in auto/ map underscore to /
        # e.g. File_Glob -> auto/File/Glob/Glob.so
        # POSIX -> auto/POSIX/POSIX.so
        parts = mod.split("_")
        leaf = parts[-1]
        mod_dir = os.path.join(auto_dir, *parts)
        os.makedirs(mod_dir, exist_ok=True)
        dst_mod = os.path.join(mod_dir, f"{leaf}.{dlext}")
        shutil.copy2(xs, dst_mod)
        os.chmod(dst_mod, 0o755)

        if dlext != "so":
            so_link = os.path.join(mod_dir, f"{leaf}.so")
            if not os.path.exists(so_link):
                try:
                    os.symlink(f"{leaf}.{dlext}", so_link)
                except OSError:
                    shutil.copy2(dst_mod, so_link)

        lib_link = os.path.join(mod_dir, f"lib{leaf}.{dlext}")
        if not os.path.exists(lib_link):
            try:
                os.symlink(f"{leaf}.{dlext}", lib_link)
            except OSError:
                shutil.copy2(dst_mod, lib_link)

    # 7. Clean up work dirs
    shutil.rmtree(work_gen, ignore_errors=True)
    shutil.rmtree(work_tree, ignore_errors=True)

    # 8. Normalize permissions
    for root, dirs, files in os.walk(out_dir):
        for d in dirs:
            try:
                os.chmod(os.path.join(root, d), 0o755)
            except OSError:
                pass
        for f in files:
            p = os.path.join(root, f)
            try:
                cur_mode = stat.S_IMODE(os.stat(p).st_mode)
                if cur_mode & 0o111:
                    os.chmod(p, 0o755)
                else:
                    os.chmod(p, 0o644)
            except OSError:
                pass

if __name__ == "__main__":
    main()
