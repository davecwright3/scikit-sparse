#!/usr/bin/env bash
# Build the SuiteSparse libraries that go into the wheels, then add their
# licenses to the wheel.
#
# cibuildwheel runs this script once per platform as its before-all step. On
# Linux it runs inside the manylinux container, and on macOS it runs on the
# runner itself. cibuildwheel then compiles the extensions against the
# libraries installed in PREFIX. auditwheel on Linux and delocate on macOS copy
# those libraries into the wheel.
#
# The wheels do not bundle a BLAS. SuiteSparse is linked against
# libsksparse_blas, built from tools/wheels/scipy_blas/sksparse_blas.c, which
# passes each BLAS/LAPACK call on to the BLAS that SciPy uses.
# src/sksparse/_scipy_blas.pyx connects the two when sksparse is imported.
#
# Usage: cibw_before_all.sh <project dir> <install prefix>
set -euo pipefail

PROJECT_DIR="${1:?usage: $0 <project dir> <install prefix>}"
PREFIX="${2:?usage: $0 <project dir> <install prefix>}"
# cibuildwheel passes a relative {project} on macOS. The script changes
# directory below, so make both paths absolute.
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"
mkdir -p "${PREFIX}"
PREFIX="$(cd "${PREFIX}" && pwd)"

SUITESPARSE_VERSION="7.14.1"
SUITESPARSE_SHA256="81e560e1f74546df139edb765b3f5bc865866da23062312ffe8fd821063c8397"
SUITESPARSE_URL="https://github.com/DrTimothyAldenDavis/SuiteSparse/archive/refs/tags/v${SUITESPARSE_VERSION}.tar.gz"

# Only the parts of SuiteSparse that scikit-sparse wraps.
SUITESPARSE_PROJECTS="suitesparse_config;amd;btf;camd;ccolamd;colamd;cholmod;klu;umfpack;spqr"

BUILD_ROOT="${TMPDIR:-/tmp}/suitesparse-build"

case "$(uname -s)" in
    Linux)
        NCPU=$(nproc)
        SHIM_LIB="${PREFIX}/lib/libsksparse_blas.so"
        SHIM_FLAGS=(-shared -Wl,-soname,libsksparse_blas.so)
        # auditwheel bundles libgomp, GCC's OpenMP runtime.
        USE_OPENMP=ON
        OPENMP_RUNTIME=libgomp
        ;;
    Darwin)
        NCPU=$(sysctl -n hw.ncpu)
        SHIM_LIB="${PREFIX}/lib/libsksparse_blas.dylib"
        SHIM_FLAGS=(-dynamiclib -install_name "${SHIM_LIB}")
        # Apple's compiler does not include OpenMP.
        USE_OPENMP=OFF
        OPENMP_RUNTIME=none
        # Build SuiteSparse for the same macOS version as the extensions.
        export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
        ;;
    *)
        echo "error: unsupported platform $(uname -s)" >&2
        exit 1
        ;;
esac

sha256_check() {
    if command -v sha256sum > /dev/null; then
        sha256sum -c -
    else
        shasum -a 256 -c -
    fi
}

# Build libsksparse_blas. -fvisibility=hidden keeps every symbol private except
# the ones marked for export.
mkdir -p "${PREFIX}/lib"
cc -O2 -fPIC -fvisibility=hidden -Wall -Wextra -Werror "${SHIM_FLAGS[@]}" \
    -o "${SHIM_LIB}" "${PROJECT_DIR}/tools/wheels/scipy_blas/sksparse_blas.c"

mkdir -p "${BUILD_ROOT}"
cd "${BUILD_ROOT}"
curl -fsSL -o suitesparse.tar.gz "${SUITESPARSE_URL}"
echo "${SUITESPARSE_SHA256}  suitesparse.tar.gz" | sha256_check
tar -xzf suitesparse.tar.gz
SRC_DIR="${BUILD_ROOT}/SuiteSparse-${SUITESPARSE_VERSION}"

# SUITESPARSE_USE_STRICT makes the build fail if it cannot find a feature we
# asked for, instead of leaving it out. CUDA and Fortran are off so the build
# does not depend on what is installed on the build machine.
#
# Given BLAS_LIBRARIES and LAPACK_LIBRARIES, SuiteSparse links against them
# without searching for a BLAS. BLA_VENDOR=Generic turns off its code for
# specific BLAS libraries, such as OpenBLAS thread control.
#
# CMAKE_INSTALL_NAME_DIR only matters on macOS. It gives the libraries
# absolute install names instead of @rpath ones, so delocate can find them.
cmake -S "${SRC_DIR}" -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_NAME_DIR="${PREFIX}/lib" \
    -DSUITESPARSE_ENABLE_PROJECTS="${SUITESPARSE_PROJECTS}" \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_STATIC_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DSUITESPARSE_DEMOS=OFF \
    -DSUITESPARSE_USE_PYTHON=OFF \
    -DSUITESPARSE_USE_CUDA=OFF \
    -DSUITESPARSE_USE_FORTRAN=OFF \
    -DSUITESPARSE_USE_OPENMP="${USE_OPENMP}" \
    -DSUITESPARSE_USE_STRICT=ON \
    -DBLA_VENDOR=Generic \
    -DBLAS_LIBRARIES="${SHIM_LIB}" \
    -DLAPACK_LIBRARIES="${SHIM_LIB}"
cmake --build build --parallel "${NCPU}"
cmake --install build

# libsksparse_blas must provide every BLAS/LAPACK function SuiteSparse calls.
# The macOS linker already refuses to build a library with undefined symbols.
# On Linux, this check makes a missing function fail the build instead of the
# import.
if [[ "$(uname -s)" == Linux ]]; then
    undefined=$(
        for lib in "${PREFIX}"/lib/lib{suitesparseconfig,amd,btf,camd,ccolamd,colamd,cholmod,klu,klu_cholmod,umfpack,spqr}.so; do
            LD_LIBRARY_PATH="${PREFIX}/lib" ldd -r "${lib}" 2>&1 | grep 'undefined symbol' || true
        done
    )
    if [[ -n "${undefined}" ]]; then
        echo "error: the SuiteSparse libraries have undefined symbols." >&2
        echo "Add any missing BLAS/LAPACK functions to tools/wheels/scipy_blas/sksparse_blas.c:" >&2
        echo "${undefined}" >&2
        exit 1
    fi
fi

# On Linux, cibuildwheel copies the project into the container, so editing it
# is safe. On macOS this runs on the real checkout, so only edit it in CI.
if [[ "$(uname -s)" == Linux || -n "${CI:-}" ]]; then
    bash "${PROJECT_DIR}/tools/wheels/bundle_licenses.sh" \
        "${PROJECT_DIR}" "${SRC_DIR}" "${SUITESPARSE_VERSION}" \
        "${SUITESPARSE_URL}" "${OPENMP_RUNTIME}"
else
    echo "warning: not in CI; the wheel will not list its bundled licenses." >&2
fi
