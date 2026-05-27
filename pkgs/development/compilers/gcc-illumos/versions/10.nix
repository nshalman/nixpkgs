# gcc-illumos GCC 10 version data.
#
# Pinned to github.com/illumos/gcc tag gcc-10.4.0-il-2 (the production
# SmartOS toolchain track — same tree that proto.strap is built from).
# Helper lib versions track SmartOS's gcc10/Makefile.

{
  gccVersion = "10.4.0-il-2";
  gccHash = "07vw0jgyy73irw0lzx80321dcfcv8d00wmplviybqav048h2was2";

  mpfrVersion = "4.2.0";
  mpfrHash = "17crm8g5zcpaq867avgfngrchlia1x5iwna6q1hc8vz3g28v67b9";

  gmpVersion = "6.2.1";
  gmpHash = "0z2ddfiwgi0xbf65z4fg4hqqzlhv0cc6hdcswf3c6n21xdmk5sga";

  mpcVersion = "1.3.1";
  mpcHash = "1f2rqz0hdrrhx4y1i5f8pv6yv08a876k1dqcm9s2p26gyn928r5b";

  ldFlagsPatch = ../patches/10-ld-flags.patch;
}
