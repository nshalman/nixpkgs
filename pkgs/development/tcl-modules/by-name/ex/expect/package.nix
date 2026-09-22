{
  lib,
  stdenv,
  buildPackages,
  fetchurl,
  tcl,
  makeWrapper,
  autoreconfHook,
  fetchpatch,
  replaceVars,
}:

tcl.mkTclDerivation rec {
  pname = "expect";
  version = "5.45.4";

  src = fetchurl {
    url = "mirror://sourceforge/expect/Expect/${version}/expect${version}.tar.gz";
    hash = "sha256-Safag7C92fRtBKBN7sGcd2e7mjI+QMR4H4nK92C5LDQ=";
  };

  patches = [
    (replaceVars ./fix-build-time-run-tcl.patch {
      tcl = "${buildPackages.tcl}/bin/tclsh";
    })
    # The following patches fix compilation with clang 15+
    (fetchpatch {
      url = "https://sourceforge.net/p/expect/patches/24/attachment/0001-Add-prototype-to-function-definitions.patch";
      hash = "sha256-X2Vv6VVM3KjmBHo2ukVWe5YTVXRmqe//Kw2kr73OpZs=";
    })
    (fetchpatch {
      url = "https://sourceforge.net/p/expect/patches/_discuss/thread/b813ca9895/6759/attachment/expect-configure-c99.patch";
      hash = "sha256-PxQQ9roWgVXUoCMxkXEgu+it26ES/JuzHF6oML/nk54=";
    })
    ./0004-enable-cross-compilation.patch
    # Include `sys/ioctl.h` and `util.h` on Darwin, which are required for `ioctl` and `openpty`.
    # Include `termios.h` on FreeBSD for `openpty`
    ./fix-darwin-bsd-clang16.patch
    # Remove some code which causes it to link against a file that does not exist at build time on native FreeBSD
    ./freebsd-unversioned.patch
  ]
  ++ lib.optionals stdenv.hostPlatform.isSunOS [
    # the /dev/ptmx paths pass an int where a string is expected; gcc 14 rejects that
    ./ptmx-log-calls.patch
  ];

  postPatch = ''
    sed -i "s,/bin/stty,$(type -p stty),g" configure.in
  ''
  # exp_rearm_sigchld() calls exp_dsleep() under REARM_SIG, which configure defines on SysV-style
  # signal systems such as illumos, but exp_trap.c does not include the header that declares it.
  # ioctl() is declared in <unistd.h> on illumos. <pty.h> only exists for openpty(), which illumos
  # does not have; the pty code takes the /dev/ptmx path there.
  + lib.optionalString stdenv.hostPlatform.isSunOS ''
    sed -i '/#include "exp_command.h"/a #include "exp_event.h"' exp_trap.c
    sed -i '/#include <stdlib.h>/a #include <unistd.h>' exp_win.c
    sed -i '/#include "exp_pty.h"/a #include "exp_int.h"' pty_termios.c
    substituteInPlace pty_termios.c --replace-fail '#else /* pty.h is Linux-specific */' '#elif !defined(__sun)'
  '';

  nativeBuildInputs = [
    autoreconfHook
    makeWrapper
  ];

  strictDeps = true;

  env = {
    NIX_CFLAGS_COMPILE = toString (
      # Needed to avoid errors when building with GCC 15.
      lib.optionals stdenv.cc.isGNU [ "-Wno-error=incompatible-pointer-types" ]
      # Autoconf 2.73 defaults to C23, but Expect uses K&R style function declarations.
      ++ [ "-std=gnu17" ]
    );
  }
  # The sources prefer <sys/fcntl.h> where configure finds it; on illumos that header defines
  # the flags but does not declare open(). Make every file take the <fcntl.h> branch.
  // lib.optionalAttrs stdenv.hostPlatform.isSunOS { ac_cv_header_sys_fcntl_h = "no"; };

  hardeningDisable = [ "format" ];

  postInstall = ''
    tclWrapperArgs+=(--prefix PATH : ${lib.makeBinPath [ tcl ]})
    ${lib.optionalString stdenv.hostPlatform.isDarwin "tclWrapperArgs+=(--prefix DYLD_LIBRARY_PATH : $out/lib/expect${version})"}
  '';

  tclRequiresCheck = [ "Expect" ];

  outputs = [
    "out"
    "dev"
  ];

  meta = {
    description = "Tool for automating interactive applications";
    homepage = "https://expect.sourceforge.net/";
    license = lib.licenses.publicDomain;
    platforms = lib.platforms.unix;
    mainProgram = "expect";
    maintainers = with lib.maintainers; [ SuperSandro2000 ];
    broken = tcl.isTcl9;
  };
}
