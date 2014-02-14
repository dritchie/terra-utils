#include "exports.h"
#include <Eigen/Core>
#include <Eigen/Dense>
#include <Eigen/SVD>

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

	void pseudoinverse(const MatrixXd& A, MatrixXd& P)
	{
		JacobiSVD<MatrixXd> svd(A, ComputeThinU | ComputeThinV);
		VectorXd invSingularVals = svd.singularValues();
		const double tolerance = 1e-6;
		for (int i = 0; i < invSingularVals.size(); i++)
			if (fabs(invSingularVals(i)) > tolerance)
				invSingularVals(i) = 1.0/invSingularVals(i);
			else
				invSingularVals(i) = 0.0;
		P = svd.matrixV() * invSingularVals.asDiagonal() * svd.matrixU().transpose();
	}

	EXPORT void nullSpaceProjection(int rows, int cols, double* A, double* x, double* p)
	{
		// Convert data in
		MatrixXd A_mat;
		MatrixXd x_vec;
		cDataToMatrix(rows, cols, A, A_mat);
		cDataToMatrix(cols, 1, x, x_vec);

		// Solve
		// ( Orthogonal projector is (I - A^+ * A) )
		MatrixXd A_pinv;
		pseudoinverse(A_mat, A_pinv);
		VectorXd p_vec = (MatrixXd::Identity(A_mat.cols(), A_mat.cols()) - A_pinv*A_mat) * x_vec;

		// Convert data out
		for (int i = 0; i < cols; i++)
			p[i] = p_vec(i);
	}
}





