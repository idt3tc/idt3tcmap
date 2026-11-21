#!/usr/bin/env bash
# Smoke test of a built (and bundled) executable: compiles, vises and
# lights the model_clipping_45_degrees regression map, then reads the BSP
# back in. The map places ASE models, which must have been loaded (via
# assimp) for the BSP to contain more than the 6 brush surfaces.
#
# On Windows, MSYS2's own DLL directories are dropped from PATH first, so
# that the test fails if a DLL is missing from the bundle.
#
# Usage: smoke-test.sh <executable>
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <executable>" >&2
    exit 2
fi
exe="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
map_dir="$(cd "$(dirname "$0")/../../regression_tests/q3map2/model_clipping_45_degrees" && pwd)"

case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
        PATH="/usr/bin:$(cygpath -u "${SYSTEMROOT}")/System32:$(cygpath -u "${SYSTEMROOT}")"
        export PATH
        ;;
esac

# Work in a scratch game directory, using relative paths only, which
# keeps MSYS2 from having to convert paths for the Windows executable
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/baseq3"
cp -R "${map_dir}"/maps "${map_dir}"/models "${map_dir}"/scripts "${work}/baseq3/"
cd "${work}"

run() {
    echo "+ idt3tcmap $*"
    "${exe}" -fs_basepath . -game quake3 "$@"
}

run -help > /dev/null
run -meta baseq3/maps/model_clipping_45_degrees.map
run -vis -fast baseq3/maps/model_clipping_45_degrees.bsp
run -light -fast baseq3/maps/model_clipping_45_degrees.bsp

info="$(run -info baseq3/maps/model_clipping_45_degrees.bsp)"
echo "${info}"
surfaces="$(awk '$2 == "drawsurfaces" { print $1 }' <<< "${info}")"
if [[ -z "${surfaces}" || "${surfaces}" -le 6 ]]; then
    echo "error: expected more than 6 drawsurfaces (models not loaded?), got '${surfaces}'" >&2
    exit 1
fi
echo "OK: ${surfaces} drawsurfaces"
