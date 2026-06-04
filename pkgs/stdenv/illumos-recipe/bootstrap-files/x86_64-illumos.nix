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
    url = "https://www.shalman.org/files/qaj0s10z8kh1a60541ni41xwmwv3nxf5-illumos-bootstrap-closure.nar.xz";
    hash = "sha256-oP0E/O1PNSuM0BMmDsAHBP2hecw+rrozPoYmF6XGQms=";
  };
  closureRoots = import <nix/fetchurl.nix> {
    url = "https://www.shalman.org/files/wfcb58s0f8z7k79yxw45wwdr1vvf5sg6-illumos-bootstrap-closure-roots.txt";
    hash = "sha256-EvdOt7UOKLr5is87AYTEJhk4q59lWVn1pu8doB/uA88=";
  };
}
