# Stdenv for x86_64-illumos seeded from bootstrap-files.
#
# 2-stage chain (vs from-source.nix's 5):
#
#   Stage 0 (seed, __raw): the cc and bintools wrappers plus a stdenv
#     that knows about them. Inputs come from the bootstrap-files
#     closure roots (./bootstrap-files/x86_64-illumos-paths.nix) via
#     builtins.storePath. The closure must be loaded into /nix/store
#     before eval — load-illumos-closure.sh does this.
#
#     gcc-illumos's .out and .lib outputs are wrapped in a synthetic
#     derivation-like attrset so cc-wrapper's `getLib cc` etc.
#     resolve correctly. Binutils-unwrapped is passed as a raw store
#     path; bintools-wrapper's accesses (`getBin`, `bintools.isGNU
#     or false`) fall back cleanly on strings.
#
#     The stdenv already carries the tooling-layer setup hooks
#     (auto-rpath, strip-illumos-libtool-flags) and the /usr/bin
#     PATH preHook — from-source.nix splits these into stage 4
#     because stages 0-3 of the from-source chain rebuild the
#     toolchain itself; here there is no toolchain rebuild to
#     protect from those hooks.
#
#   Stage 1 (final): the boot's first non-__raw stage. It triggers
#     booter.allPackages against stage 0's stdenv and propagates
#     fetchurl. The output is pkgs.
#
# The from-source chain's stages 0-3 exist to scrub proto-strap
# pollution out of the chain by repeatedly rebuilding gcc-illumos and
# the userland. The bootstrap-files closure is the canonical post-
# scrub output (built clean by gcc-illumos-bootstrap with GCC's
# --enable-bootstrap; see ../make-bootstrap-tools.nix). Seeding
# directly from it skips the scrub dance.
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

  # cc-wrapper / bintools-wrapper invoke lib.getVersion on their `cc`
  # and `bintools` inputs, which builtin-parseDrvName-rejects raw
  # /nix/store/... strings ("string is not allowed to refer to a
  # store path"). Wrap the closure roots as derivation-like attrsets
  # carrying explicit name + version so `x.version or (parse x.name)`
  # takes the .version branch. Other closure roots that flow only
  # through `getBin` / `getName` accept raw storePaths fine.
  mkBootstrapDrv =
    {
      pname,
      version,
      outPath,
      extraOutputs ? { },
      isGNU ? true,
    }:
    {
      type = "derivation";
      outputs = [ "out" ] ++ lib.attrNames extraOutputs;
      inherit outPath pname version isGNU;
      name = "${pname}-${version}";
      out = {
        type = "derivation";
        outputs = [ "out" ];
        outPath = outPath;
      };
      passthru = {
        isFromBootstrapFiles = true;
      };
    }
    // lib.mapAttrs (
      output: path: {
        type = "derivation";
        outputs = [ output ];
        outPath = path;
      }
    ) extraOutputs;

  gccIllumos = mkBootstrapDrv {
    pname = "gcc-illumos";
    version = "14.2.0";
    outPath = bf.gcc-illumos.out;
    extraOutputs = {
      lib = bf.gcc-illumos.lib;
    };
  };

  binutilsUnwrapped = mkBootstrapDrv {
    pname = "binutils";
    version = "2.44";
    outPath = bf.binutils-unwrapped;
  };

  # coreutils and expand-response-params flow through `lib.getExe'`
  # (cc-wrapper / bintools-wrapper line 974-975 + 454-455) and
  # `lib.getExe` (cc-wrapper line 969), both of which assert
  # isDerivation. Synthesise the same shape as the toolchain drvs.
  coreutilsDrv = mkBootstrapDrv {
    pname = "coreutils";
    version = "9.8";
    outPath = bf.coreutils;
  };

  expandResponseParamsDrv = mkBootstrapDrv {
    pname = "expand-response-params";
    version = "0";
    outPath = bf.expand-response-params;
  }
  // {
    # cc-wrapper calls lib.getExe on this; without meta.mainProgram
    # getExe falls back to lib.getName and warns. The binary name is
    # the package name in this case.
    meta = {
      mainProgram = "expand-response-params";
    };
  };

  shell = "${bf.bash}/bin/bash";

  # PATH for the seed stdenv: the bootstrap-files userland (every
  # closure root that contributes a /bin entry). Plus /usr/bin and
  # /usr/sbin appended via preHook for illumos host utilities
  # (isainfo, print, uname, …) that no nix-built package provides.
  initialPath = [
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
  ];

  preHook = ''
    export NIX_ENFORCE_PURITY=
    export NIX_ENFORCE_NO_NATIVE="''${NIX_ENFORCE_NO_NATIVE-1}"
    export PKG_CONFIG_LIBDIR=""
    # Append illumos system utilities. These are host-system
    # absolute paths (no nix-store references), so they don't
    # affect closure cleanliness.
    export PATH="$PATH:/usr/bin:/usr/sbin"
  '';

  # patchelf-pin wraps the bootstrap-files patchelf binary in a
  # derivation that emits a nix-support/setup-hook registering
  # patchELF as a fixupOutputHook (shrinks DT_RUNPATH on every
  # output's ELFs). Without it, packages with disallowedRequisites
  # guards on bashNonInteractive (e.g. krb5.lib) fail because their
  # RPATH still carries the build-time bash reference. The from-
  # source chain solves this by passing prevStage.patchelf into
  # stage 2+'s extraNativeBuildInputs; the seed chain has no
  # prevStage to draw from, so we route through patchelf-pin.
  patchelfPin = import ./patchelf-pin.nix {
    patchelfStorePath = bf.patchelf;
  };

  # Hooks usually attached at from-source.nix stage 4. The seed
  # stdenv builds everything downstream of the toolchain, so they
  # apply from the start.
  extraNativeBuildInputs = [
    patchelfPin
    ./auto-rpath-hook.sh
    ./strip-illumos-libtool-flags-hook.sh
  ];

  makeStdenv =
    { cc, fetchurl }:
    import ../generic {
      name = "illumos-bootstrap-files-seed-stdenv";
      buildPlatform = localSystem;
      hostPlatform = localSystem;
      targetPlatform = localSystem;

      inherit preHook initialPath shell cc config extraNativeBuildInputs;
      fetchurlBoot = fetchurl;
    };

