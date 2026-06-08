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
  bash                   = builtins.storePath /nix/store/lrw8qramw7p54d7d3li5d08lqsppgl6q-bash-interactive-5.3p3;
  coreutils              = builtins.storePath /nix/store/sxy1z9ckdh7vcq1ppxmjpb7ynfbg4shq-coreutils-9.8;
  gnutar                 = builtins.storePath /nix/store/6jlfajig1dpd69qvfg10crz42si1jbid-gnutar-1.35;
  findutils              = builtins.storePath /nix/store/1xgdpw10fcxc8fr3b14lsgz6g71dqfyx-findutils-4.10.0;
  gnumake                = builtins.storePath /nix/store/fgkhrqjkn9a04idydl21mydi9f8nbn30-gnumake-4.4.1;
  gnused                 = builtins.storePath /nix/store/m0s1p29xh9nbrk04zrlajhn84pgdckpi-gnused-4.9;
  gnugrep                = builtins.storePath /nix/store/47ndvxgigr4m9xyq8xnlrsxnsjgz8an2-gnugrep-3.12;
  gawk                   = builtins.storePath /nix/store/3c50c0lmypp8h69n7vv39m8rh396bkdh-gawk-5.3.2;
  diffutils              = builtins.storePath /nix/store/y96waf7aimcfk9s1q33gigdmimnkj30w-diffutils-3.12;
  patch                  = builtins.storePath /nix/store/zpycqbqnrgx738gqdb622sxnvi13r0zq-patch-2.8;
  xz-bin                 = builtins.storePath /nix/store/r4s0sviwk20yjkvvhvq1pb294385f8xi-xz-5.8.3-bin;
  xz-dev                 = builtins.storePath /nix/store/hqyyij9x75bg8zivslqj1l1i8vp9hpcs-xz-5.8.3-dev;
  gzip                   = builtins.storePath /nix/store/pcw71x6j7l86n8f7wvd5h17y822lm8jj-gzip-1.14;
  bzip2-bin              = builtins.storePath /nix/store/rc7pjn4lxljsrra2csxnzx0hp5jqia9x-bzip2-1.0.8-bin;
  bzip2-dev              = builtins.storePath /nix/store/2bvvkd2779si8lcpjk0lj7nm7c8wzak7-bzip2-1.0.8-dev;
  zlib                   = builtins.storePath /nix/store/gz8f77v53chx8kkmipylnqgn5wlq1nrf-zlib-1.3.2;
  zlib-dev               = builtins.storePath /nix/store/6d1phv361488bnqzxmsv9il1phwg762g-zlib-1.3.2-dev;
  gcc-illumos = {
    out = builtins.storePath /nix/store/d72a39pg2jhxdpjd87rdy1pd1659j4xq-gcc-illumos-14.2.0-il-1;
    lib = builtins.storePath /nix/store/4s9rsxjcncpbscxlavm63hacz8yimlsv-gcc-illumos-14.2.0-il-1-lib;
  };
  binutils-unwrapped     = builtins.storePath /nix/store/fq0bc2yfvziy7nkimn8vqh216h0nj6v4-binutils-2.44;
  expand-response-params = builtins.storePath /nix/store/gb0306ylh6qwb974rk37v3a632d9csyy-expand-response-params;
  patchelf               = builtins.storePath /nix/store/gya1nqhalz0pb03jazzjgz7czd58sph5-patchelf-0.15.2;
  curl = {
    out = builtins.storePath /nix/store/46g01k42q0mj3xbpj4sil2hhkkna400w-curl-8.19.0;
    bin = builtins.storePath /nix/store/x5gdqsjzdgzqsh3axh9j0wygncdyfsvl-curl-8.19.0-bin;
  };
  gnum4                  = builtins.storePath /nix/store/fa1xp1mypyrpmpj1r7vr2133sygpmv0m-gnum4-1.4.20;
  flex                   = builtins.storePath /nix/store/dzxca3s9nm99yl7mhkki27kf2r5561cd-flex-2.6.4;
  bison                  = builtins.storePath /nix/store/kfvzma8hxnr3gjkr23j2ych4jci7gk9k-bison-3.8.2;
  perl                   = builtins.storePath /nix/store/gasv6lvsai98i7gp16qn35aapzsf6mr5-perl-5.40.0;
}
