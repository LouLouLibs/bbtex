#!/usr/bin/perl
# Kernel-owned lock: released on exit/crash, with no stale PID directory.
use strict;
use warnings;
use Fcntl qw(LOCK_EX);
my $path = shift @ARGV or die "Missing lock path\n";
@ARGV or die "Missing command\n";
$^F = 255; # Keep the lock descriptor across exec.
open(my $lock, '>>', $path) or die "Open $path: $!\n";
flock($lock, LOCK_EX) or die "Lock $path: $!\n";
exec { $ARGV[0] } @ARGV or die "Exec $ARGV[0]: $!\n";
