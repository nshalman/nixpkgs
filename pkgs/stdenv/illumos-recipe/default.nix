# Stdenv for x86_64-illumos, modeled on the native stdenv pattern.
#
# Stage 0 wraps the strap-tools tree (gcc-illumos + proto-strap binutils
# + host /usr/bin + /opt/local) with cc-wrapper and bintools-wrapper in
# nativeTools mode. This is the "first real stdenv" — it can be used to
# evaluate stdenv.mkDerivation but its bootstrap inputs are impure
# (symlinks into /usr/bin and /opt/local). Stage 1 rebuilds against
# stage-0 packages, narrowing the closure once we have nix-built tools.
#
# See SMARTOS_RECIPE_ROADMAP.md Phase 2 for the design rationale.
# Phase 4 will replace the strap-tools host symlinks with a nix-built
# bootstrap-tools tarball.
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
      inherit extraNativeBuildInputs;

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

      bintools = import ../../build-support/bintools-wrapper {
        name = "bintools-illumos-strap";
        inherit lib stdenvNoCC;
        nativePrefix = "${strapTools}";
        nativeTools = true;
        nativeLibc = true;
        runtimeShell = shell;
        expand-response-params = "";
      };

      cc = import ../../build-support/cc-wrapper {
        name = "cc-illumos-strap";
        nativePrefix = "${strapTools}";
        nativeTools = true;
        nativeLibc = true;
        runtimeShell = shell;
        expand-response-params = "";
        inherit lib bintools stdenvNoCC;
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
