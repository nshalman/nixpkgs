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
#     /etc/nix/nix.conf                       single-user, default substituter (cache.nixos.org)
#
# First-boot step (out of scope for this derivation; whoever assembles
# the zone root plumbs it via SMF / rc.d / etc.):
#
#   nix-store --load-db < /nix/var/nix/.reginfo
#
# After that, `nix-build`/`nix-store --realise` work. The shipped
# /nix/store contains the bootstrap-files closure (gcc-illumos,
# binutils, GNU userland, patchelf — see ./bootstrap-files/) pre-
# loaded, so the stdenv chain that eval'd via bootstrap-files-stages
# cache-hits without fetching closure.nar.xz at first boot.
#
# Iteration 1 scope: single-user, no /etc/passwd or /etc/profile
# shipped (the zone root those things live in is assembled outside
# this derivation). Layer on as we learn what's needed.
{
  pkgs ? import ../../.. { },
  # Ship a copy of this nixpkgs tree at /etc/nixos/nixpkgs and set the
  # default nix-path so `<nixpkgs>` resolves out of the box. Default
  # off because the snapshot's hash invalidates on any tree edit (so
  # zone-tree rebuilds on every iteration we do). Flip to true when
  # building a final / shippable image.
  shipNixpkgs ? false,
  # Pre-load the bootstrap-files closure (gcc-illumos + binutils + GNU
  # userland + patchelf — 22 store paths, ~414 MiB compressed) into
  # the shipped /nix/store. Without this, the seed stdenv chain
  # (bootstrap-files-stages.nix) fails eval on a fresh zone because
  # builtins.storePath references the closure roots; the consumer has
  # to run bootstrap-files/load-illumos-closure.sh manually before any
  # nix-build works. Default on — this is what makes the image
  # self-contained.
  shipBootstrapFiles ? true,
}:
let
  inherit (pkgs) runCommand closureInfo writeText lib;
  inherit (pkgs.buildPackages) xz gnutar rsync;

  # NixOS-style "system" env: one store path with a bin/ etc/ share/...
  # tree of symlinks into every constituent package. Lets users type
  # `bash`, `nix`, etc. from a single PATH entry, and provides the
  # canonical /nix/var/nix/profiles/default symlink target. The
  # definition lives in zone-root/system.nix so the in-zone editable
  # template at /etc/nixos/system.nix and the initial profile baked
  # into the image are the same derivation — extending one extends
  # both.
  systemEnv = import ./zone-root/system.nix { inherit pkgs; };

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

  bootstrapFiles = import ./bootstrap-files { };

  closure = closureInfo {
    rootPaths =
      [ systemEnv ]
      ++ lib.optional shipNixpkgs nixpkgsSnapshot
      ++ lib.optionals shipBootstrapFiles bootstrapFiles.allPaths;
  };

  nixConf = writeText "nix.conf" (''
    experimental-features = nix-command flakes
    build-users-group =
    # Leave `substituters` at the compile-time default
    # (https://cache.nixos.org). FOD source tarballs are content-
    # addressed by hash and not platform-specific, so the public
    # cache serves them across illumos / linux / darwin alike — that
    # avoids the seed chain's fetchurl builder having to actually run
    # (the curl=null variant is still in place for cycle reasons;
    # bd nix-mva tracks restoring a real curl in the seed).
    trusted-users = root
    # Our nix-2.33.6+9 baked in `system = x86_64-sunos` at autoconf time
    # (illumos uname -s = SunOS, lowercased). nixpkgs has no
    # "x86_64-sunos" platform — it uses "x86_64-illumos" (or
    # "x86_64-solaris"). Override here so builtins.currentSystem and
    # default eval-system pick the right value.
    system = x86_64-illumos
    extra-platforms = x86_64-illumos x86_64-sunos
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
    mkdir -p $out/nix/store $out/nix/var/nix/profiles \
             $out/nix/var/nix/gcroots $out/etc/nix

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

    ${lib.optionalString shipBootstrapFiles ''
      # GC roots for the bootstrap-files closure. Without these, a
      # `nix-store --gc` inside the zone wipes gcc-illumos / binutils-
      # unwrapped / patchelf / gnum4 / flex / bison / perl / etc.
      # because they aren't reachable from /nix/var/nix/profiles/default
      # (the default profile pins nix + bash + the few user-facing
      # tools, not the stage-0 toolchain that lives in the closure to
      # make subsequent nix-builds cache-hit). One symlink per closure
      # root, named by its hash-prefixed store basename for
      # uniqueness.
      mkdir -p $out/nix/var/nix/gcroots/illumos-bootstrap-tools
      ${lib.concatMapStringsSep "\n" (p:
        ''ln -s ${p} "$out/nix/var/nix/gcroots/illumos-bootstrap-tools/$(basename ${p})"''
      ) bootstrapFiles.allPaths}
    ''}

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
