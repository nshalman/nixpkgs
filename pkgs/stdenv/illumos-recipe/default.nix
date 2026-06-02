# Dispatcher between two stdenv chains for x86_64-illumos:
#
#  - bootstrap-files mode: seed stage 0 from pre-loaded
#    closure paths (../bootstrap-files/x86_64-illumos-paths.nix).
#    Two stages total: a wrap-cc/bintools seed + the illumos tooling
#    layer. The everyday consumer path — the closure has to be loaded
#    via ./bootstrap-files/load-illumos-closure.sh once before any
#    nix-build can succeed (builtins.storePath fails eval otherwise).
#
#  - from-source mode: the 5-stage chain (strap-tools + stages 0-4)
#    that builds the toolchain from sources, starting at proto-strap.
#    This is the path make-bootstrap-tools.nix uses to regenerate a
#    fresh bootstrap-files closure when bash etc bumps in upstream
#    nixpkgs. Drift story: bootstrap-files only changes when
#    explicitly refreshed.
#
# Selection: `config.illumosUseBootstrapFiles or false`. To opt in to
# bootstrap-files mode, pass
#   import ../../.. { config = { illumosUseBootstrapFiles = true; }; }
{
  lib,
  localSystem,
  crossSystem,
  config,
  overlays,
  crossOverlays ? [ ],
}@args:

assert crossSystem == localSystem;
assert localSystem.system == "x86_64-illumos";

if config.illumosUseBootstrapFiles or false then
  import ./bootstrap-files-stages.nix args
else
  import ./from-source.nix args
