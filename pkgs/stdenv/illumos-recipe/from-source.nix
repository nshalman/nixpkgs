# Stdenv for x86_64-illumos — from-source mode.
#
# 3-stage chain (was 5; collapsed once `--enable-bootstrap` became the
# gcc-illumos default and the pin overlay was retired):
#
#   Stage 0 (raw): cc-wrapper around proto-strap's GCC 10.4.0;
#     bintools-wrapper around proto-strap's GNU binutils (gas/ar/nm/…).
#     Both via the `proto-strap-cc` wrapper derivation (strap-tools.nix)
#     which flattens proto-strap's nested `/usr/gcc/10/` + `/usr/gnu/`
#     layout into a single `$out/bin/` with standard names.
#     `initialPath` is the bootstrap-files userland (bf.bash, bf.gnumake,
#     bf.gawk, bf.gnused, bf.gnugrep, bf.findutils, …) — no /opt/local,
#     no host-/usr/bin symlinks. The seed chain
#     (bootstrap-files-stages.nix) consumes the same `bf.*` paths, so
#     from-source and seed are now structurally parallel; the only
#     difference is whether `cc` is built from sources or pulled from
#     the previous closure.
#
#   Stage 1: allPackages atop stage 0. `pkgs.gcc-illumos` compiles with
#     `--enable-bootstrap` so its stage-3 self-link drops proto-strap
#     from cc1's RUNPATH. Userland (bash, binutils-unwrapped, …) is
#     rebuilt by allPackages — these are clean nixpkgs builds atop
#     the proto-strap stage 0.
#
#   Stage 2 (final): drop proto-strap entirely. Rewrap cc with stage-1's
#     `gcc-illumos.out` + `binutils-unwrapped`. `initialPath` uses
#     stage-1's userland (no more `bf.*` references at the chain level).
#     Tooling-layer hooks (strip-illumos-libtool-flags, /usr/bin in
#     PATH for isainfo/print/uname) attach here. `pkgs.*` at stage 2
#     is the shippable artifact set.
#
# Why 3 not 5: with `--enable-bootstrap` gcc-illumos's output is
# self-clean at stage 1 — the host-cc carry-through that the old
# stage 3 existed to re-link no longer happens. The old stage 4
# (tooling-layer split) existed to protect a pin overlay from rebuilds;
# the pin overlay went away in `7fe5fb4a3e4c`, so the split has no
# purpose now. Stage 2 carries both jobs.
#
# Build cost on host A: 2 × gcc-illumos compile (~2.5h each at
# coresCap=2) plus stage-1+stage-2 userland rebuilds. About 9h wall
# total — half the old 5-stage cost.
{
  lib,
  localSystem,
  crossSystem,
  config,
  overlays,
  crossOverlays ? [ ],
}:

assert crossSystem == localSystem;
assert localSystem.system == "x86_64-illumos";

let
  bf = (import ./bootstrap-files { }).paths;
  protoStrapCC = import ./strap-tools.nix { };

  # Wrap a bootstrap-files storePath as a derivation-like attrset so
  # cc-wrapper / bintools-wrapper's `lib.getExe'` / `lib.getVersion`
  # calls accept it. Mirrors bootstrap-files-stages.nix's mkBootstrapDrv.
  mkBootstrapDrv =
    {
      pname,
      version,
      outPath,
      mainProgram ? null,
    }:
    {
      type = "derivation";
      outputs = [ "out" ];
      inherit outPath pname version;
      name = "${pname}-${version}";
      out = {
        type = "derivation";
        outputs = [ "out" ];
        outPath = outPath;
      };
    }
    // lib.optionalAttrs (mainProgram != null) {
      meta = { inherit mainProgram; };
    };

  expandResponseParamsDrv = mkBootstrapDrv {
    pname = "expand-response-params";
    version = "0";
    outPath = bf.expand-response-params;
    mainProgram = "expand-response-params";
  };

  coreutilsDrv = mkBootstrapDrv {
    pname = "coreutils";
    version = "9.8";
    outPath = bf.coreutils;
  };

  shell = "${bf.bash}/bin/bash";

  # Stage 0/1 initialPath: bootstrap-files userland. Stage 0's cc and
  # bintools come from proto-strap-cc via the cc-wrapper / bintools-
  # wrapper `nativePrefix` mechanism, NOT from this list.
  bfInitialPath = [
    bf.bash
    bf.coreutils
    bf.findutils
    bf.gnutar
    bf.gnused
    bf.gnugrep
    bf.gawk
    bf.gnumake
    bf.diffutils
    bf.patch
    bf.xz-bin
    bf.gzip
    bf.bzip2-bin
    bf.gnum4
    bf.flex
    bf.bison
    bf.perl
  ];

  # Common preHook fragment: relax purity (illumos host tools at
  # /lib/64), isolate pkg-config from any /opt/local on the host.
  prehookCommon = ''
    export NIX_ENFORCE_PURITY=
    export NIX_ENFORCE_NO_NATIVE="''${NIX_ENFORCE_NO_NATIVE-1}"
    export PKG_CONFIG_LIBDIR=""
  '';

  # patchelf shrink-rpath fixupOutputHook for stages 0/1. Stage 2 uses
  # prevStage.patchelf directly (a stage-1-built nixpkgs patchelf).
  patchelfPin = import ./patchelf-pin.nix {
    patchelfStorePath = bf.patchelf;
  };

  # Builds a stdenv with the supplied cc, fetchurl, and initialPath.
  # auto-rpath-hook is universal across stages.
  makeStdenv =
    {
      cc,
      fetchurl,
      extraInitialPath ? [ ],
      extraNativeBuildInputs ? [ ],
      extraPreHook ? "",
      overrides ? (self: super: { }),
    }:
    import ../generic {
      name = "illumos-from-source-stdenv";
      buildPlatform = localSystem;
      hostPlatform = localSystem;
      targetPlatform = localSystem;

      preHook = prehookCommon + extraPreHook;
      extraNativeBuildInputs = extraNativeBuildInputs ++ [
        ./auto-rpath-hook.sh
      ];

      initialPath = extraInitialPath ++ bfInitialPath;
      fetchurlBoot = fetchurl;
      inherit
        shell
        cc
        overrides
        config
        ;
    };

