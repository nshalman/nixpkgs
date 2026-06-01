# strap-tools: assembles gcc-illumos + GNU binutils + host
# /usr/bin tools + /opt/local/bin (gmake, patch, ...) into a single
# `$out/bin` directory. Used as `nativePrefix` for the cc-wrapper /
# bintools-wrapper at stage 0 of pkgs/stdenv/illumos-recipe.
#
# Impurity is intentional for stage 0: /usr/bin and /opt/local are
# symlinked, not copied. Stages 0/1 outputs transitively reference
# proto-strap (whose pkgsrc-built binutils carry /opt/local in
# DT_RUNPATH) and /opt/local itself. Stage 2 rebuilds with nix-built
# userland and drops strap-tools entirely; stage 3 rebuilds the
# toolchain itself. Stage 3+ outputs are clean of both.
#
# GNU binutils source: proto-strap ships them under `usr/gnu/bin/`
# with a `g` prefix (gas, gld, gar, gnm, ...). The builder strips
# the prefix when symlinking into strap-tools/bin so wrappers see
# standard names. ld is the exception — we use Sun ld at /usr/bin/ld
# because gcc-illumos was configured with --with-ld=/usr/bin/ld and
# bypasses the wrapped ld in PATH anyway.
{
  gccIllumos ? import ../../development/compilers/gcc-illumos { },
  protoStrap ? import ../../development/compilers/proto-strap { },
  system ? "x86_64-illumos",
}:
derivation {
  name = "illumos-strap-tools";
  inherit system;
  gccIllumosOut = gccIllumos.out;
  gccIllumosLib = gccIllumos.lib;
  protoStrapPath = "${protoStrap}";
  builder = "/usr/bin/bash";
  args = [ ./strap-tools-builder.sh ];
  PATH = "/usr/bin:/usr/sbin";
}
