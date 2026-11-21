#!/usr/bin/env bash
# Copies the built executable into <dest dir> together with all shared
# libraries it needs which are not part of the operating system, and makes
# it load them from there, so that the directory runs on systems which do
# not have the build dependencies installed:
#
#   Linux:   libraries go to lib/, found via RUNPATH ($ORIGIN)
#   macOS:   libraries go to lib/, found via @executable_path (dylibbundler)
#   Windows: DLLs go next to the executable (MSYS2 UCRT64 / MINGW64)
#
# Finally, checks that the executable only references bundled or system
# libraries.
#
# Usage: bundle.sh <executable> <dest dir>
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <executable> <dest dir>" >&2
    exit 2
fi
exe_src="$1"
dest="$2"
exe="${dest}/$(basename "${exe_src}")"

mkdir -p "${dest}"
cp "${exe_src}" "${exe}"

case "$(uname -s)" in
    Linux)
        # glibc itself (and the dynamic loader) has to come from the
        # target system, everything else is bundled
        system_libs='^(linux-vdso|ld-linux.*|libc|libm|libmvec|libdl|libpthread|librt|libresolv|libutil)\.so'

        mkdir -p "${dest}/lib"
        # ldd resolves the complete dependency tree, so no recursion needed
        ldd "${exe}" | awk '$2 == "=>" && $3 ~ /^\// { print $3 }' | while read -r lib; do
            if [[ "$(basename "${lib}")" =~ ${system_libs} ]]; then
                continue
            fi
            cp -L "${lib}" "${dest}/lib/"
        done

        # Bundled libraries find each other next to themselves, the
        # executable finds them in lib/ ($ORIGIN is expanded by the loader)
        # shellcheck disable=SC2016
        for lib in "${dest}"/lib/*; do
            chmod u+w "${lib}"
            patchelf --set-rpath '$ORIGIN' "${lib}"
        done
        # shellcheck disable=SC2016
        patchelf --set-rpath '$ORIGIN/lib' "${exe}"

        echo "Bundled libraries:"
        ldd "${exe}"
        if ldd "${exe}" | grep -q 'not found'; then
            echo "error: unresolved libraries" >&2
            exit 1
        fi
        # Everything but glibc must resolve into the bundle
        if ldd "${exe}" | awk '$2 == "=>" { print $1, $3 }' \
            | grep -vE "${system_libs}" | grep -vF " $(cd "${dest}/lib" && pwd -P)/"; then
            echo "error: libraries above are neither system nor bundled libraries" >&2
            exit 1
        fi
        ;;

    Darwin)
        # Copies all non-system dylibs recursively and rewrites their
        # install names to @executable_path/lib/. Homebrew's lib/ is
        # searched for @rpath references; stdin is closed, as dylibbundler
        # otherwise asks interactively for libraries it can't find.
        dylibbundler --overwrite-dir --bundle-deps --create-dir \
            --fix-file "${exe}" \
            --dest-dir "${dest}/lib" \
            --install-path @executable_path/lib/ \
            --search-path "$(brew --prefix)/lib" \
            < /dev/null

        # Rewriting load commands invalidates code signatures, which arm64
        # refuses to run, so sign everything again (ad-hoc)
        shopt -s nullglob
        for f in "${dest}"/lib/*.dylib "${exe}"; do
            codesign --force --sign - "${f}"
        done

        echo "Bundled libraries:"
        bad=0
        for f in "${exe}" "${dest}"/lib/*.dylib; do
            otool -L "${f}"
            # Only the bundle and the OS may be referenced
            if otool -L "${f}" | tail -n +2 | awk '{ print $1 }' \
                | grep -vE '^(@executable_path/lib/|@rpath/|/usr/lib/|/System/)'; then
                echo "error: ${f} references the libraries above outside the bundle" >&2
                bad=1
            fi
        done
        exit "${bad}"
        ;;

    MINGW* | MSYS* | CYGWIN*)
        # The prefix of the active MSYS2 environment, e.g. /ucrt64
        prefix="$(cygpath -u "${MINGW_PREFIX:?not in an MSYS2 MinGW environment}")"

        # ldd lists every DLL loaded, including indirect dependencies;
        # everything from the MSYS2 environment is bundled, everything
        # else is part of Windows
        ldd "${exe}" | awk '$2 == "=>" { print $3 }' | while read -r dll; do
            if [[ "${dll}" == "${prefix}"/* ]]; then
                cp "${dll}" "${dest}/"
            fi
        done

        echo "Bundled libraries:"
        ldd "${exe}"
        if ldd "${exe}" | grep -qiE 'not found|\?\?\?'; then
            echo "error: unresolved libraries" >&2
            exit 1
        fi
        ;;

    *)
        echo "error: unsupported platform $(uname -s)" >&2
        exit 1
        ;;
esac
