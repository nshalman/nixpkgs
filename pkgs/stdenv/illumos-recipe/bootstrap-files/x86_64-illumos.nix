# Bootstrap-tools closure for x86_64-illumos.
#
# Pure fetchurl declarations of the artifacts produced by
#   nix-build pkgs/stdenv/illumos-recipe/make-bootstrap-tools.nix -A build
# on a host with the from-source stdenv chain already in /nix/store.
# The closure ships gcc-illumos + binutils + GNU userland + patchelf;
# patchelf is structural for the seed chain's stage-0 fixup hook (a
# stdenv without it can't shrink RPATHs and fails packages with
# disallowedRequisites guards on bashNonInteractive, e.g. krb5.lib).
# Refresh via the same script and bump both fields here.
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
    url = "https://www.shalman.org/files/67cvzmy5rrrnbhnvij6lpzgif9cl909r-illumos-bootstrap-closure.nar.xz";
    hash = "sha256-GC95X2x6ZpVf05Av+e0RAmOv9gddXWZUDBX1jkfwWe4=";
  };
  closureRoots = import <nix/fetchurl.nix> {
    url = "https://www.shalman.org/files/nmnpnp6h610ap0vibhzc1fh5l4bmmgps-illumos-bootstrap-closure-roots.txt";
    hash = "sha256-00+nolxqcdIIs+AcxBDrBErZT9SbWsLtjB4fpPIzpM4=";
  };
}
