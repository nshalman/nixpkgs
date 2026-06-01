{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
}:

stdenv.mkDerivation rec {
  pname = "libcpuid";
  version = "0.8.1";

  src = fetchFromGitHub {
    owner = "anrieff";
    repo = "libcpuid";
    rev = "v${version}";
    hash = "sha256-+/TTlGk1ePPTHrSTSZmPHT2h3gKs9ouCF4ElvLWHF/g=";
  };

  nativeBuildInputs = [ autoreconfHook ];

  # libtool translates -export-symbols into -Wl,-retain-symbols-file
  # (GNU-ld syntax) even when configure detects Sun ld. gcc-illumos
  # invokes Sun ld via baked-in --with-ld=/usr/bin/ld and errors on
  # the .sym file. Drop the regex / file on illumos; the library will
  # export everything, which is fine for our consumers.
  postPatch = lib.optionalString stdenv.hostPlatform.isIllumos ''
    substituteInPlace libcpuid/Makefile.am \
      --replace-fail "-export-symbols \$(srcdir)/libcpuid.sym" ""
  '';

  meta = {
    homepage = "https://libcpuid.sourceforge.net/";
    description = "Small C library for x86 CPU detection and feature extraction";
    mainProgram = "cpuid_tool";
    changelog = "https://raw.githubusercontent.com/anrieff/libcpuid/master/ChangeLog";
    license = lib.licenses.bsd2;
    maintainers = with lib.maintainers; [
      orivej
    ];
    platforms = lib.platforms.x86;
  };
}
