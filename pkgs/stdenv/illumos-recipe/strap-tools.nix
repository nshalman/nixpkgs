# proto-strap-cc: flat-layout view of the SmartOS-published
# proto.strap compiler (GCC 10.4.0) and GNU binutils, suitable as
# `nativePrefix` for cc-wrapper / bintools-wrapper at stage 0 of
# pkgs/stdenv/illumos-recipe/from-source.nix.
#
# proto-strap ships GNU binutils under `usr/gnu/bin/` with a `g`
# prefix (gas, gld, gar, gnm, …). cc-wrapper expects standard names
# under `$nativePrefix/bin/`. The builder strips the prefix when
# symlinking. ld is the exception — we use Sun ld at /usr/bin/ld
# because gcc-illumos is configured `--with-ld=/usr/bin/ld` and
# bypasses the wrapped ld in PATH anyway.
#
# Purely-proto-strap inputs; no /opt/local, no /usr/bin symlinks.
# Userland tools (bash, make, gawk, …) come from the consuming
# stdenv's `initialPath` — typically the bootstrap-files closure.
#
# Name in /nix/store stays `illumos-strap-tools` for git-history
# continuity with the prior strap-tools.nix; the role is now narrowly
# "proto-strap-cc," documented in from-source.nix.
{
  protoStrap ? import ../../development/compilers/proto-strap { },
  system ? "x86_64-illumos",
}:
derivation {
  name = "illumos-proto-strap-cc";
  inherit system;
  protoStrapPath = "${protoStrap}";
  builder = "/usr/bin/bash";
  args = [ ./strap-tools-builder.sh ];
  PATH = "/usr/bin:/usr/sbin";
}
