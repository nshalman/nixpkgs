# Build a self-contained nix zone-image tarball for x86_64-illumos.
#
# Usage:
#   nix-build pkgs/stdenv/illumos-recipe/make-zone-image.nix -A zone-image
#
# Produces:
#   result   the .tar.xz, sized roughly = nix's runtime closure (~600 MB
#            uncompressed). Contents, when extracted at /:
#
#     /nix/store/...                          every path in nix's closure
#     /nix/var/nix/.reginfo                   closureInfo's registration file
#     /nix/var/nix/profiles/default           symlink -> /nix/store/.../nix
#     /etc/nix/nix.conf                       single-user, no substituters
#
# First-boot step (out of scope for this derivation; whoever assembles
# the zone root plumbs it via SMF / rc.d / etc.):
#
#   nix-store --load-db < /nix/var/nix/.reginfo
#
# After that, `nix-build`/`nix-store --realise` work. Builds that need
# stage-0 stdenv (bash, coreutils, gcc-illumos, binutils-illumos, ...)
# fetch bootstrap-tools.tar.xz over HTTP per pkgs/stdenv/illumos/
# bootstrap-files/x86_64-illumos.nix; no /opt/local needed.
#
# Iteration 1 scope: single-user, no substituters, no /etc/passwd or
# /etc/profile shipped (the zone root those things live in is assembled
# outside this derivation). Layer on as we learn what's needed.
{
  pkgs ? import ../../.. { },
  # The nix package to ship. Default is the Phase-5-step-15 build
  # (nix-2.33.6+9 against the illumos-recipe stdenv), pinned via
  # storePath so we don't accidentally rebuild a different nix version
  # — pkgs.nix in this nixpkgs branch is 2.31.5 and won't compile on
  # illumos without further patches.
  nix ? builtins.storePath /nix/store/1x7hzfrph24yzm47pr5xk5gs5gi9h9c5-nix-2.33.6+9,
}:
let
  inherit (pkgs) runCommand closureInfo writeText lib;
  inherit (pkgs.buildPackages) xz gnutar;

  closure = closureInfo { rootPaths = [ nix ]; };

  nixConf = writeText "nix.conf" ''
    experimental-features = nix-command flakes
    build-users-group =
    substituters =
    trusted-users = root
  '';

in
rec {
  # The on-disk staging tree, as a regular derivation we can inspect.
  # Useful for debugging without pinging the tar+xz step.
  zone-tree = runCommand "nix-zone-tree" { } ''
    mkdir -p $out/nix/store $out/nix/var/nix/profiles $out/etc/nix

    # Copy every store path in nix's runtime closure. --no-preserve=mode
    # so chmod -R works afterwards (store paths are r-x by default).
    for p in $(cat ${closure}/store-paths); do
      cp -aHR --no-preserve=mode "$p" $out/nix/store/
    done
    chmod -R u+w $out/nix/store

    # The registration file consumed by `nix-store --load-db`.
    cp ${closure}/registration $out/nix/var/nix/.reginfo

    # Single profile pointing at the nix package. Use a relative symlink
    # so the zone's filesystem layout isn't pinned to the build host.
    ln -s ${nix} $out/nix/var/nix/profiles/default

    # Single-user nix.conf.
    cp ${nixConf} $out/etc/nix/nix.conf
  '';

  # Tarball of the staging tree, gzip-tar to keep this build cheap; bump
  # to xz when the closure stabilizes. Reproducible flags mirror what
  # make-bootstrap-tools.nix uses.
  zone-image = runCommand "nix-zone-image.tar.xz"
    {
      nativeBuildInputs = [ xz gnutar ];
    }
    ''
      cd ${zone-tree}
      XZ_OPT="-6 -T 4" tar cJf $out \
        --hard-dereference --sort=name --numeric-owner --owner=0 --group=0 --mtime=@1 \
        ./nix ./etc
    '';
}
