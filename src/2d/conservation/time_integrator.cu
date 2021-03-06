/* time_integrator.cu
 *
 * time integration functions.
 */
#ifndef TIMEINTEGRATOR_H_GUARD
#define TIMEINTEGRATOR_H_GUARD
void checkCudaError(const char*);
#endif

#define TOL 5.0e-8
#define N_MAX 10

extern int local_N;

typedef void (*surface_ftn)(double*, double*, 
                 double*, double*,
                 double*, double*,
                 double*, double*,
                 double*, double*,
                 int*, int*,
                 int*, int*,
                 double*, double*,
                 int, int, int, int, int, double);

typedef void (*volume_ftn)(double*, double*, 
                double*, double*, 
                double*, double*,
                int, int, int);

 void dispatch_functions(surface_ftn &eval_surface_ftn, 
                         volume_ftn  &eval_volume_ftn, int n) {
    switch(local_N) {
        case 1:
            switch (n) {
                case 0: eval_surface_ftn = eval_surface_wrapper1_0;
                        eval_volume_ftn  = eval_volume_wrapper1_0;
                        break;
                case 1: eval_surface_ftn = eval_surface_wrapper1_1;
                        eval_volume_ftn  = eval_volume_wrapper1_1;
                        break;
                case 2: eval_surface_ftn = eval_surface_wrapper1_2;
                        eval_volume_ftn  = eval_volume_wrapper1_2;
                        break;
                case 3: eval_surface_ftn = eval_surface_wrapper1_3;
                        eval_volume_ftn  = eval_volume_wrapper1_3;
                        break;
                case 4: eval_surface_ftn = eval_surface_wrapper1_4;
                        eval_volume_ftn  = eval_volume_wrapper1_4;
                        break;
                case 5: eval_surface_ftn = eval_surface_wrapper1_5;
                        eval_volume_ftn  = eval_volume_wrapper1_5;
                        break;
            }
            break;
       case 2:
            switch (n) {
                case 0: eval_surface_ftn = eval_surface_wrapper2_0;
                        eval_volume_ftn  = eval_volume_wrapper2_0;
                        break;
                case 1: eval_surface_ftn = eval_surface_wrapper2_1;
                        eval_volume_ftn  = eval_volume_wrapper2_1;
                        break;
                case 2: eval_surface_ftn = eval_surface_wrapper2_2;
                        eval_volume_ftn  = eval_volume_wrapper2_2;
                        break;
                case 3: eval_surface_ftn = eval_surface_wrapper2_3;
                        eval_volume_ftn  = eval_volume_wrapper2_3;
                        break;
                case 4: eval_surface_ftn = eval_surface_wrapper2_4;
                        eval_volume_ftn  = eval_volume_wrapper2_4;
                        break;
                case 5: eval_surface_ftn = eval_surface_wrapper2_5;
                        eval_volume_ftn  = eval_volume_wrapper2_5;
                        break;
            }
            break;
       case 3:
            switch (n) {
                case 0: eval_surface_ftn = eval_surface_wrapper3_0;
                        eval_volume_ftn  = eval_volume_wrapper3_0;
                        break;
                case 1: eval_surface_ftn = eval_surface_wrapper3_1;
                        eval_volume_ftn  = eval_volume_wrapper3_1;
                        break;
                case 2: eval_surface_ftn = eval_surface_wrapper3_2;
                        eval_volume_ftn  = eval_volume_wrapper3_2;
                        break;
                case 3: eval_surface_ftn = eval_surface_wrapper3_3;
                        eval_volume_ftn  = eval_volume_wrapper3_3;
                        break;
                case 4: eval_surface_ftn = eval_surface_wrapper3_4;
                        eval_volume_ftn  = eval_volume_wrapper3_4;
                        break;
                case 5: eval_surface_ftn = eval_surface_wrapper3_5;
                        eval_volume_ftn  = eval_volume_wrapper3_5;
                        break;
            }
            break;
       case 4:
            switch (n) {
                case 0: eval_surface_ftn = eval_surface_wrapper4_0;
                        eval_volume_ftn  = eval_volume_wrapper4_0;
                        break;
                case 1: eval_surface_ftn = eval_surface_wrapper4_1;
                        eval_volume_ftn  = eval_volume_wrapper4_1;
                        break;
                case 2: eval_surface_ftn = eval_surface_wrapper4_2;
                        eval_volume_ftn  = eval_volume_wrapper4_2;
                        break;
                case 3: eval_surface_ftn = eval_surface_wrapper4_3;
                        eval_volume_ftn  = eval_volume_wrapper4_3;
                        break;
                case 4: eval_surface_ftn = eval_surface_wrapper4_4;
                        eval_volume_ftn  = eval_volume_wrapper4_4;
                        break;
                case 5: eval_surface_ftn = eval_surface_wrapper4_5;
                        eval_volume_ftn  = eval_volume_wrapper4_5;
                        break;
            }
            break;
    }
}

