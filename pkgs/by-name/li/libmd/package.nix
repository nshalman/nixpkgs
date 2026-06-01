{
  lib,
  stdenv,
  fetchurl,
  autoreconfHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "libmd";
  version = "1.1.0";

  src = fetchurl {
    urls = [
      "https://archive.hadrons.org/software/libmd/libmd-${finalAttrs.version}.tar.xz"
      "https://libbsd.freedesktop.org/releases/libmd-${finalAttrs.version}.tar.xz"
    ];
    sha256 = "sha256-G9aqQidTE68xQcfPLluWTosf1IgCXK8vlx9DsAd2szI=";
  };

  enableParallelBuilding = true;

  doCheck = true;

  nativeBuildInputs = [ autoreconfHook ];

  # libmd's HAVE_LINKER_VERSION_SCRIPT=no branch (Sun ld on illumos)
  # uses libtool `-export-symbols libmd.sym`, which libtool translates
  # to GNU-ld `-Wl,-retain-symbols-file -Wl,libmd.sym`. Sun ld errors
  # out. Drop the flag; libmd exports everything, which is fine for
  # our consumers. Same pattern as gettext/jq/libcpuid.
  postPatch = lib.optionalString stdenv.hostPlatform.isIllumos ''
    substituteInPlace src/Makefile.am \
      --replace-fail "-export-symbols libmd.sym" ""
  '';

  meta = {
    homepage = "https://www.hadrons.org/software/libmd/";
    changelog = "https://archive.hadrons.org/software/libmd/libmd-${finalAttrs.version}.announce";
    # Git: https://git.hadrons.org/cgit/libmd.git
    description = "Message Digest functions from BSD systems";
    license = with lib.licenses; [
      bsd3
      bsd2
      isc
      beerware
      publicDomain
    ];
    maintainers = [ ];
    platforms = lib.platforms.unix;
  };
})
