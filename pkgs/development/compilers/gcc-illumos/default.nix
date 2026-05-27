# gcc-illumos: GCC built per the SmartOS / OmniOS illumos recipe.
#
# Parameterized over GCC version and host compiler. Two version data
# files ship in versions/ ; default is GCC 14 (versions/14.nix).
#
# Recipe (per /workspace/smartos-live/projects/illumos-extra/gcc{10,14}/):
# - source from github.com/illumos/gcc, illumos community fork
# - mpfr/gmp/mpc unpacked into the GCC source tree as in-tree deps
# - one ld-flags patch (adapted OmniOS 1000-ld-flags.patch) rewriting
#   LINK_ARCH64_SPEC_BASE so the resulting xgcc emits $out/lib/amd64
#   for runpath / library search
#
# Build mode is --disable-bootstrap (single stage). The pkgsrc
# /--enable-bootstrap combo wedged the host's memory subsystem during
# stage-3 link bursts on a 32 GB box; one stage is enough when we
# start from a clean host compiler.
#
# Cleanliness contract:
# - Output `xgcc`'s OWN RUNPATH inherits the host compiler's specs.
#   For proto.strap that means /usr/gcc/10/lib/amd64 ends up alongside
#   $out/lib/amd64 in the driver / cc1plus RUNPATHs. The builder passes
#   LDFLAGS=-Wl,-R$out/lib/amd64 so resulting binaries find their libs
#   in $out first. Cosmetic cleanup deferred.
# - Output BINARIES THAT xgcc COMPILES use our patched specs and
#   naturally emit $out/lib/amd64 — no cleanup needed downstream.
#
# Usage examples:
#
#   # Default: gcc-14, host = proto-strap.
#   nix-build -E '(import ./pkgs/development/compilers/gcc-illumos) {}'
#
#   # GCC 10 against proto-strap.
#   nix-build -E '(import ./pkgs/development/compilers/gcc-illumos) {
#     version = import ./pkgs/development/compilers/gcc-illumos/versions/10.nix;
#   }'
#
#   # GCC 10 against an already-built gcc-illumos-14 (no proto-strap).
#   # gcc-illumos doesn't ship gas; supply it separately.
#   nix-build -E '
#     let
#       gcc14 = import ./pkgs/development/compilers/gcc-illumos { };
#       proto = import ./pkgs/development/compilers/proto-strap { };
#     in import ./pkgs/development/compilers/gcc-illumos {
#       version = import ./pkgs/development/compilers/gcc-illumos/versions/10.nix;
#       host = {
#         binPath = "${gcc14}/bin";
#         gasPath = "${proto}/usr/gnu/bin/gas";
#       };
#     }'
#
{
  # Version data: gccVersion, gccHash, mpfrVersion, mpfrHash, ...,
  # ldFlagsPatch (see versions/*.nix).
  version ? import ./versions/14.nix,

  # Host compiler description:
  #   binPath = "..."  PATH prefix prepended to extraHostPath; must
  #                    contain gcc, g++, cpp (and ideally cc/ld via
  #                    gcc's own driver behavior).
  #   gasPath = "..."  absolute path to the GNU assembler. Passed to
  #                    configure as --with-as= and baked into the new
  #                    gcc-illumos compiler's specs.
  # Defaults derive both paths from a fresh proto-strap import.
  host ? let p = import ../proto-strap { }; in {
    binPath = "${p}/usr/gcc/10/bin:${p}/usr/gnu/bin";
    gasPath = "${p}/usr/gnu/bin/gas";
  },

  # Tools NOT generally in the host compiler: make, gawk, patch, flex,
  # bison. illumos /usr/bin covers bash/sed/awk/tar/m4; the rest still
  # come from pkgsrc (or wherever — override if you've staged them
  # somewhere else).
  extraHostPath ? "/opt/local/bin:/usr/bin:/usr/gnu/bin:/usr/sfw/bin",

  # Cap on `make -j`. 0 (default) = no cap, use NIX_BUILD_CORES verbatim.
  # Set positive (e.g. 6) on memory-constrained hosts to clamp.
  coresCap ? 0,

  system ? "x86_64-illumos",
}:

let
  fetchurl = import <nix/fetchurl.nix>;

  inherit (version)
    gccVersion gccHash
    mpfrVersion mpfrHash
    gmpVersion gmpHash
    mpcVersion mpcHash
    ldFlagsPatch
    ;

  src = fetchurl {
    url = "https://github.com/illumos/gcc/archive/refs/tags/gcc-${gccVersion}.tar.gz";
    sha256 = gccHash;
    name = "gcc-${gccVersion}.tar.gz";
  };

  mpfrSrc = fetchurl {
    url = "https://ftp.gnu.org/gnu/mpfr/mpfr-${mpfrVersion}.tar.bz2";
    sha256 = mpfrHash;
    name = "mpfr-${mpfrVersion}.tar.bz2";
  };

  gmpSrc = fetchurl {
    url = "https://ftp.gnu.org/gnu/gmp/gmp-${gmpVersion}.tar.bz2";
    sha256 = gmpHash;
    name = "gmp-${gmpVersion}.tar.bz2";
  };

  mpcSrc = fetchurl {
    url = "https://ftp.gnu.org/gnu/mpc/mpc-${mpcVersion}.tar.gz";
    sha256 = mpcHash;
    name = "mpc-${mpcVersion}.tar.gz";
  };

  # Final PATH: host compiler tools first (so they win over anything
  # else), then the extras for make/patch/etc.
  hostPath = "${host.binPath}:${extraHostPath}";

in
derivation {
  name = "gcc-illumos-${gccVersion}";
  inherit system src mpfrSrc gmpSrc mpcSrc hostPath;

  asPath = host.gasPath;
  coresCap = toString coresCap;
  mpfrVer = "mpfr-${mpfrVersion}";
  gmpVer = "gmp-${gmpVersion}";
  mpcVer = "mpc-${mpcVersion}";
  version = gccVersion;

  builder = "/usr/bin/bash";
  args = [ ./builder.sh ];

  patchFile = ldFlagsPatch;
}
