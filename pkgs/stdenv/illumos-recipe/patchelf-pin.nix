# Wraps the Phase-4 patchelf build into a thin derivation that exposes
# bin/patchelf plus a nix-support/setup-hook registering patchELF as a
# fixupOutputHook. Used as an extraNativeBuildInputs entry on the
# illumos-recipe stdenv so every downstream package gets
# `patchelf --shrink-rpath` applied during fixupPhase.
#
# The store path is pinned via builtins.storePath to sidestep the eval-
# ordering problem (patchelf needs the stdenv to build; the stdenv
# needs patchelf as an input). Update after a patchelf rebuild:
#   nix-build -E 'with import ./. {}; patchelf' --no-out-link
# then paste the result here.
{
  patchelfStorePath ? builtins.storePath /nix/store/1bas7qp8p2slihjzqlabakzrblfl4ms6-patchelf-0.15.2,
  system ? "x86_64-illumos",
}:
derivation {
  name = "patchelf-illumos-pin";
  inherit system patchelfStorePath;
  builder = "/usr/bin/bash";
  args = [ ./patchelf-pin-builder.sh ];
  PATH = "/usr/bin:/usr/sbin";
}