in
[
  # Stage 0 (raw): cc + bintools wrappers around proto-strap-cc.
  # Userland from bootstrap-files via initialPath.
  (
    { }:
    rec {
      __raw = true;

      stdenv = makeStdenv {
        cc = null;
        fetchurl = null;
        extraNativeBuildInputs = [ patchelfPin ];
      };
      stdenvNoCC = stdenv;

      # cc-wrapper / bintools-wrapper want a "real" cc derivation (with
      # outPath, pname/name, $out/bin/*, $out/lib/*) so that downstream
      # `pkgs.gcc-illumos = import gcc-illumos { host.binPath =
      # "${stdenv.cc.cc}/bin"; ... }` and friends resolve. protoStrapCC
      # is exactly that: a flat-layout view of proto-strap. nativeTools
      # =false → cc-wrapper expects ${cc}/bin/*, not ${nativePrefix}/bin
      # /*. Same pattern as bootstrap-files-stages.nix.
      bintools = import ../../build-support/bintools-wrapper {
        name = "bintools-illumos-stage0";
        inherit lib stdenvNoCC;
        bintools = protoStrapCC;
        libc = null;
        nativeTools = false;
        nativeLibc = true;
        nativePrefix = "";
        runtimeShell = shell;
        expand-response-params = expandResponseParamsDrv;
        coreutils = coreutilsDrv;
        gnugrep = bf.gnugrep;
      };

      cc = import ../../build-support/cc-wrapper {
        name = "cc-illumos-stage0";
        inherit lib stdenvNoCC;
        cc = protoStrapCC;
        inherit bintools;
        libc = null;
        nativeTools = false;
        nativeLibc = true;
        nativePrefix = "";
        runtimeShell = shell;
        expand-response-params = expandResponseParamsDrv;
        coreutils = coreutilsDrv;
        gnugrep = bf.gnugrep;
        isGNU = true;
      };

      fetchurl = import ../../build-support/fetchurl {
        inherit lib stdenvNoCC;
        curl = bf.curl.bin;
        inherit (config) hashedMirrors rewriteURL;
      };
    }
  )

  # Stage 1: allPackages atop stage 0. gcc-illumos rebuilds here with
  # `--enable-bootstrap`; its output is clean of proto-strap.
  (prevStage: {
    inherit config overlays;
    stdenv =
      makeStdenv {
        inherit (prevStage) cc fetchurl;
        extraNativeBuildInputs = [ patchelfPin ];
        overrides = self: super: { inherit (prevStage) fetchurl; };
      }
      // {
        inherit (prevStage) fetchurl;
      };
  })

  # Stage 2 (final): drop proto-strap. Rewrap cc + bintools against
  # stage-1's freshly-built `gcc-illumos` + `binutils-unwrapped`.
  # initialPath uses stage-1's userland (no more bf.* references at
  # the chain level — those still appear via build inputs of stage-1
  # outputs, but stage-2 outputs reference only stage-1 store paths).
  # Tooling-layer hooks attach here.
  (prevStage: {
    inherit config overlays;
    stdenv =
      let
        cleanBintools = prevStage.wrapBintoolsWith {
          bintools = prevStage.binutils-unwrapped;
          libc = null;
          nativeTools = false;
          nativeLibc = true;
          nativePrefix = "";
        };
        cleanCC = prevStage.wrapCCWith {
          cc = prevStage.gcc-illumos;
          bintools = cleanBintools;
          libc = null;
          nativeTools = false;
          nativeLibc = true;
          nativePrefix = "";
          isGNU = true;
        };

        cleanPath = with prevStage; [
          bash
          coreutils
          findutils
          gnutar
          gnused
          gnugrep
          gawk
          gnumake
          diffutils
          patch
          xz
          gzip
          bzip2
        ];
      in
      (import ../generic {
        name = "illumos-from-source-stage2-stdenv";
        buildPlatform = localSystem;
        hostPlatform = localSystem;
        targetPlatform = localSystem;

        # /usr/bin appended for illumos system utilities (isainfo,
        # print, uname, …) that no nix-built package provides. Host-
        # system absolute paths, no nix-store refs.
        preHook = prehookCommon + ''
          export PATH="$PATH:/usr/bin:/usr/sbin"
        '';

        extraNativeBuildInputs = [
          prevStage.patchelf
          ./auto-rpath-hook.sh
          ./strip-illumos-libtool-flags-hook.sh
        ];

        initialPath = cleanPath;
        fetchurlBoot = prevStage.fetchurl;
        shell = "${prevStage.bashNonInteractive}/bin/bash";
        cc = cleanCC;
        inherit config;
        overrides = self: super: { inherit (prevStage) fetchurl; };
      })
      // {
        inherit (prevStage) fetchurl;
      };
  })
]
