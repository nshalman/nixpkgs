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
    # The following patches fix compilation with clang 15+ and GCC 14+
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
    # Add missing exp_event.h include for exp_dsleep declaration (fixes GCC 14 implicit function declaration error)
    ./fix-missing-exp_event_h.patch
    # illumos/Solaris: Add POSIX PTY support (no openpty/pty.h available)
    ./illumos-pty-support.patch
  ];

  postPatch = ''
    sed -i "s,/bin/stty,$(type -p stty),g" configure.in
  '';

  nativeBuildInputs = [
    autoreconfHook
    makeWrapper
  ];

  strictDeps = true;

  env = lib.optionalAttrs stdenv.cc.isGNU {
    NIX_CFLAGS_COMPILE = "-Wno-error=incompatible-pointer-types -std=gnu17";
  };

  # GCC 14 on illumos treats these legacy C issues as errors
  preBuild = lib.optionalString stdenv.hostPlatform.isIllumos ''
    # Append warning suppressions to CFLAGS in the generated Makefile
    # Pattern matches CFLAGS followed by any whitespace and =
    sed -i 's/^CFLAGS[[:space:]]*=[[:space:]]*/CFLAGS = -Wno-error=incompatible-pointer-types -Wno-error=int-to-pointer-cast -Wno-error=int-conversion /' Makefile
  '';

  hardeningDisable = [ "format" ];

  postInstall = ''
    tclWrapperArgs+=(--prefix PATH : ${lib.makeBinPath [ tcl ]})
    ${lib.optionalString stdenv.hostPlatform.isDarwin "tclWrapperArgs+=(--prefix DYLD_LIBRARY_PATH : $out/lib/expect${version})"}
  '';

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
  };
}
