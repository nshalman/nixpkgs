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
  # The nix package to ship. We deliberately use nixVersions.nix_2_33
  # rather than the package-set default `pkgs.nix` — the default is
  # 2.31.5 in this branch and doesn't compile on illumos.
  # nixVersions.nix_2_33 is 2.33.6+9, the Phase-5-step-15 build with
  # the illumos portability work. Use .out (not the package itself)
  # because buildEnv would otherwise try to include outputs like `man`
  # that haven't been built.
  nix ? pkgs.nixVersions.nix_2_33.out,
  bash ? pkgs.bashInteractive,
  # Additional packages (or store paths) to expose via the system env.
  # Default set:
  #   coreutils + rsync + gitMinimal — usual GNU userland alongside
  #     bash/nix, plus git so users can `git clone` a nixpkgs tree.
  #   cacert — Mozilla CA bundle at $out/etc/ssl/certs/ca-bundle.crt;
  #     zone-root/builder.sh wires /etc/ssl/certs symlinks to it.
  extraRootPaths ? [
    pkgs.coreutils
    pkgs.rsync
    pkgs.gitMinimal
    pkgs.cacert
  ],
  # Ship a copy of this nixpkgs tree at /etc/nixos/nixpkgs and set the
  # default nix-path so `<nixpkgs>` resolves out of the box. Default
  # off because the snapshot's hash invalidates on any tree edit (so
  # zone-tree rebuilds on every iteration we do). Flip to true when
  # building a final / shippable image.
  shipNixpkgs ? false,
  # Bundle pkgs.stdenv's full closure into the zone's /nix/store so
  # `nix-build '<nixpkgs>' -A hello` works offline (no fetch of
  # bootstrap-tools.tar.xz). NOT added to the buildEnv'd PATH — stdenv
  # is invoked via nix-build, not directly. Default off; flip to true
  # for the publicly-shippable image.
  shipStdenv ? false,
}:
let
  inherit (pkgs) runCommand closureInfo writeText buildEnv lib;
  inherit (pkgs.buildPackages) xz gnutar rsync;

  # NixOS-style "system" env: one store path with a bin/ etc/ share/...
  # tree of symlinks into every constituent package. Lets users type
  # `bash`, `nix`, etc. from a single PATH entry, and provides the
  # canonical /nix/var/nix/profiles/default symlink target. Extend the
  # `paths` list to expose more tools in the merged tree.
  systemEnv = buildEnv {
    name = "nix-zone-system";
    paths = [ nix bash ] ++ extraRootPaths;
    pathsToLink = [ "/bin" "/etc" "/lib" "/libexec" "/share" ];
    ignoreCollisions = true;
  };

  # Snapshot of THIS nixpkgs tree, ingested into the store, when
  # shipNixpkgs = true. .git/result/outputs/.direnv filtered out.
  nixpkgsSnapshot =
    if shipNixpkgs then
      builtins.path {
        path = ../../..;
        name = "nixpkgs-snapshot";
        filter =
          path: type:
          let
            base = baseNameOf path;
          in
          base != ".git"
          && base != "result"
          && base != "outputs"
          && base != ".direnv";
      }
    else null;

  closure = closureInfo {
    rootPaths =
      [ systemEnv ]
      ++ lib.optional shipNixpkgs nixpkgsSnapshot
      ++ lib.optional shipStdenv pkgs.stdenv;
  };

  nixConf = writeText "nix.conf" (''
    experimental-features = nix-command flakes
    build-users-group =
    substituters =
    trusted-users = root
  '' + lib.optionalString shipNixpkgs ''
    # Default NIX_PATH so `<nixpkgs>` resolves out of the box. Users
    # can override per-session via NIX_PATH=... or by replacing the
    # /etc/nixos/nixpkgs symlink with their own tree.
    nix-path = nixpkgs=/etc/nixos/nixpkgs
  '');

in
rec {
  # The on-disk staging tree, as a regular derivation we can inspect.
  # Useful for debugging without pinging the tar+xz step.
  zone-tree = runCommand "nix-zone-tree" { nativeBuildInputs = [ rsync ]; } ''
    mkdir -p $out/nix/store $out/nix/var/nix/profiles $out/etc/nix

    # Copy every store path in the closure. rsync -a preserves modes
    # (including the exec bit on binaries) without the cp
    # `--no-preserve=mode` gotcha that would otherwise yield 444 across
    # the board after nix's post-build read-only canonicalization.
    # `chmod -R u+w` adds write so the tree is mutable for the rest of
    # this builder; nix strips it back to 555/444 after exit.
    for p in $(cat ${closure}/store-paths); do
      rsync -a "$p" $out/nix/store/
    done
    chmod -R u+w $out/nix/store

    # The registration file consumed by `nix-store --load-db`.
    cp ${closure}/registration $out/nix/var/nix/.reginfo

    # Default profile points at the buildEnv'd system tree so users see
    # `bash`, `nix`, etc. through a single bin/ dir.
    ln -s ${systemEnv} $out/nix/var/nix/profiles/default

    # Single-user nix.conf.
    cp ${nixConf} $out/etc/nix/nix.conf

    ${lib.optionalString shipNixpkgs ''
      # Ship the nixpkgs source tree at /etc/nixos/nixpkgs so the default
      # NIX_PATH (set in nix.conf above) and `<nixpkgs>` references in
      # /etc/nixos/system.nix work out of the box.
      mkdir -p $out/etc/nixos
      ln -s ${nixpkgsSnapshot} $out/etc/nixos/nixpkgs
    ''}
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
