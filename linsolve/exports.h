#ifndef __LINSOLVE_H
#define __LINSOLVE_H

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__ ((visibility ("default")))
#endif

#define EXTERN extern "C" {
#ifdef __cplusplus
EXTERN
#endif

EXPORT void fullRankGeneral(int rows, int cols, double* A, double* b, double* x);
EXPORT void fullRankSemidefinite(int rows, int cols, double* A, double* b, double* x);
EXPORT void leastSquares(int rows, int cols, double* A, double* b, double* x);

#ifdef __cplusplus
}
#endif

#endif