/* right hand side
 *
 * computes the sum of the quadrature and the riemann flux for the 
 * coefficients for each element
 * THREADS: num_elem
 */
__global__ void eval_rhs(double *c, double *quad_rhs, double *left_riemann_rhs, double *right_riemann_rhs, 
                         int *elem_s1, int *elem_s2, int *elem_s3,
                         int *left_elem, double *J, 
                         double dt, int n_p, int num_sides, int num_elem) {
    int idx = blockDim.x * blockIdx.x + threadIdx.x;
    double s1_eqn[N_MAX], s2_eqn[N_MAX], s3_eqn[N_MAX];
    double j;
    int i, s1_idx, s2_idx, s3_idx;
    int n;

    if (idx < num_elem) {

        j = J[idx];

        // get the indicies for the riemann contributions for this element
        s1_idx = elem_s1[idx];
        s2_idx = elem_s2[idx];
        s3_idx = elem_s3[idx];

        for (i = 0; i < n_p; i++) {

            // determine left or right pointing
            if (idx == left_elem[s1_idx]) {
                for (n = 0; n < N; n++) {
                    s1_eqn[n] = left_riemann_rhs[num_sides * n_p * n + i * num_sides + s1_idx];
                }
            } else {
                for (n = 0; n < N; n++) {
                    s1_eqn[n] = right_riemann_rhs[num_sides * n_p * n + i * num_sides + s1_idx];
                }
            }

            if (idx == left_elem[s2_idx]) {
                for (n = 0; n < N; n++) {
                    s2_eqn[n] = left_riemann_rhs[num_sides * n_p * n + i * num_sides + s2_idx];
                }
            } else {
                for (n = 0; n < N; n++) {
                    s2_eqn[n] = right_riemann_rhs[num_sides * n_p * n + i * num_sides + s2_idx];
                }
            }

            if (idx == left_elem[s3_idx]) {
                for (n = 0; n < N; n++) {
                    s3_eqn[n] = left_riemann_rhs[num_sides * n_p * n + i * num_sides + s3_idx];
                }
            } else {
                for (n = 0; n < N; n++) {
                    s3_eqn[n] = right_riemann_rhs[num_sides * n_p * n + i * num_sides + s3_idx];
                }
            }

            // calculate the coefficient c
            for (n = 0; n < N; n++) {
                c[num_elem * n_p * n + i * num_elem + idx] = 1. / j * dt * (quad_rhs[num_elem * n_p * n + i * num_elem + idx] + s1_eqn[n] + s2_eqn[n] + s3_eqn[n]);
            }
        }
    }
}

/* tempstorage for RK
 * 
 * I need to store u + alpha * k_i into some temporary variable called k*.
 */
__global__ void rk_tempstorage(double *c, double *kstar, double*k, double alpha, int n_p, int num_elem) {
    int idx = blockDim.x * blockIdx.x + threadIdx.x;

    if (idx < N * n_p * num_elem) {
        kstar[idx] = c[idx] + alpha * k[idx];
    }
}


/***********************
 * RK4 
 ***********************/

/* rk4
 *
 * computes the runge-kutta solution 
 * u_n+1 = u_n + k1/6 + k2/3 + k3/3 + k4/6
 */
