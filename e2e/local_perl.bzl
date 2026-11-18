"""Generated local perl repository rule for e2e testing"""
load("@rules_perl//perl:repo.bzl", "perl_download")

def _local_perl_impl(module_ctx):
    workspace_root = module_ctx.path(Label("//:BUILD.bazel")).dirname
    perl_download(
        name = "local_perl",
        strip_prefix = "perl-5.45.4-linux_amd64",
        urls = ["file://%s/dist/perl.tar.gz" % workspace_root],
        sha256 = "5a43c129feea218c54166cad0c7e44ff2c0a1e9d25df7b504f66988ae16fc840",
    )

local_perl = module_extension(
    implementation = _local_perl_impl,
)
