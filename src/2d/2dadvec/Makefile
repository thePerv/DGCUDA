all: dgcuda
tests: runtests

dgcuda: main.cu 2dadvec.cu 2dadvec_kernels.cu 2dadvec_kernels_wrappers.cu quadrature.cu basis.cu basis_eval.cu time_integrator.cu
	nvcc -arch=sm_13 main.cu -o dgcuda

runtests: test_all.cu 2dadvec.cu 2dadvec_kernels.cu 2dadvec_kernels_wrappers.cu quadrature.cu basis.cu basis_eval.cu time_integrator.cu
	nvcc -arch=sm_13 test_all.cu -o runtests

