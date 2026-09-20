# The stdenv for illumos (system x86_64-solaris), bootstrapped from two fetched files in the manner of
# ../freebsd: `unpack`, just enough to unpack, and `bootstrapTools`, a userland and gcc merged into one prefix.
#
# What differs from the other bootstraps is libc. It is never ours: programs run against the libc and runtime
# linker of the system they are started on, and are linked against a pinned, older copy of the illumos libraries
# (the "sysroot") so that they need nothing a system of that age or later lacks. That copy is link-only; it must
# not end up in a RUNPATH, which bintools-wrapper sees to. It is not in the bootstrap files either: the first
# stage makes it from the published sysroot with the bootstrap tools.
{
  lib,
  localSystem,
  crossSystem,
  config,
  overlays,
  crossOverlays ? [ ],

  # { unpack, bootstrapTools }, see ../freebsd/bootstrap-files. None are hosted for this platform yet.
  bootstrapFiles ? throw "pkgs/stdenv/illumos: no bootstrap files are published for ${localSystem.system} yet; pass bootstrapFiles",

  # { callPackage }: { illumos-libc, illumos-ld, gcc-illumos, ... }, the platform's toolchain packages.
  illumosPackages ? throw "pkgs/stdenv/illumos: pass illumosPackages, the illumos toolchain package set",
}:

assert crossSystem == localSystem;

