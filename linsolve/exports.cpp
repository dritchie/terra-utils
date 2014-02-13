#include "exports.h"
#include <Eigen/Core>
#include <Eigen/Dense>

// using namespace std;
using namespace Eigen;

void cDataToMatrix(int rows, int cols, double* cdata, MatrixXd& mat)
{
	mat.resize(rows, cols);
	for (int i = 0; i < rows; i++)
	{
		double* dataP = cdata + i*cols;
		VectorXd v(cols);
		for (int d = 0; d < cols; d++)
			v[d] = dataP[d];
		mat.row(i) = v;
	}
}

extern "C"
{
	EXPORT void fullRankGeneral(int rows, int cols, double* A, double* b, double* x)
	{
		// Convert data in
		MatrixXd A_mat;
		MatrixXd b_vec;
		cDataToMatrix(rows, cols, A, A_mat);
		cDataToMatrix(rows, 1, b, b_vec);

		// Solve
		VectorXd x_vec = A_mat.colPivHouseholderQr().solve(b_vec);

		// Convert data out
		for (int i = 0; i < cols; i++)
			x[i] = x_vec(i);
	}

	EXPORT void fullRankSemidefinite(int rows, int cols, double* A, double* b, double* x)
	{
		// Convert data in
		MatrixXd A_mat;
		MatrixXd b_vec;
		cDataToMatrix(rows, cols, A, A_mat);
		cDataToMatrix(rows, 1, b, b_vec);

		// Solve
		VectorXd x_vec = A_mat.ldlt().solve(b_vec);

		// Convert data out
		for (int i = 0; i < cols; i++)
			x[i] = x_vec(i);
	}

	EXPORT void leastSquares(int rows, int cols, double* A, double* b, double* x)
	{
		// Convert data in
		MatrixXd A_mat;
		MatrixXd b_vec;
		cDataToMatrix(rows, cols, A, A_mat);
		cDataToMatrix(rows, 1, b, b_vec);

		// Solve
		VectorXd x_vec = A_mat.jacobiSvd(ComputeThinU | ComputeThinV).solve(b_vec);

		// Convert data out
		for (int i = 0; i < cols; i++)
			x[i] = x_vec(i);
	}
}





