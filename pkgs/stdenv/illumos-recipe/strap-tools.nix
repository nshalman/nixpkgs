# strap-tools: assembles gcc-illumos + binutils-illumos + host
# /usr/bin tools + /opt/local/bin (gmake, patch, ...) into a single
# `$out/bin` directory. Used as `nativePrefix` for the cc-wrapper /
# bintools-wrapper at stage 0 of pkgs/stdenv/illumos-recipe.
#
# Impurity is intentional for stage 0: /usr/bin and /opt/local are
# symlinked, not copied. The plan in SMARTOS_RECIPE_ROADMAP.md Phase 4
# replaces these with a nix-built bootstrap-tools tarball.
#
# binutils is taken via builtins.storePath to sidestep the eval-
# ordering problem (binutils-unwrapped needs the package set, but
# strap-tools is constructed before the package set exists). The
# pinned path is the output of the Phase-4-built binutils-illumos —
# update it after any binutils rebuild (`nix-build -E 'with import
# ./. {}; binutils-unwrapped'` produces it; eval it then update the
# default).
{
  gccIllumos ? import ../../development/compilers/gcc-illumos { },
  binutilsIllumos ? builtins.storePath /nix/store/chjhxnwkp22s1nr2x9w8wdmmi1w9f0w7-binutils-2.44,
  system ? "x86_64-illumos",
}:
derivation {
  name = "illumos-strap-tools";
  inherit system binutilsIllumos;
  gccIllumos = gccIllumos.out;
  gccIllumosLib = gccIllumos.lib;
  builder = "/usr/bin/bash";
  args = [ ./strap-tools-builder.sh ];
  PATH = "/usr/bin:/usr/sbin";
}
