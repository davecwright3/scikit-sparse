/*
 * Part of the scikit-sparse project.
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * libsksparse_blas: BLAS and LAPACK for the SuiteSparse libraries in the
 * binary wheels.
 *
 * The wheels do not bundle a BLAS. SuiteSparse is linked against this library
 * instead. It exports the Fortran BLAS/LAPACK symbols that SuiteSparse calls,
 * such as dgemm_ and dpotrf_, and passes each call on to the matching function
 * in scipy.linalg.cython_blas or scipy.linalg.cython_lapack. The
 * sksparse._scipy_blas extension module sets the function pointers when
 * sksparse is imported. The wheels then use the same BLAS as the installed
 * SciPy, for example OpenBLAS or Accelerate.
 *
 * Every function in the list follows the Fortran calling convention with
 * 32-bit integers, so all of its arguments are pointers. Each wrapper passes on
 * N void pointers.
 *
 * To add a function, add a line to SKSPARSE_BLAS_FUNCTIONS. If SuiteSparse
 * calls a function that is not in the list, cibw_before_all.sh fails the build.
 */

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define SKSPARSE_EXPORT __declspec(dllexport)
#else
#define SKSPARSE_EXPORT __attribute__((visibility("default")))
#endif

/*
 * X(kind, name, number of arguments). kind is the return type, VOID or
 * DOUBLE.
 */
#define SKSPARSE_BLAS_FUNCTIONS(X) \
    /* BLAS, single */             \
    X(VOID,   sgemm,  13)          \
    X(VOID,   sgemv,  11)          \
    X(VOID,   ssyrk,  10)          \
    X(VOID,   strsm,  11)          \
    X(VOID,   strsv,   8)          \
    /* BLAS, double */             \
    X(VOID,   dgemm,  13)          \
    X(VOID,   dgemv,  11)          \
    X(VOID,   dger,    9)          \
    X(DOUBLE, dnrm2,   3)          \
    X(VOID,   dsyrk,  10)          \
    X(VOID,   dtrsm,  11)          \
    X(VOID,   dtrsv,   8)          \
    /* BLAS, single complex */     \
    X(VOID,   cgemm,  13)          \
    X(VOID,   cgemv,  11)          \
    X(VOID,   cherk,  10)          \
    X(VOID,   ctrsm,  11)          \
    X(VOID,   ctrsv,   8)          \
    /* BLAS, double complex */     \
    X(VOID,   zgemm,  13)          \
    X(VOID,   zgemv,  11)          \
    X(VOID,   zgeru,   9)          \
    X(VOID,   zherk,  10)          \
    X(DOUBLE, dznrm2,  3)          \
    X(VOID,   ztrsm,  11)          \
    X(VOID,   ztrsv,   8)          \
    /* LAPACK */                   \
    X(VOID,   spotrf,  5)          \
    X(VOID,   dpotrf,  5)          \
    X(VOID,   cpotrf,  5)          \
    X(VOID,   zpotrf,  5)          \
    X(VOID,   dlarf,   9)          \
    X(VOID,   dlarfb, 15)          \
    X(VOID,   dlarfg,  5)          \
    X(VOID,   dlarft,  9)          \
    X(VOID,   zlarf,   9)          \
    X(VOID,   zlarfb, 15)          \
    X(VOID,   zlarfg,  5)          \
    X(VOID,   zlarft,  9)

#define RET_VOID   void
#define RET_DOUBLE double
#define RETURN_VOID
#define RETURN_DOUBLE return

#define PARAMS_3  void *a1, void *a2, void *a3
#define PARAMS_5  PARAMS_3, void *a4, void *a5
#define PARAMS_8  PARAMS_5, void *a6, void *a7, void *a8
#define PARAMS_9  PARAMS_8, void *a9
#define PARAMS_10 PARAMS_9, void *a10
#define PARAMS_11 PARAMS_10, void *a11
#define PARAMS_13 PARAMS_11, void *a12, void *a13
#define PARAMS_15 PARAMS_13, void *a14, void *a15

#define ARGS_3  a1, a2, a3
#define ARGS_5  ARGS_3, a4, a5
#define ARGS_8  ARGS_5, a6, a7, a8
#define ARGS_9  ARGS_8, a9
#define ARGS_10 ARGS_9, a10
#define ARGS_11 ARGS_10, a11
#define ARGS_13 ARGS_11, a12, a13
#define ARGS_15 ARGS_13, a14, a15

/* Pointers to SciPy's functions. They are NULL until _scipy_blas runs. */
#define DECLARE_POINTER(kind, name, n) \
    static RET_##kind (*sksparse_ptr_##name)(PARAMS_##n) = NULL;
SKSPARSE_BLAS_FUNCTIONS(DECLARE_POINTER)

static void sksparse_blas_not_loaded(const char *name)
{
    fprintf(stderr,
            "scikit-sparse: SuiteSparse called the BLAS/LAPACK function %s "
            "before sksparse loaded it from SciPy. Import sksparse before "
            "using its bundled SuiteSparse libraries.\n",
            name);
    abort();
}

/* The exported Fortran symbols that SuiteSparse links against. */
#define DEFINE_WRAPPER(kind, name, n)                          \
    SKSPARSE_EXPORT RET_##kind name##_(PARAMS_##n)             \
    {                                                          \
        if (sksparse_ptr_##name == NULL) {                     \
            sksparse_blas_not_loaded(#name);                   \
        }                                                      \
        RETURN_##kind sksparse_ptr_##name(ARGS_##n);           \
    }
SKSPARSE_BLAS_FUNCTIONS(DEFINE_WRAPPER)

#define LIST_NAME(kind, name, n) #name,
static const char *sksparse_blas_name_list[] = {
    SKSPARSE_BLAS_FUNCTIONS(LIST_NAME)
    NULL
};

/* Return the NULL-terminated list of functions that _scipy_blas must set. */
SKSPARSE_EXPORT const char **sksparse_blas_names(void)
{
    return sksparse_blas_name_list;
}

/* Set the function called by name##_. Returns 0, or -1 for an unknown name. */
SKSPARSE_EXPORT int sksparse_blas_set(const char *name, void *fn)
{
#define SET_IF_MATCH(kind, fname, n)                              \
    if (strcmp(name, #fname) == 0) {                              \
        sksparse_ptr_##fname = (RET_##kind (*)(PARAMS_##n)) fn;   \
        return 0;                                                 \
    }
    SKSPARSE_BLAS_FUNCTIONS(SET_IF_MATCH)
#undef SET_IF_MATCH
    return -1;
}
