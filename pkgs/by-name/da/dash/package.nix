{
  lib,
  stdenv,
  buildPackages,
  pkg-config,
  fetchurl,
  libedit,
  runCommand,
  dash,

  # Reverse dependency smoke tests
  tests,
  patchRcPathPosix,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "dash";
  version = "0.5.13.2";

  src = fetchurl {
    url = "http://gondor.apana.org.au/~herbert/dash/files/dash-${finalAttrs.version}.tar.gz";
    hash = "sha256-5xNoJrHu1s4xk+iv+i9wsbK5Fo3ZH/p9209G6eYgVP4=";
  };

  strictDeps = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isStatic [ pkg-config ];

  depsBuildBuild = [ buildPackages.stdenv.cc ];
  # libedit drops on illumos: histedit.h is unusable without the
  # 64-bit-suffix interfaces (readdir64 / dirent64 / glob64 …) that
  # dash assumes from glibc but illumos's LP64 doesn't provide. Giving
  # up libedit also gives up dash's line editing — fine for /bin/sh
  # scripting use.
  buildInputs = lib.optional (!stdenv.hostPlatform.isIllumos) libedit;

  hardeningDisable = [ "strictflexarrays3" ];

  configureFlags = lib.optional (!stdenv.hostPlatform.isIllumos) "--with-libedit";
  preConfigure =
    lib.optionalString stdenv.hostPlatform.isStatic ''
      export LIBS="$(''${PKG_CONFIG:-pkg-config} --libs --static libedit)"
    ''
    + lib.optionalString stdenv.hostPlatform.isIllumos ''
      # illumos doesn't have d_type in struct dirent — neutralize the
      # optimization in src/expand.c so the file always falls through
      # to the lstat path.
      substituteInPlace src/expand.c \
        --replace-fail 'dp->d_type != DT_DIR && dp->d_type != DT_LNK &&' "" \
        --replace-fail 'dp->d_type != DT_UNKNOWN)' "0)"

      # illumos uses LP64 natively: rename dash's glibc-style 64-bit
      # function/type references to the unsuffixed names that exist on
      # illumos (where they're already 64-bit-wide).
      find src -name '*.c' -o -name '*.h' | xargs sed -i \
        -e 's/readdir64/readdir/g' \
        -e 's/dirent64/dirent/g' \
        -e 's/glob64_t/glob_t/g' \
        -e 's/glob64/glob/g' \
        -e 's/globfree64/globfree/g' \
        -e 's/open64/open/g' \
        -e 's/stat64/stat/g' \
        -e 's/fstat64/fstat/g' \
        -e 's/lstat64/lstat/g'
    '';

  postConfigure = lib.optionalString stdenv.hostPlatform.isIllumos ''
    # Strip the 64-bit-suffix #defines that configure emitted under the
    # assumption suffixed names don't exist; on illumos they collide
    # with system headers after the source-rename pass above.
    for def in fstat64 lstat64 stat64 glob64_t glob64 globfree64 open64 readdir64 dirent64; do
      sed -i "/#define $def/d" config.h
    done
  '';

  enableParallelBuilding = true;

  passthru = {
    shellPath = "/bin/dash";
    tests = {
      "execute-simple-command" = runCommand "dash-execute-simple-command" { } ''
        mkdir $out
        ${lib.getExe dash} -c 'echo "Hello World!" > $out/success'
        [ -s $out/success ]
        grep -q "Hello World" $out/success
      '';

      /**
        Reverse dependency smoke tests. Build success of `dash.tests` informs
        whether an update makes it into staging.
      */
      reverseDependencies = lib.recurseIntoAttrs {
        writers = lib.recurseIntoAttrs {
          simple = tests.writers.simple.dash;
          bin = tests.writers.bin.dash;
        };
        # Not sure if effective smoke test, but cheap
        patch-rc-path-posix = patchRcPathPosix.tests.test-posix;
      };
    };
  };

  meta = {
    homepage = "http://gondor.apana.org.au/~herbert/dash/";
    description = "POSIX-compliant implementation of /bin/sh that aims to be as small as possible";
    platforms = lib.platforms.unix;
    license = with lib.licenses; [
      bsd3
      gpl2Plus
    ];
    mainProgram = "dash";
  };
})
