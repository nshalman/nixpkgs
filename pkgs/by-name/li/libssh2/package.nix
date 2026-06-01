{
  lib,
  stdenv,
  fetchurl,
  openssl,
  zlib,
  windows,

  # for passthru.tests
  aria2,
  curl,
  libgit2,
  mc,
  vlc,
}:

stdenv.mkDerivation rec {
  pname = "libssh2";
  version = "1.11.1";

  src = fetchurl {
    url = "https://www.libssh2.org/download/libssh2-${version}.tar.gz";
    hash = "sha256-2ex2y+NNuY7sNTn+LImdJrDIN8s+tGalaw8QnKv2WPc=";
  };

  patches = [
    # https://github.com/libssh2/libssh2/commit/256d04b60d80bf1190e96b0ad1e91b2174d744b1
    ./CVE-2026-7598.patch
  ];

  # this could be accomplished by updateAutotoolsGnuConfigScriptsHook, but that causes infinite recursion
  # necessary for FreeBSD code path in configure
  postPatch = ''
    substituteInPlace ./config.guess --replace-fail /usr/bin/uname uname
  ''
  # libtool turns -export-symbols-regex into GNU-ld
  # -Wl,-retain-symbols-file -Wl,libssh2.exp, but gcc-illumos passes
  # to Sun ld via --with-ld=/usr/bin/ld which rejects the .exp file.
  # Drop the regex; libssh2 exports everything (consumers only
  # reference libssh2_* anyway). Same pattern as gettext/jq/libcpuid/
  # libmd, but libssh2 doesn't use autoreconfHook so we also need to
  # patch the shipped Makefile.in directly.
  + lib.optionalString stdenv.hostPlatform.isIllumos ''
    substituteInPlace src/Makefile.am src/Makefile.in \
      --replace-fail "-export-symbols-regex '^libssh2_.*'" ""
  '';

  outputs = [
    "out"
    "dev"
    "devdoc"
  ];

  # illumos: libtool's symbol extraction detection fails because it expects
  # underscore-prefixed symbols (BSD-style) but illumos nm doesn't use them.
  # Set the variable to a working sed command for illumos nm output format.
  # Also add -z nodefs to allow symbols from implicit dependencies.
  preConfigure = lib.optionalString stdenv.hostPlatform.isIllumos ''
    export lt_cv_sys_global_symbol_pipe="sed -n -e 's/^.* [BDRT] \([_A-Za-z][_A-Za-z0-9]*\)$/T \1 \1/p'"
    export LDFLAGS="$LDFLAGS -Wl,-z,nodefs"
  '';

  propagatedBuildInputs = [ openssl ]; # see Libs: in libssh2.pc
  buildInputs = [ zlib ] ++ lib.optional stdenv.hostPlatform.isMinGW windows.mingw_w64;

  passthru.tests = {
    inherit
      aria2
      libgit2
      mc
      vlc
      ;
    curl = (curl.override { scpSupport = true; }).tests.withCheck;
  };

  meta = {
    description = "Client-side C library implementing the SSH2 protocol";
    homepage = "https://www.libssh2.org";
    platforms = lib.platforms.all;
    license = with lib.licenses; [ bsd3 ];
    maintainers = with lib.maintainers; [ SuperSandro2000 ];
  };
}
