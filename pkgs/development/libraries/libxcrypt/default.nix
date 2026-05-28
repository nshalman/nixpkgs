{
  lib,
  stdenv,
  fetchurl,
  perl,
  # Update the enabled crypt scheme ids in passthru when the enabled hashes change
  enableHashes ? "strong",
  nixosTests,
  runCommand,
  python3,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "libxcrypt";
  version = "4.5.2";

  src = fetchurl {
    url = "https://github.com/besser82/libxcrypt/releases/download/v${finalAttrs.version}/libxcrypt-${finalAttrs.version}.tar.xz";
    hash = "sha256-cVE6McAaQovM1TZ6Mv2V8RXW2sUPtbYMd51ceUKuwHE=";
  };

  # this could be accomplished by updateAutotoolsGnuConfigScriptsHook, but that causes infinite recursion
  # necessary for FreeBSD code path in configure
  postPatch = ''
    substituteInPlace ./build-aux/m4-autogen/config.guess --replace-fail /usr/bin/uname uname
  '';

  outputs = [
    "out"
    "man"
  ];

  configureFlags = [
    "--enable-hashes=${enableHashes}"
    "--enable-obsolete-api=glibc"
    "--disable-failure-tokens"
    # required for musl, android, march=native
    "--disable-werror"
  ]
  # illumos ld accepts a different version-script dialect than GNU ld;
  # libxcrypt's symvers script uses GNU syntax that produces an unusable
  # mapfile here. Symbol versioning is a soname-compatibility nicety,
  # not a correctness requirement, so just turn it off on illumos.
  ++ lib.optionals stdenv.hostPlatform.isIllumos [
    "--disable-symvers"
    # illumos exposes memset_s() only behind __STDC_WANT_LIB_EXT1__, but
    # configure detects it via the symbol existing in libc and sets
    # HAVE_MEMSET_S=1. crypt-port.h then picks memset_s over
    # explicit_bzero (which illumos *does* expose unconditionally) and
    # the build fails on the implicit declaration. Force-disable the
    # memset_s detection so the explicit_bzero branch wins.
    "ac_cv_func_memset_s=no"
  ];

  makeFlags =
    let
      lld17Plus = stdenv.cc.bintools.isLLVM && lib.versionAtLeast stdenv.cc.bintools.version "17";
    in
    [ ]
    # fixes: can't build x86_64-w64-mingw32 shared library unless -no-undefined is specified
    ++ lib.optionals stdenv.hostPlatform.isWindows [ "LDFLAGS+=-no-undefined" ]

    # lld 17 sets `--no-undefined-version` by default and `libxcrypt`'s
    # version script unconditionally lists legacy compatibility symbols, even
    # when not exported: https://github.com/besser82/libxcrypt/issues/181
    ++ lib.optionals lld17Plus [ "LDFLAGS+=-Wl,--undefined-version" ];

  nativeBuildInputs = [
    perl
  ];

  enableParallelBuilding = true;

  # libxcrypt tests assert behavior of crypt(3) for hashes that aren't
  # all available on illumos. Skip until per-hash gating is sorted out.
  doCheck = !stdenv.hostPlatform.isIllumos;

  passthru = {
    tests = {
      inherit (nixosTests) login shadow;

      passthruMatches = runCommand "libxcrypt-test-passthru-matches" { } ''
        ${python3.interpreter} "${./check_passthru_matches.py}" ${
          lib.escapeShellArgs (
            [
              finalAttrs.src
              enableHashes
              "--"
            ]
            ++ finalAttrs.passthru.enabledCryptSchemeIds
          )
        }
        touch "$out"
      '';
    };
    enabledCryptSchemeIds = [
      # https://github.com/besser82/libxcrypt/blob/v4.5.0/lib/hashes.conf
      "y" # yescrypt
      "gy" # gost_yescrypt
      "sm3y" # sm3_yescrypt
      "7" # scrypt
      "2b" # bcrypt
      "2y" # bcrypt_y
      "2a" # bcrypt_a
      "6" # sha512crypt
    ];
  };

  meta = {
    changelog = "https://github.com/besser82/libxcrypt/blob/v${finalAttrs.version}/NEWS";
    description = "Extended crypt library for descrypt, md5crypt, bcrypt, and others";
    homepage = "https://github.com/besser82/libxcrypt/";
    platforms = lib.platforms.all;
    maintainers = with lib.maintainers; [
      dottedmag
      hexa
    ];
    license = lib.licenses.lgpl21Plus;
  };
})
