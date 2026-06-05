# Stage-2 stdenv outputs as `builtins.storePath` references.
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
  bash                   = builtins.storePath /nix/store/3ag6g3n7jxgkz1ghjymi2g2hcv7rgl01-bash-interactive-5.3p3;
  coreutils              = builtins.storePath /nix/store/hd931n7zjpjgjlf16fv83nrn1gw290dy-coreutils-9.8;
  gnutar                 = builtins.storePath /nix/store/gn5jjkxi67yazq72cq3xh1kbs8mxf8qj-gnutar-1.35;
  findutils              = builtins.storePath /nix/store/gf77ddr7n5v01gh2mxfr6kxp07l06v89-findutils-4.10.0;
  gnumake                = builtins.storePath /nix/store/czpnbqa38dw99749as410p1jr3ixprss-gnumake-4.4.1;
  gnused                 = builtins.storePath /nix/store/4lmhvnz701ry2k0p0hwvlzz384kbzwwq-gnused-4.9;
  gnugrep                = builtins.storePath /nix/store/k7hb60a681bgzx5lkjk0zaz5xcszqp31-gnugrep-3.12;
  gawk                   = builtins.storePath /nix/store/fx84hy6ny8b3ilfvh1pmd9nnj8k7d1yb-gawk-5.3.2;
  diffutils              = builtins.storePath /nix/store/nqi720vizgyrvzipl3s2mnl2m5vnc305-diffutils-3.12;
  patch                  = builtins.storePath /nix/store/31xqvsam1azpry41px476rhjfw6qs85q-patch-2.8;
  xz-bin                 = builtins.storePath /nix/store/3kfww4x2h0lpbc1w3xb90kfn2jkp752q-xz-5.8.3-bin;
  xz-dev                 = builtins.storePath /nix/store/svfg5cvm7l441cf3snhs4yjq9dwcnkc1-xz-5.8.3-dev;
  gzip                   = builtins.storePath /nix/store/wd65zwfg17kjj5dwrfqn12i8winykiik-gzip-1.14;
  bzip2-bin              = builtins.storePath /nix/store/qsx67gp1pmhnmqjy64fw1gd5nd0rn8l2-bzip2-1.0.8-bin;
  bzip2-dev              = builtins.storePath /nix/store/6bfyw3fghzkg27xkwr1i02h5cw2w7x05-bzip2-1.0.8-dev;
  zlib                   = builtins.storePath /nix/store/v14v81yg4zv2h5x9bbg0g5mhscb4fl82-zlib-1.3.2;
  zlib-dev               = builtins.storePath /nix/store/qxm3q85ccq8nymniw9ywhmcywwff7d8n-zlib-1.3.2-dev;
  gcc-illumos = {
    out = builtins.storePath /nix/store/npm26k3gpma3wpzyhv07b0g6gsbz4hix-gcc-illumos-14.2.0-il-1;
    lib = builtins.storePath /nix/store/xkahb7ay527j5zgc480g4lb37330dza0-gcc-illumos-14.2.0-il-1-lib;
  };
  binutils-unwrapped     = builtins.storePath /nix/store/yj0dl8zdripwwmci0j7yjl54j634zjlq-binutils-2.44;
  expand-response-params = builtins.storePath /nix/store/dfk7bjkczv5d8vsdbsznj5vs1jas79ar-expand-response-params;
  patchelf               = builtins.storePath /nix/store/rrl6sz254jgdw94bdjl75y612pfcncad-patchelf-0.15.2;
  curl = {
    out = builtins.storePath /nix/store/rf23vjn2zdb1kvh1qixl97ncyc2a8b26-curl-8.19.0;
    bin = builtins.storePath /nix/store/05fvajqx34nbb93rgl7ybcf7qkxa5rh8-curl-8.19.0-bin;
  };
  gnum4                  = builtins.storePath /nix/store/9j5cbdnqyfwdzcqiw42ln0gcg205h6da-gnum4-1.4.20;
  flex                   = builtins.storePath /nix/store/652ws3qvd0jag85xx5j5v2djvhfyfjhr-flex-2.6.4;
  bison                  = builtins.storePath /nix/store/w2cfryva72xr2xys5mzs9wdp7b5a8f6f-bison-3.8.2;
  perl                   = builtins.storePath /nix/store/f5fp9wdppssbari88qgrjwgi9vacpbqx-perl-5.40.0;
}
