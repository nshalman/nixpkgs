# Optional wrapper around a previously-built patchelf that exposes
# bin/patchelf plus a nix-support/setup-hook registering patchELF as
# a fixupOutputHook. When non-null, this is added to the
# illumos-recipe stdenv's extraNativeBuildInputs so downstream
# packages get `patchelf --shrink-rpath` during fixupPhase.
#
# Default is null: stages 0/1 build without the fixupOutputHook
# (RPATHs stay unshrunk — longer than they need to be but valid).
# Stage 2 consumes prevStage.patchelf directly, so its outputs ARE
# shrunk; stage 3+ rebuild the toolchain cleanly. This means the
# default chain has unshrunk RPATHs only on stage 0/1 outputs, which
# don't appear in shippable closures.
#
# To attach a pre-built patchelf for stage 0/1 (faster iteration),
# pass `patchelfStorePath = builtins.storePath /nix/store/...`
# explicitly.
{
  patchelfStorePath ? null,
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
