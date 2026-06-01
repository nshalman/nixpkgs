# Setup hook (stage 4): strip GNU-ld-only symbol-filtering flags
# from Makefile* before `make` runs. Sun ld (which gcc-illumos
# invokes via baked-in --with-ld=/usr/bin/ld) rejects every flag
# in the patterns below; libtool bakes them into generated Makefiles
# whenever a project uses `-export-symbols` / `-export-symbols-regex`
# in libtool LDFLAGS, and some projects (libxslt, curl) hardcode
# `-Wl,--version-script=` directly.
#
# Effect: affected libraries export every symbol (no filtering).
# For our purposes that's fine — downstream consumers explicitly
# reference the symbols they need, and the alternative would be to
# translate per-library symbol lists into Sun-ld mapfile format.
#
# Why a hook rather than per-package patches: by the time stage 4
# is in place we'd seen 8+ packages hit the same pattern (gettext,
# jq, libcpuid, libmd, libssh2, libxslt, curl, openssl…). One sed
# rule applied to every build is cheaper than chasing each new
# package down individually.

stripIllumosLibtoolFlags() {
    if [ -z "${stripIllumosLibtoolFlags_done:-}" ]; then
        stripIllumosLibtoolFlags_done=1
        # Only touch the post-autoconf forms (Makefile, Makefile.in).
        # Modifying Makefile.am updates its mtime relative to
        # Makefile.in, which triggers automake regeneration during
        # `make` — and automake isn't on every build's PATH (e.g.
        # libxcrypt). Makefile.in is what configure consumed; Makefile
        # is what make reads. Strip from both, leave .am alone.
        find -L . -type f \
            \( -name 'Makefile' -o -name 'Makefile.in' \) \
            -print0 2>/dev/null \
          | xargs -0 -r perl -i -pe '
              s/\s*-export-symbols-regex\s+\S+//g;
              s/\s*-export-symbols\s+\S+//g;
              s/\s*-Wl,--version-script=\S+//g;
              s/\s*-Wl,-retain-symbols-file,\S+//g;
              s/\s*-Wl,-retain-symbols-file\s+-Wl,\S+//g;
          ' 2>/dev/null || true
    fi
}

preBuildHooks+=(stripIllumosLibtoolFlags)