in
[
  # Stage 0 (seed, __raw): wrap the bootstrap-files cc + binutils
  # with cc-wrapper / bintools-wrapper. Stage 0's stdenv has cc=null
  # because cc-wrapper itself takes stdenvNoCC; mirroring the
  # cc/bintools/stdenv knot that from-source.nix's stage 0 ties.
  (
    { }:
    rec {
      __raw = true;

      stdenv = makeStdenv {
        cc = null;
        fetchurl = null;
      };
      stdenvNoCC = stdenv;

      bintools = import ../../build-support/bintools-wrapper {
        name = "bintools-illumos-seed";
        inherit lib stdenvNoCC;
        bintools = binutilsUnwrapped;
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
        name = "cc-illumos-seed";
        inherit lib stdenvNoCC;
        cc = gccIllumos;
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

      # Use fetchurl/boot.nix — a thin wrapper around the language
      # builtin `<nix/fetchurl.nix>`. The curl-based pkgs.fetchurl
      # would call `curl` from a builder script; passing curl=null
      # leaves the script intact and lets the builder fail at
      # "curl: command not found" on a fresh consumer that hasn't
      # built pkgs.curl yet (host A built only because
      # pkgs.curl-fetched sources were already cached from earlier
      # from-source-chain builds). boot.nix needs no curl.
      #
      # Stage 1 (below) propagates this as pkgs.fetchurl via the
      # `overrides` overlay, so downstream `src = fetchurl {...}`
      # calls in nixpkgs land on the same builtin-backed fetcher.
      # Tradeoff: pkgs.fetchurl loses the curl-only features
      # (mirror://, postFetch, downloadToTemp). Acceptable for the
      # seed chain's scope; a follow-up stage can rebuild a full
      # curl-based pkgs.fetchurl once pkgs.curl is in /nix/store.
      fetchurl = import ../../build-support/fetchurl/boot.nix {
        inherit (localSystem) system;
        inherit (config) rewriteURL;
      };
    }
  )

  # Stage 1 (final): allPackages atop a fresh stdenv that picks up
  # stage 0's cc + fetchurl. The seed stdenv at stage 0 has cc=null
  # (the cc/bintools/stdenv knot); stage 1 ties the knot by passing
  # the wrapped cc in. `overrides = self: super: { fetchurl; }`
  # propagates the boot fetchurl into the package set so users get
  # the same fetchurl their stdenv was built with.
  (prevStage: {
    inherit config overlays;
    stdenv =
      makeStdenv {
        inherit (prevStage) cc fetchurl;
      }
      // {
        inherit (prevStage) fetchurl;
        overrides = self: super: { inherit (prevStage) fetchurl; };
      };
  })
]
