#!/usr/bin/env python3
"""Hermetic packager for the upstream Perl unit test suite."""

import argparse
import os
import stat
import sys
import tarfile

def main():
    parser = argparse.ArgumentParser(description="Package Perl upstream test suite.")
    parser.add_argument("--out", required=True, help="Output tar.gz path")
    parser.add_argument("--sample-source", required=True, help="Sample source file to deduce perl_root")
    args = parser.parse_args()

    sample = args.sample_source
    if "/lib/strict.pm" in sample:
        perl_root = sample[:sample.index("/lib/strict.pm")]
    elif "/Configure" in sample:
        perl_root = sample[:sample.index("/Configure")]
    elif "/perl.c" in sample:
        perl_root = sample[:sample.index("/perl.c")]
    else:
        perl_root = os.path.dirname(os.path.dirname(sample))

    out_path = args.out
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)

    items_to_package = [
        "t",
        "TestInit.pm",
        "Porting",
        "cpan",
        "dist",
        "ext",
    ]

    with tarfile.open(out_path, "w:gz") as tar:
        for item in items_to_package:
            full_path = os.path.join(perl_root, item)
            if not os.path.exists(full_path):
                continue

            def filter_tarinfo(tarinfo):
                tarinfo.uid = 0
                tarinfo.gid = 0
                tarinfo.uname = "root"
                tarinfo.gname = "root"
                tarinfo.mtime = 0
                mode = stat.S_IMODE(tarinfo.mode)
                if tarinfo.isdir():
                    tarinfo.mode = 0o755
                elif mode & 0o111:
                    tarinfo.mode = 0o755
                else:
                    tarinfo.mode = 0o644
                return tarinfo

            tar.add(full_path, arcname=item, filter=filter_tarinfo)

    print(f"Packaged Perl test suite to {out_path} ({os.path.getsize(out_path)} bytes)")

if __name__ == "__main__":
    main()
