# Stdenv for x86_64-illumos. 5-stage chain.
#
# Stage 0 wraps the strap-tools tree (gcc-illumos + binutils-illumos
# + host /usr/bin + /opt/local shell utilities) with cc-wrapper and
# bintools-wrapper in nativeTools mode. This is the "first real
# stdenv" — it can evaluate stdenv.mkDerivation; its bootstrap inputs
# are impure (symlinks into /usr/bin and /opt/local for the shell
# utility tools only).
#
# Stage 1 builds the full package set on top of stage 0. Outputs are
# nix-built but the stdenv's initialPath still points at strap-tools,
# so the closure of anything built here transitively references
# /opt/local symlinks.
#
# Stage 2 (clean userland) drops strap-tools entirely. cc and bintools
# are rewrapped with nativeTools=false against stage-1-built bash /
# coreutils / gnugrep / binutils-unwrapped / patchelf. The cc itself
# is still the scrubbed gcc-illumos pin (proto-strap byte refs
# neutralized post-hoc). initialPath is a list of stage-1-built GNU
# userland paths.
#
# Stage 3 (fully clean) is structurally identical to stage 2 but its
# prevStage is allPackages built by stage 2 — so the cc is a fresh
# gcc-illumos rebuilt under stage 2's clean stdenv (no scrub needed),
# and the userland is rebuilt by the same. Build-time .drv graph at
# this stage has zero strap-tools / proto-strap provenance. This is
# the layer that populates zone images and a future bootstrap tarball.
#
# Stage 4 (illumos tooling layer) wraps stage 3 with two host-env
# workarounds: /usr/bin on PATH (for isainfo/print/uname/…) and a
# preBuild hook that strips GNU-ld-only symbol-filtering flags from
# Makefile* (Sun ld doesn't accept them; libtool generates them
# anyway). With stage 3 pinned via stage3-pin-overlay.nix, only stage
# 4 and downstream pkgs.* rebuild when this layer's tooling changes —
# the long-tail gcc-illumos compile stays put.
#
# strap-tools sources its binutils from binutils-illumos (a clean,
# Phase-4-built /opt/local-free output) rather than proto-strap's
# pre-baked binaries. proto-strap is still the host for gcc-illumos's
# initial compile but doesn't appear in strap-tools' bin/ tree.
#
# See SMARTOS_RECIPE_ROADMAP.md Phase 4 (steps 11-13).
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
  strapTools = import ./strap-tools.nix { };

  # Thin derivation exposing bin/patchelf + a setup-hook that registers
  # patchELF as a fixupOutputHook. Built once via the Phase-4 patchelf
  # derivation, then pinned via builtins.storePath so we can plumb it
  # in without circular deps. See patchelf-pin.nix.
  patchelfPin = import ./patchelf-pin.nix { };

  shell = "${strapTools}/bin/bash";

  # PATH for stage 0: just the strap-tools tree. We don't add /usr/bin or
  # /opt/local directly — every host tool we want is symlinked into
  # strap-tools/bin already, so this keeps the eval impurity contained
  # to one input.
  path = [ strapTools ];

  # Shared across all stages: native-libc relaxation and pkg-config
  # isolation from /opt/local.
  # NOTE: keep this hook free of the literal string "/opt/local". The
  # body of `prehookCommon` is embedded verbatim into the stdenv setup
  # script; anything written here ends up in the runtime closure where
  # `audit.nix` flags it as a forbidden host-path reference (even from
  # a comment). The pkg-config isolation rationale belongs in this
  # file's prose, not in shell comments shipped via the stdenv.
  prehookCommon = ''
    export NIX_ENFORCE_PURITY=
    export NIX_ENFORCE_NO_NATIVE="''${NIX_ENFORCE_NO_NATIVE-1}"
    export PKG_CONFIG_LIBDIR=""
  '';

  # Stages 0/1 only: strap-tools-specific shimming.
  #   - MAKE=gmake + alias make=gmake: strap-tools symlinks gmake from
  #     /opt/local/bin (illumos /usr/bin/make is dmake, not GNU). Stage 2
  #     uses nixpkgs gnumake which exposes the binary as `make`, so the
  #     alias would break it (calls gmake which doesn't exist).
  #   - STRIP=strip / AR=ar / ... explicit exports: in nativeTools=true
  #     mode (stage 0's cc-wrapper) bintools-wrapper's setup-hook leaves
  #     these unset because _PATH is empty. Stage 2 uses nativeTools=false
  #     where bintools-wrapper auto-detects properly.
  prehookStrap = ''
    export MAKE=gmake
    shopt -s expand_aliases
    alias make=gmake

    export STRIP=strip
    export AR=ar
    export AS=as
    export LD=ld
    export NM=nm
    export OBJCOPY=objcopy
    export OBJDUMP=objdump
    export RANLIB=ranlib
    export READELF=readelf
    export SIZE=size
    export STRINGS=strings
  '';

  prehookBase = prehookCommon + prehookStrap;

  makeStdenv =
    {
      cc,
      fetchurl,
      extraPath ? [ ],
      overrides ? (self: super: { }),
      extraNativeBuildInputs ? [ ],
    }:
    import ../generic {
      buildPlatform = localSystem;
      hostPlatform = localSystem;
      targetPlatform = localSystem;

      preHook = prehookBase;
      extraNativeBuildInputs =
        extraNativeBuildInputs
        ++ lib.optional (patchelfPin != null) patchelfPin
        ++ [ ./auto-rpath-hook.sh ];

      initialPath = extraPath ++ path;

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
  # Stage 0 (raw): the cc and bintools wrappers, plus a minimal stdenv
  # that knows about them. Built directly against strap-tools.
  (
    { }:
    rec {
      __raw = true;

      stdenv = makeStdenv {
        cc = null;
        fetchurl = null;
      };
      stdenvNoCC = stdenv;

      bintoolsRaw = import ../../build-support/bintools-wrapper {
        name = "bintools-illumos-strap";
        inherit lib stdenvNoCC;
        nativePrefix = "${strapTools}";
        nativeTools = true;
        nativeLibc = true;
        runtimeShell = shell;
        expand-response-params = "";
      };

      ccRaw = import ../../build-support/cc-wrapper {
        name = "cc-illumos-strap";
        nativePrefix = "${strapTools}";
        nativeTools = true;
        nativeLibc = true;
        runtimeShell = shell;
        expand-response-params = "";
        inherit lib stdenvNoCC;
        bintools = bintoolsRaw;
      };

      # Lie about nativeTools to downstream wrapCCWith / wrapBintoolsWith
      # calls — those inherit stdenv.cc.nativeTools and hit the
      # `nativeTools -> !propagateDoc && nativePrefix != ""` assertion
      # whenever they re-wrap a real (non-null) cc whose man pages
      # exist (e.g. nixpkgs' generic gcc-all.nix used by nix's test
      # deps). Our actual stage-0 cc-wrapper IS nativeTools=true
      # internally — this is purely a cascade workaround.
      bintools = bintoolsRaw // { nativeTools = false; };
      cc = ccRaw // {
        nativeTools = false;
        bintools = bintools;
      };

      fetchurl = import ../../build-support/fetchurl {
        inherit lib stdenvNoCC;
        # Curl from /usr/bin if present; otherwise nix will fall back
        # to its builtin fetcher.
        curl = null;
        inherit (config) hashedMirrors rewriteURL;
      };
    }
  )

  # Stage 1: first real stdenv built from stage-0. At this point we can
  # evaluate stdenv.mkDerivation for downstream packages. Outputs are
  # nix-built but the stdenv still references strap-tools (and via it
  # /opt/local) — stage 2 cleans that up.
  (prevStage: {
    inherit config overlays;
    stdenv =
      makeStdenv {
        inherit (prevStage) cc fetchurl;
        overrides = self: super: { inherit (prevStage) fetchurl; };
      }
      // {
        inherit (prevStage) fetchurl;
      };
  })

  # Stage 2 (clean final): drop strap-tools; rewrap cc + bintools
  # nativeTools=false against stage-1's nix-built shell / coreutils /
  # gnugrep / binutils-unwrapped / patchelf. The `cc` arg to
  # wrapCCWith fakes a multi-output gcc-illumos: `${cc}` resolves to
  # the scrubbed driver (no proto-strap refs), `getLib cc` resolves
  # to the original gcc-illumos.lib (libgcc_s + libstdc++, clean).
  (prevStage: {
    inherit config overlays;
    stdenv =
      let
        gccIllumos = import ../../development/compilers/gcc-illumos { };
        pins = import ./pins.nix;
        gccIllumosScrub = pins.gccIllumosScrub;
        # Attribute trick: override outPath so `getBin cc` / `${cc}`
        # resolve to the scrubbed driver, while inherited `.lib` keeps
        # pointing at the original (clean) gcc-illumos.lib output for
        # cc_solib / libgcc_s discovery.
        gccIllumosClean = gccIllumos // {
          outPath = "${gccIllumosScrub}";
        };

        cleanBintools = prevStage.wrapBintoolsWith {
          bintools = prevStage.binutils-unwrapped;
          libc = null;
          nativeTools = false;
          nativeLibc = true;
          nativePrefix = "";
        };
        cleanCC = prevStage.wrapCCWith {
          cc = gccIllumosClean;
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
        buildPlatform = localSystem;
        hostPlatform = localSystem;
        targetPlatform = localSystem;

        # Clean prehook: no `alias make=gmake` (stage 2's initialPath
        # has nixpkgs gnumake, which provides `make`, not `gmake`),
        # no STRIP=strip exports (bintools-wrapper nativeTools=false
        # auto-detects them).
        preHook = prehookCommon;

        # Nixpkgs patchelf already ships the same fixupOutputHook
        # registration that patchelf-pin reproduces, so we use it
        # directly here — no pin/wrapper needed at this stage.
        extraNativeBuildInputs = [
          prevStage.patchelf
          ./auto-rpath-hook.sh
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

  # Stage 3 (fully clean): same shape as stage 2, but prevStage is
  # stage-2-built allPackages. cc is prevStage.gcc-illumos — a fresh
  # gcc-illumos compiled by stage 2's stdenv using the scrubbed pin
  # as host. Its output has no proto-strap refs; the scrub trick is
  # no longer needed. binutils-unwrapped, bash, coreutils, patchelf
  # likewise come straight from prevStage and were built by stage 2.
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
        buildPlatform = localSystem;
        hostPlatform = localSystem;
        targetPlatform = localSystem;

        preHook = prehookCommon;

        extraNativeBuildInputs = [
          prevStage.patchelf
          ./auto-rpath-hook.sh
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

  # Stage 4 (tooling layer): stage 3 stdenv plus systemic workarounds
  # for illumos host environment. Lives above stage 3 so the pin
  # overlay (stage3-pin-overlay.nix) keeps the heavy chain — bash,
  # coreutils, gcc-illumos, binutils — frozen while we iterate on
  # what tooling downstream package builds need.
  #
  # What it adds vs stage 3:
  #   1. /usr/bin on PATH so configure scripts find illumos system
  #      utilities (isainfo, print, uname, …) without per-package
  #      absolute-path patches.
  #   2. strip-illumos-libtool-flags-hook.sh: a preBuild hook that
  #      removes GNU-ld-only symbol-filtering flags from Makefile*
  #      (-export-symbols, --version-script, -retain-symbols-file).
  #      Sun ld can't parse them; libtool generates them anyway when
  #      a project uses -export-symbols-* in libtool LDFLAGS.
  #
  # Stage 4 reuses everything else from stage 3 — same cc (clean
  # gcc-illumos via prevStage), same bintools, same userland. Building
  # stage 4 stdenv itself is cheap (just a wrap-cc / wrap-bintools
  # cycle); the cost is that every downstream package now has a new
  # drv hash that includes the strip hook + extended PATH.
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
        buildPlatform = localSystem;
        hostPlatform = localSystem;
        targetPlatform = localSystem;

        preHook = prehookCommon + ''
          # Append illumos system utilities. These are host-system
          # absolute paths (no nix-store references), so they don't
          # affect closure cleanliness.
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