__global__ void rk4(double *c, double *k1, double *k2, double *k3, double *k4, int n_p, int num_elem) {
    int idx = blockDim.x * blockIdx.x + threadIdx.x;

    if (idx < N * n_p * num_elem) {
        c[idx] += k1[idx]/6. + k2[idx]/3. + k3[idx]/3. + k4[idx]/6.;
    }
}


void time_integrate_rk4(int n_quad, int n_quad1d, int n_p, int n, int num_elem, int num_sides,
                        double endtime, double min_r) {
    int n_threads = 128;
    int i;
    double dt, t;

    double *c = (double *) malloc(num_elem * n_p * 4 * sizeof(double));
    double *max_lambda = (double *) malloc(num_elem * sizeof(double));
    double max_l;

    int n_blocks_elem  = (num_elem  / n_threads) + ((num_elem  % n_threads) ? 1 : 0);
    int n_blocks_sides = (num_sides / n_threads) + ((num_sides % n_threads) ? 1 : 0);
    int n_blocks_rk    = ((local_N * n_p * num_elem) / n_threads) + (((local_N * n_p * num_elem) % n_threads) ? 1 : 0);

    surface_ftn eval_surface_ftn = NULL;
    volume_ftn  eval_volume_ftn  = NULL;

    dispatch_functions(eval_surface_ftn, eval_volume_ftn, n);

    if ((eval_surface_ftn == NULL) || 
        (eval_volume_ftn == NULL)) {
        printf("ERROR: dispatched kernel functions in rk4 were NULL.\n");
        exit(0);
    }

    t = 0;
    double convergence = 1 + TOL;
    int timestep = 0;

    printf("Computing...\n");
    //while (t < endtime && convergence > TOL) {
    while (t < endtime) {
        // compute all the lambda values over each cell
        eval_global_lambda<<<n_blocks_elem, n_threads>>>(d_c, d_lambda, n_quad, n_p, num_elem);

        // just grab all the lambdas and sort them since there are so few of them
        cudaMemcpy(max_lambda, d_lambda, num_elem * sizeof(double), cudaMemcpyDeviceToHost);
        max_l = max_lambda[0];
        for (i = 0; i < num_elem; i++) {
            max_l = (max_lambda[i] > max_l) ? max_lambda[i] : max_l;
        }

        dt  = 0.7 * min_r / max_l /  (2. * n + 1.);
        // get next timestep
        if (t + dt > endtime) {
            dt = endtime - t;
            t = endtime;
        } else {
            t += dt;
        }
        printf("\rt = %lf", t);

        // stage 1
        cudaThreadSynchronize();
        checkCudaError("error before stage 1: eval_surface");
        eval_surface_ftn<<<n_blocks_sides, n_threads>>>
                        (d_c, d_left_riemann_rhs, d_right_riemann_rhs, 
                         d_s_length, 
                         d_V1x, d_V1y,
                         d_V2x, d_V2y,
                         d_V3x, d_V3y,
                         d_left_elem, d_right_elem,
                         d_left_side_number, d_right_side_number,
                         d_Nx, d_Ny, 
                         n_quad1d, n_quad, n_p, num_sides, num_elem, t);

        checkCudaError("error after stage 1: eval_surface");

        eval_volume_ftn<<<n_blocks_elem, n_threads>>>
                        (d_c, d_quad_rhs, 
                         d_xr, d_yr, d_xs, d_ys,
                         n_quad, n_p, num_elem);
        cudaThreadSynchronize();

        checkCudaError("error after stage 1: eval_volume");

        eval_rhs<<<n_blocks_elem, n_threads>>>(d_k1, d_quad_rhs, d_left_riemann_rhs, d_right_riemann_rhs, 
                                              d_elem_s1, d_elem_s2, d_elem_s3, 
                                              d_left_elem, d_J, dt, n_p, num_sides, num_elem);
        cudaThreadSynchronize();

        //limit_c<<<n_blocks_elem, n_threads>>>(d_k1, n_p, num_elem);
        cudaThreadSynchronize();

        rk_tempstorage<<<n_blocks_rk, n_threads>>>(d_c, d_kstar, d_k1, 0.5, n_p, num_elem);
        cudaThreadSynchronize();
        checkCudaError("error after stage 1.");

        // stage 2
        eval_surface_ftn<<<n_blocks_sides, n_threads>>>
                        (d_kstar, d_left_riemann_rhs, d_right_riemann_rhs, 
                         d_s_length, 
                         d_V1x, d_V1y,
                         d_V2x, d_V2y,
                         d_V3x, d_V3y,
                         d_left_elem, d_right_elem,
                         d_left_side_number, d_right_side_number,
                         d_Nx, d_Ny, 
                         n_quad1d, n_quad, n_p, num_sides, num_elem, t + 0.5*dt);

        eval_volume_ftn<<<n_blocks_elem, n_threads>>>
                        (d_kstar, d_quad_rhs, 
                         d_xr, d_yr, d_xs, d_ys,
                         n_quad, n_p, num_elem);
        cudaThreadSynchronize();

        eval_rhs<<<n_blocks_elem, n_threads>>>(d_k2, d_quad_rhs, d_left_riemann_rhs, d_right_riemann_rhs,
                                              d_elem_s1, d_elem_s2, d_elem_s3, 
                                              d_left_elem, d_J, dt, n_p, num_sides, num_elem);
        cudaThreadSynchronize();

        //limit_c<<<n_blocks_elem, n_threads>>>(d_k2, n_p, num_elem);
        cudaThreadSynchronize();

        rk_tempstorage<<<n_blocks_rk, n_threads>>>(d_c, d_kstar, d_k2, 0.5, n_p, num_elem);
        cudaThreadSynchronize();

        checkCudaError("error after stage 2.");

        // stage 3
        eval_surface_ftn<<<n_blocks_sides, n_threads>>>
                        (d_kstar, d_left_riemann_rhs, d_right_riemann_rhs, 
                         d_s_length, 
                         d_V1x, d_V1y,
                         d_V2x, d_V2y,
                         d_V3x, d_V3y,
                         d_left_elem, d_right_elem,
                         d_left_side_number, d_right_side_number,
                         d_Nx, d_Ny, 
                         n_quad1d, n_quad, n_p, num_sides, num_elem, t + 0.5*dt);

        eval_volume_ftn<<<n_blocks_elem, n_threads>>>
                        (d_kstar, d_quad_rhs, 
                         d_xr, d_yr, d_xs, d_ys,
                         n_quad, n_p, num_elem);
        cudaThreadSynchronize();

        eval_rhs<<<n_blocks_elem, n_threads>>>(d_k3, d_quad_rhs, d_left_riemann_rhs, d_right_riemann_rhs, 
                                              d_elem_s1, d_elem_s2, d_elem_s3, 
                                              d_left_elem, d_J, dt, n_p, num_sides, num_elem);
        cudaThreadSynchronize();

        //limit_c<<<n_blocks_elem, n_threads>>>(d_k3, n_p, num_elem);

        rk_tempstorage<<<n_blocks_rk, n_threads>>>(d_c, d_kstar, d_k3, 1.0, n_p, num_elem);
        cudaThreadSynchronize();

        checkCudaError("error after stage 3.");

        // stage 4
        eval_surface_ftn<<<n_blocks_sides, n_threads>>>
                        (d_kstar, d_left_riemann_rhs, d_right_riemann_rhs, 
                         d_s_length, 
                         d_V1x, d_V1y,
                         d_V2x, d_V2y,
                         d_V3x, d_V3y,
                         d_left_elem, d_right_elem,
                         d_left_side_number, d_right_side_number,
                         d_Nx, d_Ny, 
                         n_quad1d, n_quad, n_p, num_sides, num_elem, t + dt);

        eval_volume_ftn<<<n_blocks_elem, n_threads>>>
                        (d_kstar, d_quad_rhs, 
                         d_xr, d_yr, d_xs, d_ys,
                         n_quad, n_p, num_elem);
        cudaThreadSynchronize();

        eval_rhs<<<n_blocks_elem, n_threads>>>(d_k4, d_quad_rhs, d_left_riemann_rhs, d_right_riemann_rhs, 
                                              d_elem_s1, d_elem_s2, d_elem_s3, 
                                              d_left_elem, d_J, dt, n_p, num_sides, num_elem);
        cudaThreadSynchronize();

        //limit_c<<<n_blocks_elem, n_threads>>>(d_k4, n_p, num_elem);

        checkCudaError("error after stage 4.");
        
        // final stage
        rk4<<<n_blocks_rk, n_threads>>>(d_c, d_k1, d_k2, d_k3, d_k4, n_p, num_elem);
        cudaThreadSynchronize();

        /*
        if (timestep > 0.) {
            check_convergence<<<n_blocks_rk4, n_threads>>>(d_c_prev, d_c, num_elem, n_p);
            cudaMemcpy(c, d_c_prev, num_elem * n_p * 4 * sizeof(double), cudaMemcpyDeviceToHost);

            convergence = c[0];
            for (i = 1; i < num_elem * n_p * 4; i++) {
                if (c[i] > convergence) {
                    convergence = c[i];
                }
            }

            convergence = sqrtf(convergence);

            printf(" > convergence = %.015lf\n", convergence);
            printf(" > TOL         = %.015lf\n", TOL);
        }


        cudaMemcpy(d_c_prev, d_c, num_elem * n_p * 4 * sizeof(double), cudaMemcpyDeviceToDevice);
        */

        timestep++;


        cudaThreadSynchronize();
        checkCudaError("error after final stage.");

    }

    printf("\n");
    free(max_lambda);
    free(c);
}


