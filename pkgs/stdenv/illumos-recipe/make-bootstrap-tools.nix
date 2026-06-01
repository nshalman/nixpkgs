# Build the bootstrap-tools tarball for x86_64-illumos.
#
# Usage:
#   nix-build pkgs/stdenv/illumos-recipe/make-bootstrap-tools.nix -A build
#
# Produces:
#   result/on-server/unpack.nar.xz          minimal unpacker (bash, xz, tar, mkdir)
#   result/on-server/bootstrap-tools.tar.xz frozen stdenv userland
#
# Tarballs are uploaded out-of-band; bootstrap-files/x86_64-illumos.nix
# references them by URL + sha256.
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
  inherit (pkgs.buildPackages) dumpnar rsync;

  # gcc-illumos isn't wired into all-packages.nix yet; import directly.
  # The freestanding import builds with proto-strap as host compiler,
  # so the resulting .out transitively references proto-strap. For a
  # truly clean bootstrap-tools tarball we want stage-3's self-rebuilt
  # gcc-illumos, but stage-3's gcc-illumos isn't exposed via pkgs.* —
  # plumbing that through all-packages.nix is its own piece of work.
  # Until then, this tarball is "build-time honest" (proto-strap shows
  # up as a build input transitively) but Phase 5 work has been
  # consuming the stage-3 toolchain via pkgs.stdenv anyway.
  gcc-illumos = import ../../development/compilers/gcc-illumos { };

  # Binutils for the tarball comes from the package set. Pre-pin
  # removal this was a builtins.storePath pin (chjhxnwkp...-binutils-
  # 2.44); now we use whatever stage 4's pkgs resolves to, which on
  # illumos-recipe is the stage-2-built clean binutils-unwrapped.
  binutils-illumos = pkgs.binutils-unwrapped;

  # Use rsync for the closure copy, consistent with make-zone-image.nix
  # and make-zone-root.nix. rsync -a preserves modes (including the
  # exec bit on binaries) without the cp `--no-preserve=mode` gotcha
  # that would otherwise strip exec bits and yield non-executable
  # binaries after nix's post-build read-only canonicalization.
  pack-all =
    packCmd: name: packages: fixups:
    (runCommand name
      {
        nativeBuildInputs = [
          dumpnar
          rsync
        ];
      }
      ''
        base=$PWD
        requisites="$(cat ${closureInfo { rootPaths = packages; }}/store-paths)"

        for f in $requisites; do
          rsync -a "$f/" "$base/"
        done
        chmod -R +w "$base"
        cd $base

        rm -rf nix nix-support
        mkdir -p nix-support
        for dir in $requisites; do
          cd "$dir/nix-support" 2>/dev/null || continue
          for f in $(find . -type f); do
            mkdir -p "$base/nix-support/$(dirname $f)"
            cat $f >>"$base/nix-support/$f"
          done
        done
        rm -f $base/nix-support/propagated-build-inputs
        cd $base

        ${fixups}

        ${packCmd}
      ''
    );

  # Memory-conservative xz settings (illumos VM is RAM-bound during the
  # tarball pack step).
  nar-all = pack-all "dumpnar . | xz -6 -T 4 >$out";
  tar-all = pack-all "XZ_OPT=\"-6 -T 4\" tar cJf $out --hard-dereference --sort=name --numeric-owner --owner=0 --group=0 --mtime=@1 .";

  coreutils-big = pkgs.coreutils.override { singleBinary = false; };

  mkdir = runCommand "mkdir" { coreutils = coreutils-big; } ''
    mkdir -p $out/bin
    cp $coreutils/bin/mkdir $out/bin
  '';

in
rec {
  # Minimal unpacker shipped alongside bootstrap-tools.tar.xz.
  unpack =
    nar-all "unpack.nar.xz"
      (with pkgs; [
        bash
        mkdir
        xz
        gnutar
      ])
      ''
        rm -rf include lib/*.a lib/bash share
      '';

  # Roots of the tarball's closure. Exposed as a top-level attribute
  # so audit.nix can deep-grep this exact set without duplicating the
  # list. Anything added here is also implicitly auditable.
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

  # Main userland tarball. Toolchain (gcc-illumos + proto-strap binutils)
  # is packaged here so a fresh consumer doesn't need /opt/local at all.
  bootstrap-tools = tar-all "bootstrap-tools.tar.xz" bootstrap-tools-packages ''
    # Trim non-essential docs to keep the tarball small.
    rm -rf share/info share/doc share/man
  '';

  build = runCommand "illumos-bootstrap-tools" { } ''
    mkdir -p $out/on-server
    ln -s ${unpack} $out/on-server/unpack.nar.xz
    ln -s ${bootstrap-tools} $out/on-server/bootstrap-tools.tar.xz
  '';
}
