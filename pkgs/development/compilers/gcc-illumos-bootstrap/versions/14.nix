# gcc-illumos GCC 14 version data.
#
# Pinned to github.com/illumos/gcc tag gcc-14.2.0-il-1 (Dan McDonald's
# experimental track). Helper lib versions track SmartOS's gcc14/Makefile.

{
  gccVersion = "14.2.0-il-1";
  gccHash = "18lfswx45lkizs0ygdhhwp5qswb66jqssihwb9wnx6gpw986mgzq";

  mpfrVersion = "4.2.1";
  mpfrHash = "183acv9b1ji6kzawzwcxnahlij2a1i11jfv256f0ir10bdir7pxr";

  gmpVersion = "6.3.0";
  gmpHash = "1jr03h6h0yz4w9pwyh7p6ijfk3vcsrc6139c5sp9nq7vghd22a5c";

  mpcVersion = "1.3.1";
  mpcHash = "1f2rqz0hdrrhx4y1i5f8pv6yv08a876k1dqcm9s2p26gyn928r5b";

  ldFlagsPatch = ../patches/14-ld-flags.patch;
}