/***********************
 * RK2 
 ***********************/

/* tempstorage for RK2
 * 
 * I need to store u + alpha * k_i into some temporary variable called k*.
 */
__global__ void rk2_tempstorage(double *c, double *kstar, double*k, double alpha, int n_p, int num_elem) {
    int idx = blockDim.x * blockIdx.x + threadIdx.x;

    if (idx < N * n_p * num_elem) {
        kstar[idx] = c[idx] + alpha * k[idx];
    }
}

/* rk2
 *
 * computes the runge-kutta solution 
 * u_n+1 = u_n + k1/6 + k2/3 + k3/3 + k4/6
 */
__global__ void rk2(double *c, double *k, int n_p, int num_elem) {
    int idx = blockDim.x * blockIdx.x + threadIdx.x;

    if (idx < N * n_p * num_elem) {
        c[idx] += k[idx];
    }
}

void time_integrate_rk2(int n_quad, int n_quad1d, int n_p, int n, int num_elem, int num_sides,
                        double endtime, double min_r) {
    int n_threads = 128;
    int i;
    double dt, t;

    double *c = (double *) malloc(num_elem * n_p * 4 * sizeof(double));
    double *max_lambda = (double *) malloc(num_elem * sizeof(double));
    double max_l;

    int n_blocks_elem  = (num_elem  / n_threads) + ((num_elem  % n_threads) ? 1 : 0);
    int n_blocks_sides = (num_sides / n_threads) + ((num_sides % n_threads) ? 1 : 0);
    int n_blocks_rk    = ((local_N * n_p * num_elem) / n_threads) + (((local_N * n_p * num_elem) % n_threads) ? 1 : 0);

    surface_ftn eval_surface_ftn = NULL;
    volume_ftn  eval_volume_ftn  = NULL;

    dispatch_functions(eval_surface_ftn, eval_volume_ftn, n);

    if ((eval_surface_ftn == NULL) || 
        (eval_volume_ftn == NULL)) {
        printf("ERROR: dispatched kernel functions in rk4 were NULL.\n");
        exit(0);
    }

    t = 0;
    double convergence = 1 + TOL;
    int timestep = 0;

    printf("Computing...\n");
    //while (t < endtime && convergence > TOL) {
    while (t < endtime) {
        // compute all the lambda values over each cell
        eval_global_lambda<<<n_blocks_elem, n_threads>>>(d_c, d_lambda, n_quad, n_p, num_elem);

        // just grab all the lambdas and sort them since there are so few of them
        cudaMemcpy(max_lambda, d_lambda, num_elem * sizeof(double), cudaMemcpyDeviceToHost);
        max_l = max_lambda[0];
        for (i = 0; i < num_elem; i++) {
            max_l = (max_lambda[i] > max_l) ? max_lambda[i] : max_l;
        }

        dt  = 0.7 * min_r / max_l /  (2. * n + 1.);
        if (t + dt > endtime) {
            dt = endtime - t;
            t = endtime;
        } else {
            t += dt;
        }

        printf("\rt = %lf", t);

        // stage 1
        cudaThreadSynchronize();
        checkCudaError("error before stage 1: eval_surface");
        eval_surface_ftn<<<n_blocks_sides, n_threads>>>
                        (d_c, d_left_riemann_rhs, d_right_riemann_rhs, 
                         d_s_length, 
                         d_V1x, d_V1y,
                         d_V2x, d_V2y,
                         d_V3x, d_V3y,
                         d_left_elem, d_right_elem,
                         d_left_side_number, d_right_side_number,
                         d_Nx, d_Ny, 
                         n_quad1d, n_quad, n_p, num_sides, num_elem, t);

        checkCudaError("error after stage 1: eval_surface");

        eval_volume_ftn<<<n_blocks_elem, n_threads>>>
                        (d_c, d_quad_rhs, 
                         d_xr, d_yr, d_xs, d_ys,
                         n_quad, n_p, num_elem);
        cudaThreadSynchronize();

        checkCudaError("error after stage 1: eval_volume");

        eval_rhs<<<n_blocks_elem, n_threads>>>(d_k1, d_quad_rhs, d_left_riemann_rhs, d_right_riemann_rhs, 
                                              d_elem_s1, d_elem_s2, d_elem_s3, 
                                              d_left_elem, d_J, dt, n_p, num_sides, num_elem);
        cudaThreadSynchronize();

        rk_tempstorage<<<n_blocks_rk, n_threads>>>(d_c, d_kstar, d_k1, 0.5, n_p, num_elem);
        cudaThreadSynchronize();
        checkCudaError("error after stage 1.");

        // stage 2
        eval_surface_ftn<<<n_blocks_sides, n_threads>>>
                        (d_kstar, d_left_riemann_rhs, d_right_riemann_rhs, 
                         d_s_length, 
                         d_V1x, d_V1y,
                         d_V2x, d_V2y,
                         d_V3x, d_V3y,
                         d_left_elem, d_right_elem,
                         d_left_side_number, d_right_side_number,
                         d_Nx, d_Ny, 
                         n_quad1d, n_quad, n_p, num_sides, num_elem, t + 0.5*dt);

        eval_volume_ftn<<<n_blocks_elem, n_threads>>>
                        (d_kstar, d_quad_rhs, 
                         d_xr, d_yr, d_xs, d_ys,
                         n_quad, n_p, num_elem);
        cudaThreadSynchronize();

        eval_rhs<<<n_blocks_elem, n_threads>>>(d_k1, d_quad_rhs, d_left_riemann_rhs, d_right_riemann_rhs,
                                              d_elem_s1, d_elem_s2, d_elem_s3, 
                                              d_left_elem, d_J, dt, n_p, num_sides, num_elem);
        cudaThreadSynchronize();

        //limit_c<<<n_blocks_elem, n_threads>>>(d_k2, n_p, num_elem);
        checkCudaError("error after stage 2.");

        // final stage
        rk2<<<n_blocks_rk, n_threads>>>(d_c, d_k1, n_p, num_elem);
        cudaThreadSynchronize();

        /*
        if (timestep > 0.) {
            check_convergence<<<n_blocks_rk4, n_threads>>>(d_c_prev, d_c, num_elem, n_p);
            cudaMemcpy(c, d_c_prev, num_elem * n_p * 4 * sizeof(double), cudaMemcpyDeviceToHost);

            convergence = c[0];
            for (i = 1; i < num_elem * n_p * 4; i++) {
                if (c[i] > convergence) {
                    convergence = c[i];
                }
            }

            convergence = sqrtf(convergence);

            printf(" > convergence = %.015lf\n", convergence);
            printf(" > TOL         = %.015lf\n", TOL);
        }


        cudaMemcpy(d_c_prev, d_c, num_elem * n_p * 4 * sizeof(double), cudaMemcpyDeviceToDevice);
        */

        timestep++;


        cudaThreadSynchronize();
        checkCudaError("error after final stage.");

    }

    printf("\n");
    free(max_lambda);
    free(c);
}



