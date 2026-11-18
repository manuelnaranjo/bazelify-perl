#!/usr/bin/env perl
use strict;
use warnings;
use Config;
use POSIX qw(uname);
use Socket qw(inet_aton inet_ntoa);
use Cwd qw(getcwd);
use File::Glob qw(bsd_glob);

print "=== rules_perl E2E Smoke Test ===\n";
print "Perl version: $]\n";
print "OS name:      $^O\n";
print "Arch name:    $Config{archname}\n";
print "Executable:   $^X\n";

my @u = uname();
print "POSIX uname:  ", join(", ", @u), "\n";
print "Socket test:  ", inet_ntoa(inet_aton("127.0.0.1")), "\n";
print "Cwd getcwd:   ", getcwd(), "\n";

die "Unexpected perl version $]" unless $] >= 5.036;
print "rules_perl E2E Smoke Test PASSED!\n";
exit 0;
