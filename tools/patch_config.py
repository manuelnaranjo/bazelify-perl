#!/usr/bin/env python3
"""Patch Config_heavy.pl and Config.pm for runtime relocatability.

Ensures that:
1. installbin='.../../bin', installprefix='.../..', perlpath='.../perl', startperl='#!.../perl'
2. All build prefix references (/opt/perl) are normalized to runtime relative tokens.
3. The relocation loop in Config_heavy.pl is expanded to cover all standard and plain keys.
4. Inline keys in Config.pm (like scriptdir) are wrapped in relocate_inc().
"""

import os
import re
import stat
import sys

RELOCATED_KEYS = """
archlib archlibexp bin binexp initialinstalllocation installarchlib installbin
installprefix installprefixexp installprivlib installscript installsitearch
installsitebin installsitelib installsitescript perlpath prefix prefixexp
privlib privlibexp scriptdir scriptdirexp sitearch sitearchexp sitebin
sitebinexp sitelib sitelib_stem sitelibexp siteprefix siteprefixexp sitescript
sitescriptexp startperl
""".split()

def patch_config_heavy(in_path, out_path=None):
    if out_path is None:
        out_path = in_path

    with open(in_path, "r", encoding="utf-8", errors="surrogateescape") as f:
        text = f.read()

    # Normalize specific variables
    text = re.sub(r"^installbin=\x27[^\x27]*\x27", "installbin=\x27.../../bin\x27", text, flags=re.M)
    text = re.sub(r"^installprefix=\x27[^\x27]*\x27", "installprefix=\x27.../..\x27", text, flags=re.M)
    text = re.sub(r"^perlpath=\x27[^\x27]*\x27", "perlpath=\x27.../perl\x27", text, flags=re.M)
    text = re.sub(r"^startperl=\x27[^\x27]*\x27", "startperl=\x27#!.../perl\x27", text, flags=re.M)

    # Replace /opt/perl references
    text = re.sub(r"/opt/perl/bin/perl\S*", ".../perl", text)
    text = text.replace("/opt/perl", ".../..")

    # Widen relocation loop
    loop_pat = r"foreach my \$what \(qw\([^)]*\)\) \{\s*s/\^\(\$what=\)[^\n]*\n\}"
    replacement = (
        "foreach my $what (qw(%s)) {\n"
        "    s/^($what=)(['\"])(#!)?(.*?)\\2"
        "/$1 . $2 . ($3 || \"\") . relocate_inc($4) . $2/me;\n}"
    ) % " ".join(RELOCATED_KEYS)

    new_text, count = re.subn(loop_pat, lambda m: replacement, text)

    # Ensure writable if overwriting
    if os.path.exists(out_path):
        try:
            mode = stat.S_IMODE(os.stat(out_path).st_mode)
            os.chmod(out_path, mode | stat.S_IWUSR)
        except OSError:
            pass

    with open(out_path, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(new_text)

def patch_config_pm(in_path, out_path=None):
    if out_path is None:
        out_path = in_path

    with open(in_path, "r", encoding="utf-8", errors="surrogateescape") as f:
        text = f.read()

    # Wrap any literal '.../...' in relocate_inc('...')
    new_text = re.sub(r"^(\s+\w+ => )(\x27\.\.\./[^\x27]*\x27),?$", r"\1relocate_inc(\2),", text, flags=re.M)

    if os.path.exists(out_path):
        try:
            mode = stat.S_IMODE(os.stat(out_path).st_mode)
            os.chmod(out_path, mode | stat.S_IWUSR)
        except OSError:
            pass

    with open(out_path, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(new_text)

def main():
    if len(sys.argv) < 3:
        print("Usage: patch_config.py heavy <in_heavy> [out_heavy] OR patch_config.py pm <in_pm> [out_pm]", file=sys.stderr)
        sys.exit(1)

    mode = sys.argv[1]
    in_file = sys.argv[2]
    out_file = sys.argv[3] if len(sys.argv) > 3 else in_file

    if mode == "heavy":
        patch_config_heavy(in_file, out_file)
    elif mode == "pm":
        patch_config_pm(in_file, out_file)
    elif mode == "dir":
        # Search directory for Config_heavy.pl and Config.pm
        for root, _, files in os.walk(in_file):
            for file in files:
                if file == "Config_heavy.pl":
                    patch_config_heavy(os.path.join(root, file))
                elif file == "Config.pm":
                    patch_config_pm(os.path.join(root, file))
    else:
        print(f"Unknown mode: {mode}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
