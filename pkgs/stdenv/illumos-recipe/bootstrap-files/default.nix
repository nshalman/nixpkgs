# Discoverable wrapper for the x86_64-illumos bootstrap-tools artifacts.
#
# Consumers do:
#   bootstrapFiles = import pkgs/stdenv/illumos-recipe/bootstrap-files { };
#   bootstrapFiles.closure        # fetched .nar.xz store path
#   bootstrapFiles.closureRoots   # fetched roots.txt store path
#   bootstrapFiles.loaderScript   # path to load-illumos-closure.sh
#   bootstrapFiles.paths          # attrset of builtins.storePath refs
#                                 # for each closure root (used by
#                                 # ../bootstrap-files-stages.nix when
#                                 # seeding stage 0 from bootstrap-files)
#   bootstrapFiles.allPaths       # flat list of every closure root,
#                                 # suitable for closureInfo.rootPaths
#                                 # (used by ../make-zone-image.nix to
#                                 # pre-load the seed into the shipped
#                                 # image's /nix/store)
#
# closure/closureRoots/loaderScript are eval-pure (fetchurl + path).
# paths and allPaths require the closure to be loaded into /nix/store
# already — eval fails on builtins.storePath if a path is missing.
# The loader script populates /nix/store; see ./x86_64-illumos-paths.nix.
{ }:
let
  files = import ./x86_64-illumos.nix;
  pathsAttrs = import ./x86_64-illumos-paths.nix;
in
{
  inherit (files) closure closureRoots;
  loaderScript = ./load-illumos-closure.sh;
  paths = pathsAttrs;

  # Flat list mirroring closure-roots.txt content. Keep in sync with
  # ../make-bootstrap-tools.nix's bootstrap-tools-packages: any root
  # added there must appear here too.
  allPaths = with pathsAttrs; [
    bash
    coreutils
    gnutar
    findutils
    gnumake
    gnused
    gnugrep
    gawk
    diffutils
    patch
    xz-bin
    xz-dev
    gzip
    bzip2-bin
    bzip2-dev
    zlib
    zlib-dev
    gcc-illumos.out
    gcc-illumos.lib
    binutils-unwrapped
    expand-response-params
    patchelf
    curl.out
    curl.bin
  ];
}
