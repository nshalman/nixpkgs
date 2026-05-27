# strap-tools: assembles gcc-illumos + proto-strap binutils + host
# /usr/bin tools + /opt/local/bin (gmake, patch, ...) into a single
# `$out/bin` directory. Used as `nativePrefix` for the cc-wrapper /
# bintools-wrapper at stage 0 of pkgs/stdenv/illumos-recipe.
#
# Impurity is intentional for Phase 2: /usr/bin and /opt/local are
# symlinked, not copied. The plan in SMARTOS_RECIPE_ROADMAP.md Phase 4
# replaces these with a nix-built bootstrap-tools tarball.
{
  gccIllumos ? import ../../development/compilers/gcc-illumos { },
  protoStrap ? import ../../development/compilers/proto-strap { },
  system ? "x86_64-illumos",
}:
derivation {
  name = "illumos-strap-tools";
  inherit system gccIllumos protoStrap;
  builder = "/usr/bin/bash";
  args = [ ./strap-tools-builder.sh ];
  PATH = "/usr/bin:/usr/sbin";
}
