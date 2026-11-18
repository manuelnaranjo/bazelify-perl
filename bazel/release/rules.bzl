"""Hermetic rules for assembling relocatable Perl distributions."""

def _perl_distribution_tree_impl(ctx):
    out_dir = ctx.actions.declare_directory(ctx.attr.dir_name)

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
        ctx.attr.version,
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
        outputs = [out_dir],
        inputs = inputs,
        tools = [miniperl, build_dist],
        executable = build_dist,
        arguments = args,
        mnemonic = "PerlDistTree",
        progress_message = "Assembling relocatable Perl distribution %s" % ctx.attr.dir_name,
    )

    return [DefaultInfo(files = depset([out_dir]))]

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
        "version": attr.string(
            default = "5.45.4",
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
        "dir_name": attr.string(
            mandatory = True,
        ),
    },
)