let
  inherit (localSystem) system;

  # Named shortly on purpose: the unpack script replaces the store paths inside binaries by this one, padded to
  # their length, so it must not be longer than any of them.
  bootstrapArchive = derivation {
    inherit system;
    name = "boot";
    builder = "${bootstrapFiles.unpack}/bin/bash";
    args = [ ./unpack-bootstrap-files.sh ];
    LD_LIBRARY_PATH_64 = "${bootstrapFiles.unpack}/lib";
    src = bootstrapFiles.unpack;
    inherit (bootstrapFiles) bootstrapTools;
  };

  # The archive is one prefix holding a userland, perl, bison, curl, binutils and the compiler, with the libraries
  # of all of them in lib/. Nothing may be handed to the stdenv or to a wrapper as "the archive": the wrappers put
  # their tool's bin/ on PATH and the compiler's lib/ on every link line, and a package that finds perl or
  # libncurses that way behaves as it would nowhere else (GNU make runs a test suite it otherwise skips for want
  # of perl; texinfo paired the archive's ncurses with the system's <termcap.h>). So, as in ../freebsd, every tool
  # is a directory of links to its own programs. gcc resolves the link it is started through and so still finds
  # the rest of itself in the archive.
  linkBootstrap =
    {
      name,
      # A `case` pattern over program names; a program that is a link to `coreutils` is matched as "coreutils".
      programs,
      attrs ? { },
    }:
    let
      drv = derivation {
        inherit system name;
        builder = bootstrapShell;
        PATH = "${bootstrapArchive}/bin";
        args = [
          "-c"
          ''
            mkdir -p $out/bin
            for f in ${bootstrapArchive}/bin/*; do
              n=''${f##*/}
              [ "$(readlink "$f")" = coreutils ] && n=coreutils
              case "$n" in
                ${programs}) ln -s "$f" $out/bin/ ;;
              esac
            done
            [ -n "$(ls $out/bin)" ]
          ''
        ];
      };
    in
    # The wrappers ask their inputs for a version, outputs and a main program.
    {
      type = "derivation";
      outputs = [ "out" ];
      inherit (drv) outPath drvPath;
      inherit name;
      pname = name;
      version = "0";
      out = drv;
    }
    // attrs;

  # gcc's runtime libraries, for cc-wrapper to put on the link line.
  bootstrapGccLib = derivation {
    inherit system;
    name = "bootstrap-gcc-lib";
    builder = bootstrapShell;
    PATH = "${bootstrapArchive}/bin";
    args = [
      "-c"
      "mkdir -p $out/lib && ln -s ${bootstrapArchive}/lib/amd64 $out/lib/amd64"
    ];
  };

  bootstrapGcc = linkBootstrap {
    name = "bootstrap-gcc";
    programs = "gcc | g++ | cpp | c++ | gcc-ar | gcc-nm | gcc-ranlib | x86_64-pc-solaris2.11-*";
    attrs = {
      pname = "gcc-illumos";
      version = "14.2.0";
      isGNU = true;
      lib = bootstrapGccLib;
    };
  };

  # GNU binutils except for the link-editor, which is the illumos one.
  bootstrapBintools = linkBootstrap {
    name = "bootstrap-bintools";
    programs = "ar | as | ld | nm | objcopy | objdump | ranlib | readelf | size | strings | strip | addr2line | c++filt | elfedit";
    attrs = {
      pname = "illumos-bintools";
      isGNU = true;
    };
  };

  bootstrapCoreutils = linkBootstrap {
    name = "bootstrap-coreutils";
    programs = "coreutils";
    attrs.pname = "coreutils";
  };

  bootstrapGnugrep = linkBootstrap {
    name = "bootstrap-gnugrep";
    programs = "grep | egrep | fgrep";
  };

  bootstrapCurl = linkBootstrap {
    name = "bootstrap-curl";
    programs = "curl";
  };

  bootstrapExpandResponseParams = linkBootstrap {
    name = "bootstrap-expand-response-params";
    programs = "expand-response-params";
    attrs = {
      pname = "expand-response-params";
      meta.mainProgram = "expand-response-params";
    };
  };

  # What a stdenv has on PATH before a stage has built its own tools.
  bootstrapPath = linkBootstrap {
    name = "bootstrap-tools-path";
    programs = "coreutils | bash | sh | find | xargs | tar | sed | grep | egrep | fgrep | awk | gawk | make | diff | cmp | diff3 | sdiff | patch | xz | unxz | xzcat | gzip | gunzip | zcat | bzip2 | bunzip2 | bzcat | patchelf";
  };

  bootstrapShell = "${bootstrapArchive}/bin/bash";

  commonPreHook = ''
    export NIX_ENFORCE_PURITY="''${NIX_ENFORCE_PURITY-1}"
    export NIX_ENFORCE_NO_NATIVE="''${NIX_ENFORCE_NO_NATIVE-1}"
    # Nix has no sandbox on illumos, so a build runs in /nix/var/nix/builds/nix-PID-RANDOM, under a different name
    # every time, and __FILE__ and debug info carry that name into the output. Elsewhere the sandbox makes the
    # build directory constant; here the compiler has to be told.
    export NIX_CFLAGS_COMPILE+=" -ffile-prefix-map=$NIX_BUILD_TOP=/build"
  '';

  makeStdenv =
    {
      name,
      cc,
      fetchurl,
      initialPath,
      shell ? bootstrapShell,
      extraNativeBuildInputs ? [ ],
      overrides ? (self: super: { }),
    }:
    import ../generic {
      inherit
        name
        config
        shell
        cc
        initialPath
        extraNativeBuildInputs
        overrides
        ;
      buildPlatform = localSystem;
      hostPlatform = localSystem;
      targetPlatform = localSystem;
      preHook = commonPreHook;
      fetchurlBoot = fetchurl;
    };

  # The tools a stdenv is made of, as one stage hands them to the next.
  toolsOf = pkgs: {
    inherit (pkgs)
      bash
      bashNonInteractive
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
      ;
  };

  initialPathOf =
    tools: with tools; [
      bashNonInteractive
      coreutils
      findutils
      gnutar
      gnused
      gnugrep
      gawk
      gnumake
      diffutils
      patch
      xz.bin
      gzip
      bzip2.bin
    ];

  # The toolchain a stage has built, wrapped by that stage: gcc, and GNU binutils with the illumos link-editor in
  # the place of GNU ld.
  wrapToolchain =
    pkgs:
    let
      libc = pkgs.illumos-libc;
      bintools = pkgs.wrapBintoolsWith {
        inherit libc;
        bintools = pkgs.stdenvNoCC.mkDerivation {
          pname = "illumos-bintools";
          inherit (pkgs.binutils-unwrapped) version;
          dontUnpack = true;
          dontFixup = true;
          # Everything but ld is GNU binutils; the wrapper only wraps `strip` for bintools that say so.
          passthru.isGNU = true;
          installPhase = ''
            mkdir -p $out/bin
            for f in ${pkgs.binutils-unwrapped}/bin/*; do
              case "''${f##*/}" in
                ld | ld.*) ;;
                *) ln -s "$f" $out/bin/ ;;
              esac
            done
            ln -s ${pkgs.illumos-ld}/bin/ld $out/bin/ld
          '';
        };
        nativeTools = false;
        nativeLibc = false;
      };
    in
    pkgs.wrapCCWith {
      inherit libc bintools;
      cc = pkgs.gcc-illumos;
      nativeTools = false;
      nativeLibc = false;
      isGNU = true;
    };

  # patchelf comes from the bootstrap tools until a stage has built one; its hook is what shrinks RUNPATHs.
  bootstrapPatchelfHook = ../../development/tools/misc/patchelf/setup-hook.sh;
