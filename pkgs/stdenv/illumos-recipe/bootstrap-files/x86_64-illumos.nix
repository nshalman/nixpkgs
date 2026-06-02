# Bootstrap-tools closure for x86_64-illumos.
#
# Pure fetchurl declarations of the artifacts produced by
#   nix-build pkgs/stdenv/illumos-recipe/make-bootstrap-tools.nix -A build
# on a host with the from-source stdenv chain already in /nix/store.
# These specific URLs/hashes come from the audited build under bd
# nix-pb0.2; refresh via the same script and bump both fields here.
#
# Locked /nix/store prefix: the .nar.xz payload contains
# `nix/store/<each-path>/...` literally and is restored verbatim by
# ./load-illumos-closure.sh. Receivers cannot relocate the prefix —
# the deliberate trade-off vs. freebsd's bootstrap-files/unpack.nar.xz
# shape is "less work on the receiver, no prefix flexibility".
#
# See ./default.nix for the discoverable wrapper and the loader script.
{
  closure = import <nix/fetchurl.nix> {
    url = "https://www.shalman.org/files/gbjvdwh7agq8hrqhgvlldffvsfch2229-illumos-bootstrap-closure.nar.xz";
    hash = "sha256-kQ24X1LXe0v3LdN/1ZFgPqa3NTkw5Jv5nzEdc+E5qew=";
  };
  closureRoots = import <nix/fetchurl.nix> {
    url = "https://www.shalman.org/files/lp76q6gdbf34jf2b7q1jcpz7fsjqh29s-illumos-bootstrap-closure-roots.txt";
    hash = "sha256-4xY0XXvRMXP/+ZtvEHqee9XsXwuQLOfAu+A7GAKua6M=";
  };
}
