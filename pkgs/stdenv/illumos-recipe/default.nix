# Stdenv for x86_64-illumos. 2-stage chain.
#
# Stage 0 wraps the strap-tools tree (gcc-illumos + binutils-illumos
# + host /usr/bin + /opt/local shell utilities) with cc-wrapper and
# bintools-wrapper in nativeTools mode. This is the "first real
# stdenv" — it can evaluate stdenv.mkDerivation; its bootstrap inputs
# are impure (symlinks into /usr/bin and /opt/local for the shell
# utility tools only). Stage 1 builds the full package set on top.
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

  prehookBase = ''
    # Native libc; don't enforce nix-store purity at the linker.
    export NIX_ENFORCE_PURITY=
    export NIX_ENFORCE_NO_NATIVE="''${NIX_ENFORCE_NO_NATIVE-1}"

    # Stop pkg-config from auto-discovering /opt/local/lib/pkgconfig/*.pc
    # and dragging /opt/local libs (openssl, ncurses, ...) into the
    # store-path closure. Mirrors the prehookIsolated stanza from the
    # old multi-stage illumos stdenv. See bd issue nix-blc.
    export PKG_CONFIG_LIBDIR=""

    # illumos has no /usr/bin/make; route the stdenv default through gmake.
    export MAKE=gmake
    shopt -s expand_aliases
    alias make=gmake

    # bintools-wrapper's setup-hook.sh tries to auto-detect strip/ar/nm/...
    # via `PATH=$_PATH type -p <tool>`. In nativeTools=true mode with
    # null bintools_bin/coreutils_bin, _PATH stays empty and the detection
    # fails silently, leaving STRIP unset and the strip fixup-hook a no-op.
    # Export them explicitly so binaries get stripped (and other tool
    # vars match standard nixpkgs conventions).
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
      extraNativeBuildInputs = extraNativeBuildInputs ++ [
        patchelfPin
        ./auto-rpath-hook.sh
      ];

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
  # evaluate stdenv.mkDerivation for downstream packages.
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
]
