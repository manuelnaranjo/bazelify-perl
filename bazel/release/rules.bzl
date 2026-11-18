"""Hermetic rules for assembling relocatable Perl distributions."""

load("//bazel/perl:providers.bzl", "PerlVersionInfo")

def _perl_distribution_tree_impl(ctx):
    if PerlVersionInfo in ctx.attr.version:
        version = ctx.attr.version[PerlVersionInfo].version
    else:
        fail("Target %s does not provide PerlVersionInfo" % ctx.attr.version.label)

    platform_name = ctx.attr.platform_name
    dir_name = "perl-%s-%s" % (version, platform_name)

    out_dir = ctx.actions.declare_directory(dir_name)
    out_gz = ctx.actions.declare_file("perl-%s-%s.tar.gz" % (version, platform_name))
    out_xz = ctx.actions.declare_file("perl-%s-%s.tar.xz" % (version, platform_name))

    perl = ctx.executable.perl
    miniperl = ctx.executable.miniperl
    build_dist = ctx.executable.build_dist
    patch_config = ctx.file.patch_config
    change_shebang = ctx.file.change_shebang

    config_heavy = ctx.file.config_heavy_pl
    config_pm = ctx.file.config_pm
    config_git = ctx.file.config_git_pl
    sample_source = ctx.file.sample_source

    xs_files = ctx.files.xs_extensions

    args = [
        "--out-dir",
        out_dir.path,
        "--out-tar-gz",
        out_gz.path,
        "--out-tar-xz",
        out_xz.path,
        "--perl",
        perl.path,
        "--miniperl",
        miniperl.path,
        "--config-heavy",
        config_heavy.path,
        "--config-pm",
        config_pm.path,
        "--config-git",
        config_git.path,
        "--version",
        version,
        "--archname",
        ctx.attr.archname,
        "--dlext",
        ctx.attr.dlext,
        "--sample-source",
        sample_source.path,
    ]

    for xs in xs_files:
        args.extend(["--xs-lib", xs.path])

    inputs = (
        ctx.files.sources +
        ctx.files.library_files +
        ctx.files.xs_extensions +
        [
            perl,
            config_heavy,
            config_pm,
            config_git,
            sample_source,
            patch_config,
            change_shebang,
        ]
    )

    ctx.actions.run(
        outputs = [out_dir, out_gz, out_xz],
        inputs = inputs,
        tools = [miniperl, build_dist],
        executable = build_dist,
        arguments = args,
        mnemonic = "PerlDistTree",
        progress_message = "Assembling relocatable Perl distribution %s" % dir_name,
    )

    return [
        DefaultInfo(
            files = depset([out_gz, out_xz]),
        ),
        OutputGroupInfo(
            tree = depset([out_dir]),
            gz = depset([out_gz]),
            xz = depset([out_xz]),
            all = depset([out_dir, out_gz, out_xz]),
        ),
    ]

perl_distribution_tree = rule(
    implementation = _perl_distribution_tree_impl,
    attrs = {
        "perl": attr.label(
            executable = True,
            cfg = "target",
            mandatory = True,
        ),
        "miniperl": attr.label(
            executable = True,
            cfg = "exec",
            mandatory = True,
        ),
        "build_dist": attr.label(
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            mandatory = True,
        ),
        "patch_config": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "change_shebang": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "config_heavy_pl": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "config_pm": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "config_git_pl": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "sample_source": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "sources": attr.label_list(
            allow_files = True,
            default = [],
        ),
        "library_files": attr.label_list(
            allow_files = True,
            default = [],
        ),
        "xs_extensions": attr.label_list(
            allow_files = True,
            default = [],
        ),
        "version": attr.label(
            default = Label("//bazel/perl:version"),
            providers = [PerlVersionInfo],
            doc = "Perl version provider target",
        ),
        "platform_name": attr.string(
            mandatory = True,
        ),
        "archname": attr.string(
            mandatory = True,
        ),
        "dlext": attr.string(
            default = "so",
        ),
    },
)

perl_distribution = perl_distribution_tree

def _perl_test_suite_archive_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.output_name)
    sample_source = ctx.file.sample_source
    tool = ctx.executable.package_tool

    args = [
        "--sample-source",
        sample_source.path,
        "--out",
        out.path,
    ]

    inputs = ctx.files.sources + [sample_source]

    ctx.actions.run(
        outputs = [out],
        inputs = inputs,
        tools = [tool],
        executable = tool,
        arguments = args,
        mnemonic = "PerlTestSuitePkg",
        progress_message = "Packaging upstream Perl test suite archive %s" % out.basename,
    )

    return [
        DefaultInfo(files = depset([out])),
    ]

perl_test_suite_archive = rule(
    implementation = _perl_test_suite_archive_impl,
    attrs = {
        "sources": attr.label_list(
            allow_files = True,
            default = [],
        ),
        "sample_source": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "package_tool": attr.label(
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            mandatory = True,
        ),
        "output_name": attr.string(
            default = "perl-test-suite.tar.gz",
        ),
    },
)

