# Discoverable wrapper for the x86_64-illumos bootstrap-tools artifacts.
#
# Consumers do:
#   bootstrapFiles = import pkgs/stdenv/illumos-recipe/bootstrap-files { };
#   bootstrapFiles.closure        # fetched .nar.xz store path
#   bootstrapFiles.closureRoots   # fetched roots.txt store path
#   bootstrapFiles.loaderScript   # path to load-illumos-closure.sh
#
# All three are eval-pure: no stdenv required. The loader is a plain
# bash script the consumer invokes (directly or wired into first-boot).
{ }:
let
  files = import ./x86_64-illumos.nix;
in
{
  inherit (files) closure closureRoots;
  loaderScript = ./load-illumos-closure.sh;
}