/***********************
 * FORWARD EULER
 ***********************/

__global__ void eval_rhs_fe(double *c, double *quad_rhs, double *left_riemann_rhs, double *right_riemann_rhs, 
                         int *elem_s1, int *elem_s2, int *elem_s3,
                         int *left_elem, double *J, 
                         double dt, int n_p, int num_sides, int num_elem) {
    int idx = blockDim.x * blockIdx.x + threadIdx.x;
    double s1_eqn1, s2_eqn1, s3_eqn1;
    double s1_eqn2, s2_eqn2, s3_eqn2;
    double s1_eqn3, s2_eqn3, s3_eqn3;
    double s1_eqn4, s2_eqn4, s3_eqn4;
    double register_J;
    int i, s1_idx, s2_idx, s3_idx;

    if (idx < num_elem) {

        register_J = J[idx];

        // get the indicies for the riemann contributions for this element
        s1_idx = elem_s1[idx];
        s2_idx = elem_s2[idx];
        s3_idx = elem_s3[idx];

        for (i = 0; i < n_p; i++) {

            // determine left or right pointing
            if (idx == left_elem[s1_idx]) {
                s1_eqn1 = left_riemann_rhs[num_sides * n_p * 0 + i * num_sides + s1_idx];
                s1_eqn2 = left_riemann_rhs[num_sides * n_p * 1 + i * num_sides + s1_idx];
                s1_eqn3 = left_riemann_rhs[num_sides * n_p * 2 + i * num_sides + s1_idx];
                s1_eqn4 = left_riemann_rhs[num_sides * n_p * 3 + i * num_sides + s1_idx];
            } else {
                s1_eqn1 = right_riemann_rhs[num_sides * n_p * 0 + i * num_sides + s1_idx];
                s1_eqn2 = right_riemann_rhs[num_sides * n_p * 1 + i * num_sides + s1_idx];
                s1_eqn3 = right_riemann_rhs[num_sides * n_p * 2 + i * num_sides + s1_idx];
                s1_eqn4 = right_riemann_rhs[num_sides * n_p * 3 + i * num_sides + s1_idx];
            }

            if (idx == left_elem[s2_idx]) {
                s2_eqn1 = left_riemann_rhs[num_sides * n_p * 0 + i * num_sides + s2_idx];
                s2_eqn2 = left_riemann_rhs[num_sides * n_p * 1 + i * num_sides + s2_idx];
                s2_eqn3 = left_riemann_rhs[num_sides * n_p * 2 + i * num_sides + s2_idx];
                s2_eqn4 = left_riemann_rhs[num_sides * n_p * 3 + i * num_sides + s2_idx];
            } else {
                s2_eqn1 = right_riemann_rhs[num_sides * n_p * 0 + i * num_sides + s2_idx];
                s2_eqn2 = right_riemann_rhs[num_sides * n_p * 1 + i * num_sides + s2_idx];
                s2_eqn3 = right_riemann_rhs[num_sides * n_p * 2 + i * num_sides + s2_idx];
                s2_eqn4 = right_riemann_rhs[num_sides * n_p * 3 + i * num_sides + s2_idx];
            }

            if (idx == left_elem[s3_idx]) {
                s3_eqn1 = left_riemann_rhs[num_sides * n_p * 0 + i * num_sides + s3_idx];
                s3_eqn2 = left_riemann_rhs[num_sides * n_p * 1 + i * num_sides + s3_idx];
                s3_eqn3 = left_riemann_rhs[num_sides * n_p * 2 + i * num_sides + s3_idx];
                s3_eqn4 = left_riemann_rhs[num_sides * n_p * 3 + i * num_sides + s3_idx];
            } else {
                s3_eqn1 = right_riemann_rhs[num_sides * n_p * 0 + i * num_sides + s3_idx];
                s3_eqn2 = right_riemann_rhs[num_sides * n_p * 1 + i * num_sides + s3_idx];
                s3_eqn3 = right_riemann_rhs[num_sides * n_p * 2 + i * num_sides + s3_idx];
                s3_eqn4 = right_riemann_rhs[num_sides * n_p * 3 + i * num_sides + s3_idx];
            }

            // calculate the coefficient c
            c[num_elem * n_p * 0 + i * num_elem + idx] += 1. / register_J * dt * (quad_rhs[num_elem * n_p * 0 + i * num_elem + idx] + s1_eqn1 + s2_eqn1 + s3_eqn1);
            c[num_elem * n_p * 1 + i * num_elem + idx] += 1. / register_J * dt * (quad_rhs[num_elem * n_p * 1 + i * num_elem + idx] + s1_eqn2 + s2_eqn2 + s3_eqn2);
            c[num_elem * n_p * 2 + i * num_elem + idx] += 1. / register_J * dt * (quad_rhs[num_elem * n_p * 2 + i * num_elem + idx] + s1_eqn3 + s2_eqn3 + s3_eqn3);
            c[num_elem * n_p * 3 + i * num_elem + idx] += 1. / register_J * dt * (quad_rhs[num_elem * n_p * 3 + i * num_elem + idx] + s1_eqn4 + s2_eqn4 + s3_eqn4);
        }
    }
}

