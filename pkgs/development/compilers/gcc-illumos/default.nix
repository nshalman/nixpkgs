# gcc-illumos: GCC built per the SmartOS / OmniOS illumos recipe.
#
# Source:  https://github.com/illumos/gcc, tagged gcc-14.2.0-il-1
# Helper libs (mpfr, gmp, mpc) are unpacked into the source tree per the
# SmartOS pattern; GCC's top-level configure picks them up automatically.
# Single patch (1000-ld-flags.patch, adapted from OmniOS) rewrites the
# LINK_ARCH64_SPEC_BASE so the system linker is told to use $out/lib/amd64
# for runpath / library search instead of the OmniOS /usr/gcc/<MAJOR>/lib
# convention.
#
# This is intentionally a *standalone* derivation that does not depend on
# the nixpkgs stdenv chain. It uses the host's pkgsrc compiler and
# illumos system tools (/usr/bin/ld, /usr/gnu/bin/gas, etc.) directly,
# which matches Phase 1 of SMARTOS_RECIPE_ROADMAP.md ("Builds standalone
# — no integration with stdenv yet"). Phase 2 will build a lean nixpkgs
# stdenv on top of this compiler.
#
# Usage (smoke test):
#   nix-build -E '(import ./pkgs/development/compilers/gcc-illumos) {}'
#
{
  # Path containing the host bash/gcc/make/sed/awk/tar/patch. Defaults to
  # the conventional illumos + pkgsrc layout.
  hostPath ? "/opt/local/bin:/usr/bin:/usr/gnu/bin:/usr/sfw/bin",
  # Absolute path to the GNU assembler. SmartOS proto.strap installs gas at
  # /usr/gnu/bin/gas; pkgsrc-based systems instead carry it at
  # /opt/local/bin/gas. Override per host if neither default applies.
  asPath ? "/opt/local/bin/gas",
  system ? "x86_64-illumos",
}:

let
  fetchurl = import <nix/fetchurl.nix>;

  gccVersion = "14.2.0-il-1";
  mpfrVer = "mpfr-4.2.1";
  gmpVer = "gmp-6.3.0";
  mpcVer = "mpc-1.3.1";

  # GCC source from the illumos community fork (mirrors github releases).
  # Hash will be filled in after first fetch; for now leave as TOFU and
  # let nix-build report the real digest.
  src = fetchurl {
    url = "https://github.com/illumos/gcc/archive/refs/tags/gcc-${gccVersion}.tar.gz";
    sha256 = "18lfswx45lkizs0ygdhhwp5qswb66jqssihwb9wnx6gpw986mgzq";
    name = "gcc-${gccVersion}.tar.gz";
  };

  mpfrSrc = fetchurl {
    url = "https://ftp.gnu.org/gnu/mpfr/${mpfrVer}.tar.bz2";
    sha256 = "183acv9b1ji6kzawzwcxnahlij2a1i11jfv256f0ir10bdir7pxr";
    name = "${mpfrVer}.tar.bz2";
  };

  gmpSrc = fetchurl {
    url = "https://ftp.gnu.org/gnu/gmp/${gmpVer}.tar.bz2";
    sha256 = "1jr03h6h0yz4w9pwyh7p6ijfk3vcsrc6139c5sp9nq7vghd22a5c";
    name = "${gmpVer}.tar.bz2";
  };

  mpcSrc = fetchurl {
    url = "https://ftp.gnu.org/gnu/mpc/${mpcVer}.tar.gz";
    sha256 = "1f2rqz0hdrrhx4y1i5f8pv6yv08a876k1dqcm9s2p26gyn928r5b";
    name = "${mpcVer}.tar.gz";
  };

in
derivation {
  name = "gcc-illumos-${gccVersion}";
  inherit system src mpfrSrc gmpSrc mpcSrc hostPath asPath;

  inherit mpfrVer gmpVer mpcVer;
  version = gccVersion;

  builder = "/usr/bin/bash";
  args = [ ./builder.sh ];

  patchFile = ./1000-ld-flags.patch;
}
