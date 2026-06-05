# Build the bootstrap-tools closure for x86_64-illumos.
#
# Usage:
#   nix-build pkgs/stdenv/illumos-recipe/make-bootstrap-tools.nix -A build
#
# Produces:
#   result/on-server/closure.nar.xz       Stage-2 closure as xz-compressed
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
# entire stage 0–2 graph; only the user's target derivation builds.
#
# Contract: NO /opt/local refs in the closure (audit step). NO
# proto-strap refs (also audited; gcc-illumos's --enable-bootstrap
# self-link drops the host-cc RUNPATH carry-through). Sun ld is the
# system /usr/bin/ld and is NOT packaged; system /lib/64 supplies
# libc.
#
# From-source mode: defaults `pkgs` to `illumosUseBootstrapFiles =
# false`, so every root below is freshly compiled by the 3-stage
# chain (proto-strap → gcc-illumos --enable-bootstrap → final
# stdenv) rather than pulled from the prior closure via `bf.*`. Most
# artifacts cache-hit from /nix/store once the chain has been built
# in this checkout.
{
  pkgs ? import ../../.. { config = { illumosUseBootstrapFiles = false; }; },
}:
let
  inherit (pkgs) runCommand closureInfo lib;
  inherit (pkgs.buildPackages) dumpnar rsync xz;

  # singleBinary=false splits coreutils into one binary per tool
  # rather than a symlink farm pointing at a multi-call binary —
  # matches v2.3's choice; downstream builders PATH-resolve specific
  # tool names with no surprises.
  coreutils-big = pkgs.coreutils.override { singleBinary = false; };

in
rec {
  # Roots of the closure. Exposed as a top-level attribute so audit.nix
  # can deep-grep this exact set without duplicating the list. Anything
  # added here is also implicitly auditable.
  bootstrap-tools-packages = with pkgs; [
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

    # Compression — multi-output (bin/dev/out). `pkgs.xz` and
    # `pkgs.bzip2` default to their `.bin` output in current
    # nixpkgs; the explicit `.dev` lines pull in the headers as
    # separate closure roots.
    xz
    xz.dev
    gzip
    bzip2
    bzip2.dev
    zlib
    zlib.dev

    # Toolchain — gcc-illumos.out (driver), gcc-illumos.lib (libgcc_s
    # + libstdc++), plus binutils-unwrapped for gas / GNU binutils.
    # Sun ld is the system /usr/bin/ld, not packaged.
    gcc-illumos.out
    gcc-illumos.lib
    binutils-unwrapped

    # cc-wrapper helper.
    expand-response-params

    # patchelf: structural for the seed chain (krb5.lib
    # disallowedRequisites compliance). bootstrap-files-stages.nix
    # wires this into stage 0's extraNativeBuildInputs via
    # patchelf-pin.nix.
    patchelf

    # curlMinimal: also structural — seed chain's fetchurl wires
    # `curl = bf.curl.bin`. Out + bin outputs both — `out` carries
    # libcurl, `bin` carries the binary.
    curlMinimal.out
    curlMinimal.bin

    # Common build prerequisites preloaded so a fresh stage-0
    # from-source chain (and downstream autoconf/automake/etc.) does
    # not have to compile them before gcc-illumos becomes
    # available.
    gnum4
    flex
    bison
    perl
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
