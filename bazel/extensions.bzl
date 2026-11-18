"""Bzlmod module extension for upstream Perl source fetching."""

load("//bazel/private:perl_archive.bzl", "perl_archive")

_version_tag = tag_class(
    attrs = {
        "name": attr.string(
            default = "perl",
            doc = "Repository name to export (default: 'perl').",
        ),
        "version": attr.string(
            default = "5.45.4",
            doc = "Perl version to fetch (must be 5.36+).",
        ),
        "sha256": attr.string(
            doc = "SHA256 checksum of the tarball. Optional for known versions.",
        ),
        "urls": attr.string_list(
            doc = "Custom URLs for downloading the tarball.",
        ),
        "patches": attr.label_list(
            default = [],
            doc = "Patches to apply from bazel/patches/perl/.",
        ),
        "patch_args": attr.string_list(
            default = ["-p1"],
            doc = "Patch arguments, default ['-p1'].",
        ),
        "build_file": attr.label(
            default = Label("//bazel/perl:perl.BUILD.bazel"),
            doc = "Optional overlay BUILD file.",
        ),
    },
)

def _perl_dist_impl(module_ctx):
    declared_repos = {}
    default_version_seen = False

    for mod in module_ctx.modules:
        for tag in mod.tags.version:
            name = tag.name
            if name in declared_repos:
                continue
            declared_repos[name] = True
            if name == "perl":
                default_version_seen = True

            perl_archive(
                name = name,
                version = tag.version,
                sha256 = tag.sha256,
                urls = tag.urls,
                patches = tag.patches,
                patch_args = tag.patch_args,
                build_file = tag.build_file if tag.build_file else Label("//bazel/perl:perl.BUILD.bazel"),
            )

    # If no explicit "perl" repo tag was declared, declare default Perl 5.45.4
    if not default_version_seen:
        perl_archive(
            name = "perl",
            version = "5.45.4",
            patch_args = ["-p1"],
            build_file = Label("//bazel/perl:perl.BUILD.bazel"),
        )

perl_dist = module_extension(
    implementation = _perl_dist_impl,
    tag_classes = {
        "version": _version_tag,
    },
)