in
[
  # Stage 0: the bootstrap tools, wrapped. Nothing is built by a compiler here.
  (
    { }:
    rec {
      __raw = true;

      stdenv = makeStdenv {
        name = "bootstrap-stage0-stdenv-illumos";
        cc = null;
        fetchurl = null;
        initialPath = [ bootstrapPath ];
      };
      stdenvNoCC = stdenv;

      fetchurl = import ../../build-support/fetchurl {
        inherit lib stdenvNoCC;
        curl = bootstrapCurl;
        inherit (config) hashedMirrors rewriteURL;
      };

      illumos = illumosPackages {
        callPackage = lib.callPackageWith (
          {
            inherit lib stdenvNoCC fetchurl;
          }
          // illumos
        );
      };
      libc = illumos.illumos-libc;

      bintools = import ../../build-support/bintools-wrapper {
        name = "bootstrap-stage0-bintools-wrapper";
        inherit lib stdenvNoCC libc;
        bintools = bootstrapBintools;
        coreutils = bootstrapCoreutils;
        expand-response-params = bootstrapExpandResponseParams;
        gnugrep = bootstrapGnugrep;
        nativeTools = false;
        nativeLibc = false;
        runtimeShell = bootstrapShell;
      };

      cc = import ../../build-support/cc-wrapper {
        name = "bootstrap-stage0-gcc-wrapper";
        inherit
          lib
          stdenvNoCC
          libc
          bintools
          ;
        cc = bootstrapGcc;
        coreutils = bootstrapCoreutils;
        expand-response-params = bootstrapExpandResponseParams;
        gnugrep = bootstrapGnugrep;
        nativeTools = false;
        nativeLibc = false;
        runtimeShell = bootstrapShell;
        isGNU = true;
      };
    }
  )

  # Stage 1: the package set as built by the bootstrap tools. Wanted from it: the basic tools, for the next two
  # stages to be built with.
  (prevStage: {
    inherit config overlays;
    stdenv =
      makeStdenv {
        name = "bootstrap-stage1-stdenv-illumos";
        inherit (prevStage) cc fetchurl;
        initialPath = [ bootstrapPath ];
        extraNativeBuildInputs = [ bootstrapPatchelfHook ];
        overrides = self: super: {
          inherit (prevStage) fetchurl;
          inherit (prevStage.illumos) illumos-sysroot illumos-libc;
        };
      }
      // {
        inherit (prevStage) fetchurl;
      };
  })

  # Stage 2: stage 1's tools and still the bootstrap compiler. Wanted from it: the toolchain, that is gcc with
  # its runtime libraries, the illumos link-editor and GNU binutils for the rest.
  (
    prevStage:
    let
      tools = toolsOf prevStage;
    in
    {
      inherit config overlays;
      stdenv =
        makeStdenv {
          name = "bootstrap-stage2-stdenv-illumos";
          inherit (prevStage.stdenv) cc;
          inherit (prevStage) fetchurl;
          shell = "${prevStage.bashNonInteractive}/bin/bash";
          initialPath = initialPathOf tools;
          extraNativeBuildInputs = [ prevStage.patchelf ];
          overrides =
            self: super:
            tools
            // {
              inherit (prevStage) fetchurl illumos-sysroot illumos-libc;
            }
            // removeAttrs (illumosPackages { inherit (self) callPackage; }) [
              "illumos-sysroot"
              "illumos-libc"
            ];
        }
        // {
          inherit (prevStage) fetchurl;
        };
    }
  )

  # Stage 3: stage 1's tools and stage 2's toolchain. Stage 2 was compiled by the bootstrap gcc, so whatever in it
  # is C++ or needs libgcc_s (binutils, and with them the gcc that names their `as`) still runs on the archive's
  # libraries, and so do stage 1's gettext and gmp, which the tools link. Wanted from this stage: all of that
  # again, tools and toolchain, this time compiled by a gcc that was built here.
  (prevStage: {
    inherit config overlays;
    stdenv =
      makeStdenv {
        name = "bootstrap-stage3-stdenv-illumos";
        cc = wrapToolchain prevStage;
        inherit (prevStage) fetchurl;
        shell = "${prevStage.bashNonInteractive}/bin/bash";
        initialPath = initialPathOf (toolsOf prevStage);
        extraNativeBuildInputs = [ prevStage.patchelf ];
        overrides =
          self: super:
          {
            inherit (prevStage) fetchurl illumos-sysroot illumos-libc;
          }
          // removeAttrs (illumosPackages { inherit (self) callPackage; }) [
            "illumos-sysroot"
            "illumos-libc"
          ];
      }
      // {
        inherit (prevStage) fetchurl;
      };
  })

  # Stage 4, the final one: made of stage 3 only.
  (
    prevStage:
    let
      tools = toolsOf prevStage;
    in
    {
      inherit config overlays;
      stdenv =
        makeStdenv {
          name = "stdenv-illumos";
          cc = wrapToolchain prevStage;
          inherit (prevStage) fetchurl;
          shell = "${prevStage.bashNonInteractive}/bin/bash";
          initialPath = initialPathOf tools;
          extraNativeBuildInputs = [ prevStage.patchelf ];
          overrides =
            self: super:
            tools
            // {
              inherit (prevStage)
                fetchurl
                illumos-sysroot
                illumos-libc
                illumos-ld
                gcc-illumos
                binutils-unwrapped
                patchelf
                ;
            };
        }
        // {
          inherit (prevStage) fetchurl;
        };
    }
  )
]
