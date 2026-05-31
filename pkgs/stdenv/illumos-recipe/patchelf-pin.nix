# Wraps the Phase-4 patchelf build into a thin derivation that exposes
# bin/patchelf plus a nix-support/setup-hook registering patchELF as a
# fixupOutputHook. Used as an extraNativeBuildInputs entry on the
# illumos-recipe stdenv so every downstream package gets
# `patchelf --shrink-rpath` applied during fixupPhase.
#
# The store path is pinned via builtins.storePath (see pins.nix) to
# sidestep the eval-ordering problem (patchelf needs the stdenv to
# build; the stdenv needs patchelf as an input). Stage 2 doesn't use
# this wrapper — it consumes prevStage.patchelf directly.
#
# Bootstrap escape hatch: set pins.patchelf = null (or pass
# patchelfStorePath = null) and this evaluates to null. default.nix's
# makeStdenv omits the result from extraNativeBuildInputs in that
# case, so stages 0/1 build without the fixupOutputHook (RPATHs stay
# unshrunk but builds succeed). Use this when recovering from a GC of
# the pinned path: rebuild patchelf via `nix-build -E '(import ./.
# {}).patchelf'` with pins.patchelf=null, then restore the pin.
{
  pins ? import ./pins.nix,
  patchelfStorePath ? pins.patchelf,
  system ? "x86_64-illumos",
}:
if patchelfStorePath == null then
  null
else
  derivation {
    name = "patchelf-illumos-pin";
    inherit system patchelfStorePath;
    builder = "/usr/bin/bash";
    args = [ ./patchelf-pin-builder.sh ];
    PATH = "/usr/bin:/usr/sbin";
  }