// forward eulers
void time_integrate_fe(double dt, int n_quad, int n_quad1d, int n_p, int n, 
              int num_elem, int num_sides, int timesteps) {
    int n_threads = 256;
    int i;
    double t;

    int n_blocks_elem    = (num_elem  / n_threads) + ((num_elem  % n_threads) ? 1 : 0);
    int n_blocks_sides   = (num_sides / n_threads) + ((num_sides % n_threads) ? 1 : 0);

    void (*eval_surface_ftn)(double*, double*, 
                         double*, double*,
                         double*, double*,
                         double*, double*,
                         double*, double*,
                         int*, int*,
                         int*, int*,
                         double*, double*,
                         int, int, int, int, int, double) = NULL;
    void (*eval_volume_ftn)(double*, double*, 
                        double*, double*, 
                        double*, double*,
                        int, int, int) = NULL;

    dispatch_functions(eval_surface_ftn, eval_volume_ftn, n);

    if ((eval_surface_ftn == NULL) || (eval_volume_ftn == NULL)) {
        printf("ERROR: dispatched kernel functions in fe were NULL.\n");
        exit(0);
    }

    for (i = 0; i < timesteps; i++) {
        t = i * dt;
        eval_surface_ftn<<<n_blocks_sides, n_threads>>>
                        (d_c, d_left_riemann_rhs, d_right_riemann_rhs, 
                         d_s_length, 
                         d_V1x, d_V1y,
                         d_V2x, d_V2y,
                         d_V3x, d_V3y,
                         d_left_elem, d_right_elem,
                         d_left_side_number, d_right_side_number,
                         d_Nx, d_Ny, 
                         n_quad1d, n_quad, n_p, num_sides, num_elem, t);
        cudaThreadSynchronize();

        checkCudaError("error after eval_surface");

        eval_volume_ftn<<<n_blocks_elem, n_threads>>>
                        (d_c, d_quad_rhs, 
                         d_xr, d_yr, d_xs, d_ys,
                         n_quad, n_p, num_elem);
        cudaThreadSynchronize();

        eval_rhs_fe<<<n_blocks_elem, n_threads>>>(d_c, d_quad_rhs, d_left_riemann_rhs, d_right_riemann_rhs, 
                                              d_elem_s1, d_elem_s2, d_elem_s3, 
                                              d_left_elem, d_J, dt, n_p, num_sides, num_elem);
        cudaThreadSynchronize();
    }
}
