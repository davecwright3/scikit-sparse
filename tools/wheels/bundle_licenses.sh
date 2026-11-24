#!/usr/bin/env bash
# Add the licenses of the libraries bundled into a binary wheel.
#
# This edits LICENSE.txt and pyproject.toml in place, so only run it on a
# copy of the project that is thrown away after the build. The sdist is built
# separately and keeps the plain BSD-2-Clause license.
#
# Usage: bundle_licenses.sh <project dir> <SuiteSparse source dir> <version> <url> <openmp runtime>
#   <openmp runtime> is "libgomp" if the wheel bundles libgomp, or "none".
set -euo pipefail

USAGE="usage: $0 <project dir> <suitesparse src> <version> <url> <libgomp|none>"
PROJECT_DIR="${1:?${USAGE}}"
SS_SRC="${2:?${USAGE}}"
SS_VERSION="${3:?${USAGE}}"
SS_URL="${4:?${USAGE}}"
OPENMP_RUNTIME="${5:?${USAGE}}"

LICENSE_FILE="${PROJECT_DIR}/LICENSE.txt"
PYPROJECT="${PROJECT_DIR}/pyproject.toml"
WHEEL_LICENSES="${PROJECT_DIR}/tools/wheels/licenses"
MARKER="BUNDLED LIBRARIES IN BINARY WHEELS"

case "${OPENMP_RUNTIME}" in
    libgomp | none) ;;
    *)
        echo "${USAGE}" >&2
        exit 1
        ;;
esac

# before-all can run more than once on the same copy. Append only once.
if grep -q "${MARKER}" "${LICENSE_FILE}"; then
    echo "Bundled licenses already present in ${LICENSE_FILE}"
    exit 0
fi

section() {
    printf '\n\n%s\n%s\n%s\n\n' \
        "------------------------------------------------------------------------" \
        "$1" \
        "------------------------------------------------------------------------"
}

{
    printf '\n\n========================================================================\n'
    printf '%s\n' "${MARKER}"
    printf '========================================================================\n\n'
    cat <<EOF
The scikit-sparse source code is under the BSD 2-Clause license above. This
binary wheel also contains compiled copies of the libraries listed below. Some
of them are under the GNU GPL, so the wheel as a whole is distributed under
the terms of the GNU General Public License, version 2 or later.

  * SuiteSparse ${SS_VERSION}
      SuiteSparse_config, AMD, CAMD, COLAMD, CCOLAMD ..... BSD-3-Clause
      BTF, KLU ........................................... LGPL-2.1-or-later
      CHOLMOD Utility, Check, Cholesky, Partition ......... LGPL-2.1-or-later
      CHOLMOD Supernodal, Modify, MatrixOps .............. GPL-2.0-or-later
      UMFPACK, SPQR ...................................... GPL-2.0-or-later
      METIS (built into CHOLMOD) ......................... Apache-2.0
EOF
    if [[ "${OPENMP_RUNTIME}" == libgomp ]]; then
        cat <<EOF
  * libgomp, the GCC OpenMP runtime ...................... GPL-3.0-or-later
                                                           WITH GCC-exception-3.1
EOF
    fi
    cat <<EOF

No BLAS or LAPACK library is bundled. When sksparse is imported, SuiteSparse
is set up to use the BLAS and LAPACK of the installed SciPy package.

Source code:
  * scikit-sparse: the sdist for this version on PyPI, or
    https://github.com/scikit-sparse/scikit-sparse
  * SuiteSparse: ${SS_URL}
  * The wheel build scripts: tools/wheels/ and .github/workflows/wheels.yml
    in the scikit-sparse repository.
EOF

    for pkg in AMD CAMD COLAMD CCOLAMD BTF KLU CHOLMOD UMFPACK SPQR; do
        section "SuiteSparse: ${pkg}"
        cat "${SS_SRC}/${pkg}/Doc/License.txt"
    done

    # SuiteSparse_config has no Doc/License.txt. It is BSD-3-Clause, with the
    # same text as AMD's above.

    section "METIS (SuiteSparse_metis, compiled into CHOLMOD)"
    cat "${SS_SRC}/CHOLMOD/SuiteSparse_metis/LICENSE.txt"

    section "GNU General Public License, version 2"
    cat "${SS_SRC}/UMFPACK/Doc/gpl.txt"

    section "GNU Lesser General Public License, version 2.1"
    cat "${SS_SRC}/KLU/Doc/lesser.txt"

    if [[ "${OPENMP_RUNTIME}" == libgomp ]]; then
        section "libgomp: GCC Runtime Library Exception, version 3.1"
        cat "${WHEEL_LICENSES}/COPYING.RUNTIME"

        section "GNU General Public License, version 3"
        cat "${WHEEL_LICENSES}/COPYING3"
    fi
} >> "${LICENSE_FILE}"

# The wheel's license metadata has to cover everything in it.
WHEEL_LICENSE="BSD-2-Clause AND BSD-3-Clause AND LGPL-2.1-or-later AND GPL-2.0-or-later AND Apache-2.0"
if [[ "${OPENMP_RUNTIME}" == libgomp ]]; then
    WHEEL_LICENSE="${WHEEL_LICENSE} AND GPL-3.0-or-later WITH GCC-exception-3.1"
fi
# GNU sed and the BSD sed on macOS need different arguments for in-place
# edits, so write to a temporary file instead.
sed "s/^license = \"BSD-2-Clause\"$/license = \"${WHEEL_LICENSE}\"/" \
    "${PYPROJECT}" > "${PYPROJECT}.tmp"
mv "${PYPROJECT}.tmp" "${PYPROJECT}"
if ! grep -qF "license = \"${WHEEL_LICENSE}\"" "${PYPROJECT}"; then
    echo "error: could not update the license in ${PYPROJECT}" >&2
    exit 1
fi
