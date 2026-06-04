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
  # Refresher pkgs. Defaults to the dispatcher's bootstrap-files mode
  # so `pkgs.gnum4` / `pkgs.flex` / etc. are built atop the seed
  # stdenv that uses `bf.gcc-illumos` as the cc. The existing closure
  # roots (gcc-illumos, binutils, bash, coreutils, …) are pulled
  # **directly** from `bf.*` below — no rebuild of artifacts already
  # in the previous closure. An additive refresh that just adds new
  # packages costs only those packages' compile time.
  pkgs ? import ../../.. { },
}:
let
  inherit (pkgs) runCommand closureInfo lib;
  inherit (pkgs.buildPackages) dumpnar rsync xz;

  # Previous-closure store paths. Used directly as closure roots so we
  # ship the same audited gcc-illumos / binutils / userland the
  # previous iteration already validated. Refreshing artifacts in this
  # set means swapping the path in ./bootstrap-files/x86_64-illumos-paths.nix
  # after a from-source rebuild via the dispatcher's
  # illumosUseBootstrapFiles=false mode (separate workflow).
  bf = (import ./bootstrap-files { }).paths;

in
rec {
  # Roots of the closure. Exposed as a top-level attribute so audit.nix
  # can deep-grep this exact set without duplicating the list. Anything
  # added here is also implicitly auditable.
  bootstrap-tools-packages = [
    # ---- Existing roots, reused as-is from the previous closure. ----
    # These are raw storePaths (no rebuild). bf.* is the source of
    # truth for what's in the previous iteration; refreshing any of
    # these requires a from-source rebuild (illumosUseBootstrapFiles
    # =false), then resyncing bootstrap-files/x86_64-illumos-paths.nix.

    # GNU userland
    bf.bash
    bf.coreutils
    bf.gnutar
    bf.findutils
    bf.gnumake
    bf.gnused
    bf.gnugrep
    bf.gawk
    bf.diffutils
    bf.patch

    # Compression
    bf.xz-bin
    bf.xz-dev
    bf.gzip
    bf.bzip2-bin
    bf.bzip2-dev
    bf.zlib
    bf.zlib-dev

    # Toolchain — gcc-illumos.out (driver), gcc-illumos.lib (libgcc_s
    # + libstdc++), plus binutils-unwrapped for gas / GNU binutils.
    # Sun ld is the system /usr/bin/ld, not packaged.
    bf.gcc-illumos.out
    bf.gcc-illumos.lib
    bf.binutils-unwrapped

    # cc-wrapper helper.
    bf.expand-response-params

    # patchelf: structural for the seed chain (krb5.lib
    # disallowedRequisites compliance). bootstrap-files-stages.nix
    # wires this into stage 0's extraNativeBuildInputs via
    # patchelf-pin.nix.
    bf.patchelf

    # curlMinimal: also structural — seed chain's fetchurl wires
    # `curl = bf.curl.bin`. Out + bin outputs both — `out` carries
    # libcurl, `bin` carries the binary.
    bf.curl.out
    bf.curl.bin

    # ---- New additions for this refresh. ----
    # Built atop the seed stdenv (which uses bf.gcc-illumos as cc);
    # transitively reference bf.* paths above. With these baked into
    # the closure, a fresh stage-0 from-source chain doesn't have to
    # compile them before it can compile gcc-illumos. Downstream
    # packages that need them (autoconf, automake, …) also cache-hit
    # when their build inputs match.
    pkgs.gnum4
    pkgs.flex
    pkgs.bison
    pkgs.perl
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
