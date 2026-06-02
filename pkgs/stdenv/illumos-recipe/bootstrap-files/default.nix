# Discoverable wrapper for the x86_64-illumos bootstrap-tools artifacts.
#
# Consumers do:
#   bootstrapFiles = import pkgs/stdenv/illumos-recipe/bootstrap-files { };
#   bootstrapFiles.closure        # fetched .nar.xz store path
#   bootstrapFiles.closureRoots   # fetched roots.txt store path
#   bootstrapFiles.loaderScript   # path to load-illumos-closure.sh
#   bootstrapFiles.paths          # attrset of builtins.storePath refs
#                                 # for each closure root (used by
#                                 # ../default.nix when seeding stage 0
#                                 # from bootstrap-files)
#
# closure/closureRoots/loaderScript are eval-pure (fetchurl + path).
# paths requires the closure to be loaded into /nix/store already —
# eval fails on builtins.storePath if a path is missing. The loader
# script populates /nix/store; see ./x86_64-illumos-paths.nix.
{ }:
let
  files = import ./x86_64-illumos.nix;
in
{
  inherit (files) closure closureRoots;
  loaderScript = ./load-illumos-closure.sh;
  paths = import ./x86_64-illumos-paths.nix;
}
