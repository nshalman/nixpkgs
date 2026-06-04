# Stage-3 stdenv outputs as `builtins.storePath` references.
#
# These paths are NOT eval-fetched. They must already exist in
# /nix/store before any nix-build that depends on this attrset —
# typically achieved by running ../load-illumos-closure.sh once
# against the fetched closure.nar.xz (see ./default.nix wrapper).
#
# Path list mirrors closure-roots.txt produced by
# ../make-bootstrap-tools.nix. Refresh both together: rebuild the
# closure via `nix-build .../make-bootstrap-tools.nix`, update
# x86_64-illumos.nix (URL + hash), then resync these paths.
{
  bash                   = builtins.storePath /nix/store/w2s462l0dqfmq594bvfgsfayn4x8y8zw-bash-interactive-5.3p3;
  coreutils              = builtins.storePath /nix/store/qw2wjj3n2g0qlv5j3v5736b3nl1bwmyf-coreutils-9.8;
  gnutar                 = builtins.storePath /nix/store/wfr7apqgn3r7gdfq78c6nir749hdnd9c-gnutar-1.35;
  findutils              = builtins.storePath /nix/store/sgr3b3fk1nq7aa8qp5p65l9icnks3pci-findutils-4.10.0;
  gnumake                = builtins.storePath /nix/store/0rnbwga8ziipyc63a78k11y0wvci96gi-gnumake-4.4.1;
  gnused                 = builtins.storePath /nix/store/acc0pi1z60xqqqzlcqsw2ql4cz7dyj7y-gnused-4.9;
  gnugrep                = builtins.storePath /nix/store/0z8x4v7a05fz530kzaghgwa8z6dyfd24-gnugrep-3.12;
  gawk                   = builtins.storePath /nix/store/fnvl8c6v9ssmg8jhdx339nblkbzqg52a-gawk-5.3.2;
  diffutils              = builtins.storePath /nix/store/z8ahjv5hcy985hj6rk81psx96hzf96n2-diffutils-3.12;
  patch                  = builtins.storePath /nix/store/80idcvxagqar226hnmdgfm1lz1mlcwbs-patch-2.8;
  xz-bin                 = builtins.storePath /nix/store/qmhfl41gd13wfpx5pp9fgsij55cdid2p-xz-5.8.3-bin;
  xz-dev                 = builtins.storePath /nix/store/gka2cf4qv9ms7vhyz7gqa0i1ps1jrh0b-xz-5.8.3-dev;
  gzip                   = builtins.storePath /nix/store/qrlc3vq7v2p8jvg270yjc59jlssj35za-gzip-1.14;
  bzip2-bin              = builtins.storePath /nix/store/wmazypr41ss0gzlhpgd82klycds43v2c-bzip2-1.0.8-bin;
  bzip2-dev              = builtins.storePath /nix/store/fsrayjnv7i3nc6fjlqpasf1xxd05qdcl-bzip2-1.0.8-dev;
  zlib                   = builtins.storePath /nix/store/2pz3yvprsqsg9ylq6wm43s817xyrdhv1-zlib-1.3.2;
  zlib-dev               = builtins.storePath /nix/store/620zhg6jkcilncaq139f4mpxkr9516mw-zlib-1.3.2-dev;
  gcc-illumos = {
    out = builtins.storePath /nix/store/kbp48mlbn37j57mda85d1f9i206sdzyy-gcc-illumos-14.2.0-il-1;
    lib = builtins.storePath /nix/store/n23aqx5g3w1pxdkr2czqdgnxsx72vh08-gcc-illumos-14.2.0-il-1-lib;
  };
  binutils-unwrapped     = builtins.storePath /nix/store/smxxrjn00jfy9h7vxnw9x1371vvwi0vl-binutils-2.44;
  expand-response-params = builtins.storePath /nix/store/yxv5bgbj4akxsdgmz6s6lrqiy342kb2f-expand-response-params;
  patchelf               = builtins.storePath /nix/store/jfzmvf1yh2m28vxpmrs2yx1i0gax4pl4-patchelf-0.15.2;
  curl = {
    out = builtins.storePath /nix/store/mqc1fjl0pigzb65vz7m6wagcs6zl7361-curl-8.19.0;
    bin = builtins.storePath /nix/store/qvmim00wxvlk9khh9j5pg1b58jxra0az-curl-8.19.0-bin;
  };
  gnum4                  = builtins.storePath /nix/store/digdz1s7716spsh7p9w4afclqm4m179d-gnum4-1.4.20;
  flex                   = builtins.storePath /nix/store/8cy0hskb96isi6jh0jg8p250asa2297r-flex-2.6.4;
  bison                  = builtins.storePath /nix/store/n3nqn6nqmwqi4hx80d2v80x3scd05k9s-bison-3.8.2;
  perl                   = builtins.storePath /nix/store/52ah1wjicc54hnhhnralp0z19zng9lgi-perl-5.40.0;
}
