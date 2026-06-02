# Build the bootstrap-tools closure for x86_64-illumos.
#
# Usage:
#   nix-build pkgs/stdenv/illumos-recipe/make-bootstrap-tools.nix -A build
#
# Produces:
#   result/on-server/closure.nar.xz       Stage-3 closure as xz-compressed
#                                         NAR. Payload layout (after the
#                                         NAR is restored into <work>):
#                                           <work>/nix/store/<each-path>/...
#                                           <work>/nix-path-registration
#                                         A receiver moves
#                                         <work>/nix/store/* into
#                                         /nix/store/ and runs
#                                         `nix-store --load-db <
#                                         <work>/nix-path-registration`.
#   result/on-server/closure-roots.txt    One store path per line — the
#                                         explicit GC roots (i.e. the
#                                         contents of bootstrap-tools-
#                                         packages, not the full closure).
#                                         A receiver registers these as
#                                         GC roots so the loaded closure
#                                         is not immediately collectible.
#
# Once a receiver has loaded the closure, `nix-build` cache-hits the
# entire stage 0–3 graph; only stage 4 wrap + the user's target derive
# actually rebuild.
#
# Contract: NO /opt/local refs in the closure (audit step). /usr/* refs
# are expected — gcc-illumos's compiler driver binaries (xgcc, cc1,
# cc1plus, ...) carry /usr/gcc/10/lib/amd64 in RUNPATH inherited from
# the proto-strap host compiler that BUILT gcc-illumos. That resolves
# from the host illumos /usr/gcc/10, which is fine for a system-managed
# compiler runtime. Eliminating this requires self-hosted gcc-illumos
# (Phase 6 step 21); cosmetic until then.
#
# Not packaged: libc (system /lib/64 is used) and patchelf (illumos ELF
# is laid out differently; Sun ld emits clean RUNPATHs directly).
{
  pkgs ? import ../../.. { },
}:
let
  inherit (pkgs) runCommand closureInfo lib;
  inherit (pkgs.buildPackages) dumpnar rsync xz;

  # Use the cc that actually backs `pkgs.stdenv` — i.e. the stage-3
  # self-host gcc-illumos, the same derivation that built every other
  # path in this closure. Picking it here keeps the bootstrap-tools
  # closure self-consistent (one compiler at the bottom of the graph)
  # and ensures the closure pack is a no-op on any host that already
  # has stage 3 cached. Picking `pkgs.gcc-illumos` instead would be a
  # tier-up rebuild (gcc-illumos built using stage 4's cc as host) —
  # also clean, but requires an autoconf-heavy ~30-60 min rebuild not
  # already in the store. Earlier revisions used a freestanding
  # `import ../../development/compilers/gcc-illumos { }`, which
  # defaults `host` to a fresh proto-strap import and drags proto-strap
  # (with its /opt/local refs and /usr/gcc/10 RUNPATH) into the
  # closure — caught by audit.nix.
  gcc-illumos = pkgs.stdenv.cc.cc;

  # Binutils for the closure comes from the package set. Pre-pin removal
  # this was a builtins.storePath pin (chjhxnwkp...-binutils-2.44); now
  # we use whatever stage 4's pkgs resolves to, which on illumos-recipe
  # is the stage-2-built clean binutils-unwrapped.
  binutils-illumos = pkgs.binutils-unwrapped;

  coreutils-big = pkgs.coreutils.override { singleBinary = false; };

in
rec {
  # Roots of the closure. Exposed as a top-level attribute so audit.nix
  # can deep-grep this exact set without duplicating the list. Anything
  # added here is also implicitly auditable.
  bootstrap-tools-packages =
    with pkgs;
    [
      # GNU userland
      coreutils-big
      bash
      gnutar
      findutils
      gnumake
      gnused
      gnugrep
      gawk
      diffutils
      patch

      # Compression
      xz
      xz.dev
      gzip
      bzip2
      bzip2.dev
      zlib
      zlib.dev

      # Toolchain — gcc-illumos.out (driver), gcc-illumos.lib
      # (libgcc_s + libstdc++), plus binutils-unwrapped for gas /
      # GNU binutils (ld, ld.bfd, ld.gold, as, ar, nm, ...). Sun ld
      # is the system /usr/bin/ld, not packaged.
      gcc-illumos.out
      gcc-illumos.lib
      binutils-illumos

      # cc-wrapper helper
      expand-response-params
    ];

  # Closure metadata: store-paths (full transitive list) and
  # registration (input to `nix-store --load-db`).
  closure-info = closureInfo { rootPaths = bootstrap-tools-packages; };

  # Closure payload as an xz-compressed NAR. The NAR's root contains:
  #   nix/store/<each-closure-path>/...
  #   nix-path-registration              (input to nix-store --load-db)
  #
  # rsync -a preserves modes (including exec bits) without the cp
  # `--no-preserve=mode` gotcha that would strip exec; consistent with
  # the pack steps in make-zone-image.nix and make-zone-root.nix.
  #
  # Memory-conservative xz settings (illumos VM is RAM-bound during the
  # pack step).
  closure-nar =
    runCommand "illumos-bootstrap-closure.nar.xz"
      {
        nativeBuildInputs = [
          dumpnar
          rsync
          xz
        ];
      }
      ''
        base=$PWD/payload
        mkdir -p "$base/nix/store"

        while read -r p; do
          rsync -a "$p" "$base/nix/store/"
        done < ${closure-info}/store-paths

        cp ${closure-info}/registration "$base/nix-path-registration"

        # Payload subtrees inherit read-only modes from their store
        # sources; loosen so nix's post-build canonicalisation can
        # retime files before sealing the output.
        chmod -R u+w "$base"

        cd "$base"
        dumpnar . | xz -6 -T 4 > $out
      '';

  # Explicit GC roots — just the bootstrap-tools-packages entries, not
  # the transitive closure. Receivers wire these into /nix/var/nix/
  # gcroots so the imported closure isn't immediately collectible.
  closure-roots = runCommand "illumos-bootstrap-closure-roots.txt" { } ''
    printf '%s\n' ${toString bootstrap-tools-packages} > $out
  '';

  build = runCommand "illumos-bootstrap-tools" { } ''
    mkdir -p $out/on-server
    ln -s ${closure-nar} $out/on-server/closure.nar.xz
    ln -s ${closure-roots} $out/on-server/closure-roots.txt
  '';
}
