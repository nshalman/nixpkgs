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
  # Use the scrubbed .out so consumers do not transitively pull
  # proto-strap (~841 MB) via byte string refs embedded in the
  # compiler driver. gccIllumos.lib stays untouched: it carries no
  # proto-strap refs and is shared by both variants. The scrub is
  # pinned via builtins.storePath because gcc-illumos-scrub takes
  # `pkgs ? import ../../../.. { }` (to pull python3 + gnugrep),
  # which causes infinite recursion when evaluated as part of the
  # stdenv used to construct that very `pkgs`. See pins.nix for the
  # rebuild recipe.
  pins ? import ./pins.nix,
  gccIllumosScrub ? pins.gccIllumosScrub,
  binutilsIllumos ? pins.binutilsIllumos,
  system ? "x86_64-illumos",
}:
derivation {
  name = "illumos-strap-tools";
  inherit system binutilsIllumos;
  gccIllumos = gccIllumosScrub;
  gccIllumosLib = gccIllumos.lib;
  builder = "/usr/bin/bash";
  args = [ ./strap-tools-builder.sh ];
  PATH = "/usr/bin:/usr/sbin";
}
