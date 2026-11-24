# Part of the scikit-sparse project.
# SPDX-License-Identifier: BSD-2-Clause

"""Give the bundled SuiteSparse libraries SciPy's BLAS and LAPACK.

Only the binary wheels have this module. Their SuiteSparse libraries are linked
against libsksparse_blas instead of a BLAS. The source of libsksparse_blas is
in ``tools/wheels/scipy_blas/`` in the repository. Importing this module sets
the function pointers in libsksparse_blas to the functions in
:mod:`scipy.linalg.cython_blas` and :mod:`scipy.linalg.cython_lapack`, so
SuiteSparse uses the same BLAS as SciPy. ``sksparse/__init__.py`` imports this
module before any other submodule can be used.
"""

from cpython.pycapsule cimport PyCapsule_GetName, PyCapsule_GetPointer

cdef extern from *:
    """
    const char **sksparse_blas_names(void);
    int sksparse_blas_set(const char *name, void *fn);
    """
    const char **sksparse_blas_names()
    int sksparse_blas_set(const char *name, void *fn)


def _load_scipy_blas():
    from scipy.linalg import cython_blas, cython_lapack

    capi = {**cython_lapack.__pyx_capi__, **cython_blas.__pyx_capi__}
    cdef const char **names = sksparse_blas_names()
    cdef Py_ssize_t i = 0
    cdef void *fn
    missing = []
    while names[i] != NULL:
        name = names[i].decode("ascii")
        capsule = capi.get(name)
        if capsule is None:
            missing.append(name)
        else:
            fn = PyCapsule_GetPointer(capsule, PyCapsule_GetName(capsule))
            if sksparse_blas_set(names[i], fn) != 0:
                raise RuntimeError(f"Could not set BLAS/LAPACK function {name}")
        i += 1
    if missing:
        raise ImportError(
            "The installed SciPy does not export these BLAS/LAPACK functions, "
            f"which scikit-sparse needs: {', '.join(missing)}"
        )


_load_scipy_blas()
