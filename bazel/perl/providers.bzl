"""Providers for Perl build rules."""

PerlVersionInfo = provider(
    doc = "Provider conveying Perl version information throughout the build tree.",
    fields = {
        "version": "Full Perl version string (e.g. '5.45.4')",
        "major": "Major version integer",
        "minor": "Minor version integer",
    },
)
