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
    url = "https://www.shalman.org/files/52v0qnr3r6jmcyvj029p0pw43ybip45i-illumos-bootstrap-closure.nar.xz";
    hash = "sha256-Kc6DZkY5xV8ZkA5litQa/4Ni6O59jK+vN/sTLZ3ACno=";
  };
  closureRoots = import <nix/fetchurl.nix> {
    url = "https://www.shalman.org/files/ralajyixi8d5wkrjhvb6hi513pdvg73j-illumos-bootstrap-closure-roots.txt";
    hash = "sha256-EdNxcR628pU9pC6VBMsEn7XmLPYGAadHjv3Gw7/X+yw=";
  };
}
