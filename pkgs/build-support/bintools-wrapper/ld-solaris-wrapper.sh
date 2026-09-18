#!@shell@
set -eu -o pipefail
shopt -s nullglob

if (( "${NIX_DEBUG:-0}" >= 7 )); then
    set -x
fi

# I've also tried adding -z direct and -z lazyload, but it gave too many problems with C++ exceptions :'(
# Also made sure libgcc would not be lazy-loaded, as suggested here: https://www.illumos.org/issues/2534#note-3
#   but still no success.
declare -a argsBefore=(-z ignore) argsAfter=() interp=()
relocatable=0

# This loop makes sure all -L arguments are before -l arguments, or ld may complain it cannot find a library.
# GNU binutils does not have this problem:
#   http://stackoverflow.com/questions/5817269/does-the-order-of-l-and-l-options-in-the-gnu-linker-matter
#
# It also rewrites the one option the wrappers add that the Solaris link-editor rejects:
# `-dynamic-linker`, from ld-wrapper.sh, or `-dynamic-linker=`, from cc-wrapper.sh, is parsed as
# `-d ynamic-linker`. `-rpath` is accepted as is.
while (( $# )); do
    case "$1" in
        -L)   argsBefore+=("$1" "$2"); shift ;;
        -L?*) argsBefore+=("$1") ;;
        -dynamic-linker) interp=(-I "$2"); shift ;;
        -dynamic-linker=*) interp=(-I "${1#*=}") ;;
        -r|--relocatable) relocatable=1; argsAfter+=("$1") ;;
        -rpath)
            # ld-wrapper.sh adds a RUNPATH entry for every store directory that supplies a requested library.
            # A link-only libc is one of them, but it must not be found at run time.
            if [[ -n "@linkOnlyLibc@" && "$2" == "@linkOnlyLibc@"/* ]]; then
                :
            else
                argsAfter+=("$1" "$2")
            fi
            shift ;;
        *)    argsAfter+=("$1") ;;
    esac
    shift
done

# A relocatable object has no interpreter, and the link-editor refuses to be given one for it.
#
# It also satisfies -l from archives only when making one. ld-wrapper.sh appends NIX_LDFLAGS to every link, and
# setup hooks put shared libraries in there (gettext: -lintl), which GNU ld ignores at this point and the Solaris
# link-editor reports as "library -lintl: not found". Keep a -l only if some -L directory has the archive.
if (( relocatable )); then
    interp=()
    declare -a kept=() libDirs=()
    for ((i = 0; i < ${#argsBefore[@]}; i++)); do
        case "${argsBefore[$i]}" in
            -L)   libDirs+=("${argsBefore[$((i + 1))]}") ;;
            -L?*) libDirs+=("${argsBefore[$i]#-L}") ;;
        esac
    done
    for arg in ${argsAfter[@]+"${argsAfter[@]}"}; do
        if [[ "$arg" == -l?* ]]; then
            for dir in ${libDirs[@]+"${libDirs[@]}"}; do
                if [[ -e "$dir/lib${arg#-l}.a" ]]; then
                    kept+=("$arg")
                    break
                fi
            done
        else
            kept+=("$arg")
        fi
    done
    argsAfter=(${kept[@]+"${kept[@]}"})
fi

exec "@prog@" "${argsBefore[@]}" ${interp[@]+"${interp[@]}"} "${argsAfter[@]}"
