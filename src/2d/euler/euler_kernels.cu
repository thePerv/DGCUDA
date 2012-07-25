/* 2dadvec_kernels_euler.cu
 *
 * This file contains the kernels for the 2D euler DG method.
 *
 * d_t [   rho   ] + d_x [     rho * u    ] + d_y [    rho * v     ] = 0
 * d_t [ rho * u ] + d_x [ rho * u^2 + p  ] + d_y [   rho * u * v  ] = 0
 * d_t [ rho * v ] + d_x [  rho * u * v   ] + d_y [  rho * v^2 + p ] = 0
 * d_t [    E    ] + d_x [ u * ( E +  p ) ] + d_y [ v * ( E +  p ) ] = 0
 *

 */

#define PI 3.14159
#define GAMMA 1.4

/***********************
 *
 * DEVICE VARIABLES
 *
 ***********************/
/* These are always prefixed with d_ for "device" */
double *d_c;                 // coefficients for [rho, rho * u, rho * v, E]
double *d_quad_rhs;          // the right hand side containing the quadrature contributions
double *d_left_riemann_rhs;  // the right hand side containing the left riemann contributions
double *d_right_riemann_rhs; // the right hand side containing the right riemann contributions

// TODO: switch to low storage runge-kutta
// runge kutta variables
double *d_kstar;
double *d_k1;
double *d_k2;
double *d_k3;
double *d_k4;

// precomputed basis functions 
// TODO: maybe making these 2^n makes sure the offsets are cached more efficiently? who knows...
// precomputed basis functions ordered like so
//
// [phi_1(r1, s1), phi_1(r2, s2), ... , phi_1(r_nq, s_nq)   ]
// [phi_2(r1, s1), phi_2(r2, s2), ... , phi_2(r_nq, s_nq)   ]
// [   .               .           .            .           ]
// [   .               .           .            .           ]
// [   .               .           .            .           ]
// [phi_np(r1, s1), phi_np(r2, s2), ... , phi_np(r_nq, s_nq)]
//
__device__ __constant__ double basis[2048];
// note: these are multiplied by the weights
__device__ __constant__ double basis_grad_x[2048]; 
__device__ __constant__ double basis_grad_y[2048]; 

// precomputed basis functions evaluated along the sides. ordered
// similarly to basis and basis_grad_{x,y} but with one "matrix" for each side
// starting with side 0. to get to each side, offset with:
//      side_number * n_p * num_quad1d.
__device__ __constant__ double basis_side[1024];
__device__ __constant__ double basis_vertex[256];

// weights for 2d and 1d quadrature rules
__device__ __constant__ double w[32];
__device__ __constant__ double w_oned[16];

__device__ __constant__ double r1[32];
__device__ __constant__ double r2[32];
__device__ __constant__ double r_oned[32];

void set_basis(void *value, int size) {
    cudaMemcpyToSymbol("basis", value, size * sizeof(double));
}
void set_basis_grad_x(void *value, int size) {
    cudaMemcpyToSymbol("basis_grad_x", value, size * sizeof(double));
}
void set_basis_grad_y(void *value, int size) {
    cudaMemcpyToSymbol("basis_grad_y", value, size * sizeof(double));
}
void set_basis_side(void *value, int size) {
    cudaMemcpyToSymbol("basis_side", value, size * sizeof(double));
}
void set_basis_vertex(void *value, int size) {
    cudaMemcpyToSymbol("basis_vertex", value, size * sizeof(double));
}
void set_w(void *value, int size) {
    cudaMemcpyToSymbol("w", value, size * sizeof(double));
}
void set_w_oned(void *value, int size) {
    cudaMemcpyToSymbol("w_oned", value, size * sizeof(double));
}
void set_r1(void *value, int size) {
    cudaMemcpyToSymbol("r1", value, size * sizeof(double));
}
void set_r2(void *value, int size) {
    cudaMemcpyToSymbol("r2", value, size * sizeof(double));
}
void set_r_oned(void *value, int size) {
    cudaMemcpyToSymbol("r_oned", value, size * sizeof(double));
}

// tells which side (1, 2, or 3) to evaluate this boundary integral over
int *d_left_side_number;
int *d_right_side_number;

double *d_J;        // jacobian determinant 
double *d_min_J;      // for the min sized jacobian
double *d_s_length; // length of sides

// the num_elem values of the x and y coordinates for the two vertices defining a side
// TODO: can i delete these after the lengths are precomputed?
//       maybe these should be in texture memory?
double *d_s_V1x;
double *d_s_V1y;
double *d_s_V2x;
double *d_s_V2y;

// the num_elem values of the x and y partials
double *d_xr;
double *d_yr;
double *d_xs;
double *d_ys;

// the K indices of the sides for each element ranged 0->H-1
int *d_elem_s1;
int *d_elem_s2;
int *d_elem_s3;

// vertex x and y coordinates on the mesh which define an element
// TODO: can i delete these after the jacobians are precomputed?
//       maybe these should be in texture memory?
double *d_V1x;
double *d_V1y;
double *d_V2x;
double *d_V2y;
double *d_V3x;
double *d_V3y;

// stores computed values at three vertices
double *d_Uv1;
double *d_Uv2;
double *d_Uv3;

// normal vectors for the sides
double *d_Nx;
double *d_Ny;

// index lists for sides
int *d_left_elem;  // index of left  element for side idx
int *d_right_elem; // index of right element for side idx

/***********************
 *
 * DEVICE FUNCTIONS
 *
 ***********************/
/* riemann solver
 *
 * evaluates the riemann problem over the boundary using Gaussian quadrature
 * with Legendre polynomials as basis functions.
 */
__device__ double riemann(double u_left, double u_right) {
    return 0.5 * (u_left + u_right);
}

__device__ double pressure(double rho, double u, double v, double E) {
    return (GAMMA - 1) * (E - (u*u + v*v) / 2 * rho);
}

/***********************
 *
 * INITIAL CONDITIONS
 *
 ***********************/

/* initial condition function
 *
 * returns the value of the intial condition at point x
 */
__device__ double rho0(double x, double y) {
    return 2. + x ;
}
__device__ double u0(double x, double y) {
    return 1.;
}
__device__ double v0(double x, double y) {
    return 1.;
}
__device__ double E0(double x, double y) {
    return 1. / (GAMMA - 1) + (powf(u0(x, y), 2) + powf(v0(x, y), 2)) / 2. * rho0(x, y);
}

/* boundary exact
 *
 * returns the exact boundary conditions
 */
__device__ double boundary_exact_rho(double x, double y, double t) {
    return rho0(x, y);
}
__device__ double boundary_exact_u(double x, double y, double t) {
    return u0(x, y);
}
__device__ double boundary_exact_v(double x, double y, double t) {
    return v0(x, y);
}
__device__ double boundary_exact_E(double x, double y, double t) {
    return E0(x, y);
}

/* u exact
 *
 * returns the exact value of u for error measurement.
 */
__device__ double uexact(double x, double y, double t) {
    return u0(x, y);
}

/* initial conditions
 *
 * computes the coefficients for the initial conditions
 * THREADS: num_elem
 */
__global__ void init_conditions(double *c, double *J,
                                double *V1x, double *V1y,
                                double *V2x, double *V2y,
                                double *V3x, double *V3y,
                                int n_quad, int n_p, int num_elem) {
    int idx = blockDim.x * blockIdx.x + threadIdx.x;
    int i, j;
    double x, y, rho, u, v, E;

    if (idx < num_elem) {
        for (i = 0; i < n_p; i++) {
            rho = 0.;
            u = 0.;
            v = 0.;
            E = 0.;
            // perform quadrature
            for (j = 0; j < n_quad; j++) {
                // map from the canonical element to the actual point on the mesh
                // x = x2 * r + x3 * s + x1 * (1 - r - s)
                x = r1[j] * V2x[idx] + r2[j] * V3x[idx] + (1 - r1[j] - r2[j]) * V1x[idx];
                y = r1[j] * V2y[idx] + r2[j] * V3y[idx] + (1 - r1[j] - r2[j]) * V1y[idx];

                // evaluate rho, u, v, E there
                rho += w[j] * rho0(x, y) * basis[i * n_quad + j];
                u   += w[j] * u0(x, y) * rho0(x, y) * basis[i * n_quad + j];
                v   += w[j] * v0(x, y) * rho0(x, y) * basis[i * n_quad + j];
                E   += w[j] * E0(x, y) * basis[i * n_quad + j];
            }

            c[num_elem * n_p * 0 + i * num_elem + idx] = rho;
            c[num_elem * n_p * 1 + i * num_elem + idx] = u; // we actually calculate and store rho * u
            c[num_elem * n_p * 2 + i * num_elem + idx] = v; // we actually calculate and store rho * v
            c[num_elem * n_p * 3 + i * num_elem + idx] = E;
        } 
    }
}

/* find min jacobian
 *
 * returns the min jacobian inside of min_J. 
 * each block computes the min jacobian inside of that block and stores it in the
 * blockIdx.x spot of the shared min_J variable.
 * NOTE: this is fixed for 256 threads.
 */
__global__ void min_jacobian(double *J, double *min_J, int num_elem) {
    int idx = blockDim.x * blockIdx.x + threadIdx.x;
    int tid = threadIdx.x;
    int i   = (blockIdx.x * 256 * 2) + threadIdx.x;

    __shared__ double s_min[256];

    if (idx < num_elem) {
        // set all of min to J[idx] initially
        s_min[tid] = J[idx];
        __syncthreads();

        // test a few
        while (i < num_elem) {
            s_min[tid] = (s_min[tid] < J[i]) ? s_min[tid] : J[i];
            s_min[tid] = (s_min[tid] < J[i + 256]) ? s_min[tid] : J[i];
            i += gridDim.x * 256 * 2;
            __syncthreads();
        }

        // first half of the warps
        __syncthreads();
        if (tid < 128) {
            s_min[tid] = (s_min[tid] < s_min[tid + 128]) ? s_min[tid] : s_min[tid + 128];
        }

        // first and second warps
        __syncthreads();
        if (tid < 64) {
            s_min[tid] = (s_min[tid] < s_min[tid + 64]) ? s_min[tid] : s_min[tid + 64];
        }

        // unroll last warp
        __syncthreads();
        if (tid < 32) {
            if (blockDim.x >= 64) {
                s_min[tid] = (s_min[tid] < s_min[tid + 32]) ? s_min[tid] : s_min[tid + 32];
            }
            if (blockDim.x >= 32) {
                s_min[tid] = (s_min[tid] < s_min[tid + 16]) ? s_min[tid] : s_min[tid + 16];
            }
            if (blockDim.x >= 16) {
                s_min[tid] = (s_min[tid] < s_min[tid + 8]) ? s_min[tid] : s_min[tid + 8];
            }
            if (blockDim.x >= 8) {
                s_min[tid] = (s_min[tid] < s_min[tid + 4]) ? s_min[tid] : s_min[tid + 4];
            }
            if (blockDim.x >= 4) {
                s_min[tid] = (s_min[tid] < s_min[tid + 2]) ? s_min[tid] : s_min[tid + 2];
            }
            if (blockDim.x >= 2) {
                s_min[tid] = (s_min[tid] < s_min[tid + 1]) ? s_min[tid] : s_min[tid + 1];
            }
        }

        __syncthreads();
        if (tid == 0) {
            min_J[blockIdx.x] = s_min[0];
        }
    }
}

/***********************
 *
 * PRECOMPUTING
 *
 ***********************/

/* side length computer
 *
 * precomputes the length of each side.
 * THREADS: num_sides
 */ 
__global__ void preval_side_length(double *s_length, 
                              double *s_V1x, double *s_V1y, 
                              double *s_V2x, double *s_V2y,
                              int num_sides) {
    int idx = blockDim.x * blockIdx.x + threadIdx.x;

    if (idx < num_sides) {
        // compute and store the length of the side
        s_length[idx] = sqrtf(pow(s_V1x[idx] - s_V2x[idx],2) + pow(s_V1y[idx] - s_V2y[idx],2));
    }
}

/* jacobian computing
 *
 * precomputes the jacobian determinant for each element.
 * THREADS: num_elem
 */
__global__ void preval_jacobian(double *J, 
                           double *V1x, double *V1y, 
                           double *V2x, double *V2y, 
                           double *V3x, double *V3y,
                           int num_elem) {
    int idx = blockDim.x * blockIdx.x + threadIdx.x;

    if (idx < num_elem) {
        double x1, y1, x2, y2, x3, y3;

        // read vertex points
        x1 = V1x[idx];
        y1 = V1y[idx];
        x2 = V2x[idx];
        y2 = V2y[idx];
        x3 = V3x[idx];
        y3 = V3y[idx];

        // calculate jacobian determinant
        // x = x2 * r + x3 * s + x1 * (1 - r - s)
        J[idx] = (x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1);
    }
}

/* evaluate normal vectors
 *
 * computes the normal vectors for each element along each side.
 * THREADS: num_sides
 *
 */
__global__ void preval_normals(double *Nx, double *Ny, 
                          double *s_V1x, double *s_V1y, 
                          double *s_V2x, double *s_V2y,
                          double *V1x, double *V1y, 
                          double *V2x, double *V2y, 
                          double *V3x, double *V3y,
                          int *left_side_number, int num_sides) {

    int idx = blockDim.x * blockIdx.x + threadIdx.x;

    if (idx < num_sides) {
        double x, y, length;
        double sv1x, sv1y, sv2x, sv2y;
    
        sv1x = s_V1x[idx];
        sv1y = s_V1y[idx];
        sv2x = s_V2x[idx];
        sv2y = s_V2y[idx];
    
        // lengths of the vector components
        x = sv2x - sv1x;
        y = sv2y - sv1y;
    
        // normalize
        length = sqrtf(pow(x, 2) + pow(y, 2));

        // store the result
        Nx[idx] = -y / length;
        Ny[idx] =  x / length;
    }
}

__global__ void preval_normals_direction(double *Nx, double *Ny, 
                          double *V1x, double *V1y, 
                          double *V2x, double *V2y, 
                          double *V3x, double *V3y,
                          int *left_elem, int *left_side_number, int num_sides) {

    int idx = blockDim.x * blockIdx.x + threadIdx.x;

    if (idx < num_sides) {
        double new_x, new_y, dot;
        double initial_x, initial_y, target_x, target_y;
        double x, y;
        int left_idx, side;

        // get left side's vertices
        left_idx = left_elem[idx];
        side     = left_side_number[idx];

        // get the normal vector
        x = Nx[idx];
        y = Ny[idx];
    
        // make it point the correct direction by learning the third vertex point
        switch (side) {
            case 0: 
                target_x = V3x[left_idx];
                target_y = V3y[left_idx];
                initial_x = (V1x[left_idx] + V2x[left_idx]) / 2.;
                initial_y = (V1y[left_idx] + V2y[left_idx]) / 2.;
                break;
            case 1:
                target_x = V1x[left_idx];
                target_y = V1y[left_idx];
                initial_x = (V2x[left_idx] + V3x[left_idx]) / 2.;
                initial_y = (V2y[left_idx] + V3y[left_idx]) / 2.;
                break;
            case 2:
                target_x = V2x[left_idx];
                target_y = V2y[left_idx];
                initial_x = (V1x[left_idx] + V3x[left_idx]) / 2.;
                initial_y = (V1y[left_idx] + V3y[left_idx]) / 2.;
                break;
        }

        // create the vector pointing towards the third vertex point
        new_x = target_x - initial_x;
        new_y = target_y - initial_y;

        // find the dot product between the normal and new vectors
        dot = x * new_x + y * new_y;
        
        if (dot > 0) {
            Nx[idx] *= -1;
            Ny[idx] *= -1;
        }
    }
}

__global__ void preval_partials(double *V1x, double *V1y,
                                double *V2x, double *V2y,
                                double *V3x, double *V3y,
                                double *xr,  double *yr,
                                double *xs,  double *ys, int num_elem) {
    int idx = blockDim.x * blockIdx.x + threadIdx.x;
    if (idx < num_elem) {
        // evaulate the jacobians of the mappings for the chain rule
        // x = x2 * r + x3 * s + x1 * (1 - r - s)
        xr[idx] = V2x[idx] - V1x[idx];
        yr[idx] = V2y[idx] - V1y[idx];
        xs[idx] = V3x[idx] - V1x[idx];
        ys[idx] = V3y[idx] - V1y[idx];
    }
}

/***********************
 *
 * MAIN FUNCTIONS
 *
 ***********************/

/* riemann evaluation
 *
 * device function to solve the riemann problem.
 */
__device__ void eval_left_right(double *c_rho_left, double *c_rho_right,
                             double *c_u_left,   double *c_u_right,
                             double *c_v_left,   double *c_v_right,
                             double *c_E_left,   double *c_E_right,
                             double *rho_left, double *u_left, double *v_left, double *E_left,
                             double *rho_right, double *u_right, double *v_right, double *E_right,
                             double v1x, double v1y,
                             double v2x, double v2y,
                             double v3x, double v3y,
                             int j, // j, as usual, is the index of the integration point
                             int left_side, int right_side,
                             int left_idx, int right_idx,
                             int n_p, int n_quad1d,
                             int num_sides, double t) { 

    int i;

    // evaluate rho, u, v, E at the integration points
    *rho_left = 0.;
    *u_left   = 0.;
    *v_left   = 0.;
    *E_left   = 0.;
    *rho_right = 0.;
    *u_right   = 0.;
    *v_right   = 0.;
    *E_right   = 0.;
    
    for (i = 0; i < n_p; i++) {
        *rho_left += c_rho_left[i] * basis_side[left_side * n_p * n_quad1d + i * n_quad1d + j];
        *u_left   += c_u_left[i]   * basis_side[left_side * n_p * n_quad1d + i * n_quad1d + j];
        *v_left   += c_v_left[i]   * basis_side[left_side * n_p * n_quad1d + i * n_quad1d + j];
        *E_left   += c_E_left[i]   * basis_side[left_side * n_p * n_quad1d + i * n_quad1d + j];
    }

    // since we actually have coefficients for rho * u and rho * v
    *u_left = *u_left / *rho_left;
    *v_left = *v_left / *rho_left;

    // make all threads in the first warps be boundary sides
    if (right_idx == -1) {
        double r1_eval, r2_eval;
        double x, y;

        // we need the mapping back to the grid space
        switch (left_side) {
            case 0: 
                r1_eval = 0.5 + 0.5 * r_oned[j];
                r2_eval = 0.;
                break;
            case 1: 
                r1_eval = (1. - r_oned[j]) / 2.;
                r2_eval = (1. + r_oned[j]) / 2.;
                break;
            case 2: 
                r1_eval = 0.;
                r2_eval = 0.5 + 0.5 * r_oned[n_quad1d - 1 - j];
                break;
        }

        // x = x2 * r + x3 * s + x1 * (1 - r - s)
        x = v2x * r1_eval + v3x * r2_eval + v1x * (1 - r1_eval - r2_eval);
        y = v2y * r1_eval + v3y * r2_eval + v1y * (1 - r1_eval - r2_eval);
            
        // deal with the boundary element here
        *rho_right = *rho_left;
        *u_right   = *u_left;
        *v_right   = *v_left;
        *E_right   = *E_left;
        //*rho_right = boundary_exact_rho(x, y, t);
        //*u_right   = boundary_exact_u(x, y, t);
        //*v_right   = boundary_exact_v(x, y, t);
        //*E_right   = boundary_exact_E(x, y, t);

    } else {
        // evaluate the right side at the integration point
        for (i = 0; i < n_p; i++) {
            *rho_right += c_rho_right[i] * basis_side[right_side * n_p * n_quad1d + i * n_quad1d + n_quad1d - 1 - j];
            *u_right   += c_u_right[i]   * basis_side[right_side * n_p * n_quad1d + i * n_quad1d + n_quad1d - 1 - j];
            *v_right   += c_v_right[i]   * basis_side[right_side * n_p * n_quad1d + i * n_quad1d + n_quad1d - 1 - j];
            *E_right   += c_E_right[i]   * basis_side[right_side * n_p * n_quad1d + i * n_quad1d + n_quad1d - 1 - j];
        }

        // again, since we have coefficients for rho * u and rho * v
        *u_right = *u_right / *rho_right;
        *v_right = *v_right / *rho_right;
    }
}

/* surface integral evaluation
 *
 * evaluate all the riemann problems for each element.
 * THREADS: num_sides
 */
/*
 * d_t [   rho   ] + d_x [     rho * u    ] + d_y [    rho * v     ] = 0
 * d_t [ rho * u ] + d_x [ rho * u^2 + p  ] + d_y [   rho * u * v  ] = 0
 * d_t [ rho * v ] + d_x [  rho * u * v   ] + d_y [  rho * v^2 + p ] = 0
 * d_t [    E    ] + d_x [ u * ( E +  p ) ] + d_y [ v * ( E +  p ) ] = 0
 */

/* evaluate c
 *
 * evaulates the speed of sound c
 */
__device__ double eval_c(double rho, double u, double v, double E) {
    return sqrtf(GAMMA * pressure(rho, u, v, E) / rho);
}    

/* evaluate lambda
 *
 * finds the max absolute value of the jacobian for F(u).
 *  |u - c|, |u|, |u + c|
 */
__device__ double eval_lambda(double *c_rho_left, double *c_rho_right,
                             double *c_u_left,   double *c_u_right,
                             double *c_v_left,   double *c_v_right,
                             double *c_E_left,   double *c_E_right,
                             double J, int n_p, int n_quad) {
    double sum1_l, sum2_l, sum3_l;
    double sum1_r, sum2_r, sum3_r;
    double max;
    double rho, u, v, E, c;
    int i, j;

    ////////////////
    // left element 
    ////////////////

    // evaluate u - c
    sum1_l = 0;
    for (j = 0; j < n_quad; j++) {
        // evaluate rho,u,v,E at the integration point
        rho = 0.;
        u   = 0.;
        v   = 0.;
        E   = 0.;
        for (i = 0; i < n_p; i++) {
            rho += c_rho_left[i] * basis[n_quad * i + j];
            u   += c_u_left[i]   * basis[n_quad * i + j];
            v   += c_v_left[i]   * basis[n_quad * i + j];
            E   += c_E_left[i]   * basis[n_quad * i + j];
        }
        u = u / rho;
        v = v / rho;
        // evaluate c at the integration point
        c = eval_c(rho, u, v, E);

        sum1_l += w[j] * (u - c);
    }
    sum1_l = abs(sum1_l);

    // evaluate u
    sum2_l = 0;
    for (j = 0; j < n_quad; j++) {
        // evaluate u at the integration point
        u   = 0.;
        for (i = 0; i < n_p; i++) {
            u   += c_u_left[i]   * basis[n_quad * i + j];
        }
        u = u / rho;

        sum2_l += w[j] * u;
    }

    sum2_l = abs(sum2_l);

    // evaluate u + c
    sum3_l = 0;
    for (j = 0; j < n_quad; j++) {
        // evaluate rho,u,v,E at the integration point
        rho = 0.;
        u   = 0.;
        v   = 0.;
        E   = 0.;
        for (i = 0; i < n_p; i++) {
            rho += c_rho_left[i] * basis[n_quad * i + j];
            u   += c_u_left[i]   * basis[n_quad * i + j];
            v   += c_v_left[i]   * basis[n_quad * i + j];
            E   += c_E_left[i]   * basis[n_quad * i + j];
        }
        u = u / rho;
        v = v / rho;
        // evaluate c at the integration point
        c = eval_c(rho, u, v, E);

        sum3_l += w[j] * (u + c);
    }
    sum3_l = abs(sum3_l);

    ////////////////
    // right element
    ////////////////

    // evaluate u - c
    sum1_r = 0;
    for (j = 0; j < n_quad; j++) {
        // evaluate rho,u,v,E at the integration point
        rho = 0.;
        u   = 0.;
        v   = 0.;
        E   = 0.;
        for (i = 0; i < n_p; i++) {
            rho += c_rho_right[i] * basis[n_quad * i + j];
            u   += c_u_right[i]   * basis[n_quad * i + j];
            v   += c_v_right[i]   * basis[n_quad * i + j];
            E   += c_E_right[i]   * basis[n_quad * i + j];
        }
        u = u / rho;
        v = v / rho;
        // evaluate c at the integration point
        c = eval_c(rho, u, v, E);

        sum1_r += w[j] * (u - c);
    }
    sum1_r = abs(sum1_r);

    // evaluate u
    sum2_r = 0;
    for (j = 0; j < n_quad; j++) {
        // evaluate u at the integration point
        u   = 0.;
        for (i = 0; i < n_p; i++) {
            u   += c_u_right[i]   * basis[n_quad * i + j];
        }
        u = u / rho;

        sum2_r += w[j] * u;
    }

    sum2_r = abs(sum2_r);

    // evaluate u + c
    sum3_r = 0;
    for (j = 0; j < n_quad; j++) {
        // evaluate rho,u,v,E at the integration point
        rho = 0.;
        u   = 0.;
        v   = 0.;
        E   = 0.;
        for (i = 0; i < n_p; i++) {
            rho += c_rho_right[i] * basis[n_quad * i + j];
            u   += c_u_right[i]   * basis[n_quad * i + j];
            v   += c_v_right[i]   * basis[n_quad * i + j];
            E   += c_E_right[i]   * basis[n_quad * i + j];
        }
        u = u / rho;
        v = v / rho;
        // evaluate c at the integration point
        c = eval_c(rho, u, v, E);

        sum3_r += w[j] * (u + c);
    }
    sum3_r = abs(sum3_r);

    max = 0;
    if (sum1_l > max) {
        max = sum1_l;
    }
    if (sum2_l > max) {
        max = sum2_l;
    }
    if (sum3_l > max) {
        max = sum3_l;
    }
    if (sum1_r > max) {
        max = sum1_r;
    }
    if (sum2_r > max) {
        max = sum2_r;
    }
    if (sum3_r > max) {
        max = sum3_r;
    }

    return max / 2 * J;
}

/* evaluate flux
 *
 * takes the actual values of rho, u, v, and E and returns the flux 
 * x and y components. 
 * NOTE: this needs the ACTUAL values for u and v, NOT rho * u, rho * v.
 */
__device__ void eval_flux(double rho, double u, double v, double E, 
                     double *flux_x1, double *flux_y1,
                     double *flux_x2, double *flux_y2,
                     double *flux_x3, double *flux_y3,
                     double *flux_x4, double *flux_y4) {

    // evaluate pressure
    double p = pressure(rho, u, v, E);

    // flux_1 
    *flux_x1 = rho * u;
    *flux_y1 = rho * v;

    // flux_2
    *flux_x2 = rho * u * u + p;
    *flux_y2 = rho * u * v;

    // flux_3
    *flux_x3 = rho * u * v;
    *flux_y3 = rho * v * v + p;

    // flux_4
    *flux_x4 = u * (E + p);
    *flux_y4 = v * (E + p);
}

__device__ void eval_surface(double *c_rho_left, double *c_u_left, double *c_v_left, double *c_E_left,
                             double *c_rho_right, double *c_u_right, double *c_v_right, double *c_E_right,
                             double *left_riemann_rhs, double *right_riemann_rhs, 
                             double len, double J,
                             double v1x, double v1y,
                             double v2x, double v2y,
                             double v3x, double v3y,
                             int left_idx,  int right_idx,
                             int left_side, int right_side, 
                             double nx, double ny, 
                             int n_quad1d, int n_quad, int n_p, int num_sides, 
                             int num_elem, double t, int idx) {
    int i, j;
    double s;
    double lambda;
    double left_sum1, right_sum1;
    double left_sum2, right_sum2;
    double left_sum3, right_sum3;
    double left_sum4, right_sum4;
    double flux_x1_l, flux_x2_l, flux_x3_l, flux_x4_l;
    double flux_x1_r, flux_x2_r, flux_x3_r, flux_x4_r;
    double flux_y1_l, flux_y2_l, flux_y3_l, flux_y4_l;
    double flux_y1_r, flux_y2_r, flux_y3_r, flux_y4_r;
    double rho_left, u_left, v_left, E_left;
    double rho_right, u_right, v_right, E_right;

    // multiply across by the i'th basis function
    for (i = 0; i < n_p; i++) {

        left_sum1  = 0.;
        left_sum2  = 0.;
        left_sum3  = 0.;
        left_sum4  = 0.;
        right_sum1 = 0.;
        right_sum2 = 0.;
        right_sum3 = 0.;
        right_sum4 = 0.;

        for (j = 0; j < n_quad1d; j++) {

            // calculate the left and right values along the surface
            eval_left_right(c_rho_left, c_rho_right,
                            c_u_left,   c_u_right,
                            c_v_left,   c_v_right,
                            c_E_left,   c_E_right,
                            &rho_left, &u_left, &v_left, &E_left,
                            &rho_right, &u_right, &v_right, &E_right,
                            v1x, v1y, v2x, v2y, v3x, v3y,
                            j, left_side, right_side,
                            left_idx, right_idx,
                            n_p, n_quad1d, num_sides, t);

            // calculate the left fluxes
            eval_flux(rho_left, u_left, v_left, E_left,
                      &flux_x1_l, &flux_y1_l, &flux_x2_l, &flux_y2_l,
                      &flux_x3_l, &flux_y3_l, &flux_x4_l, &flux_y4_l);

            // calculate the right fluxes
            eval_flux(rho_right, u_right, v_right, E_right,
                      &flux_x1_r, &flux_y1_r, &flux_x2_r, &flux_y2_r,
                      &flux_x3_r, &flux_y3_r, &flux_x4_r, &flux_y4_r);

            // need these local max values
            lambda = eval_lambda(c_rho_left, c_rho_right,
                                 c_u_left, c_u_right, 
                                 c_v_left, c_v_right, 
                                 c_E_left, c_E_right,
                                 J, n_p, n_quad);
            
            // 1st equation
            s = 0.5 * ((flux_x1_l + flux_x1_r) * nx + (flux_y1_l + flux_y1_r) * ny 
                        + lambda * (rho_left - rho_right));
            left_sum1  += w_oned[j] * s * basis_side[left_side * n_p * n_quad1d + i * n_quad1d + j];
            right_sum1 += w_oned[j] * s * basis_side[right_side * n_p * n_quad1d + i * n_quad1d + n_quad1d - 1 - j];

            // 2nd equation
            s = 0.5 * ((flux_x2_l + flux_x2_r) * nx + (flux_y2_l + flux_y2_r) * ny 
                        + lambda * (u_left - u_right));
            left_sum2  += w_oned[j] * s * basis_side[left_side * n_p * n_quad1d + i * n_quad1d + j];
            right_sum2 += w_oned[j] * s * basis_side[right_side * n_p * n_quad1d + i * n_quad1d + n_quad1d - 1 - j];

            // 3rd equation
            s = 0.5 * ((flux_x3_l + flux_x3_r) * nx + (flux_y3_l + flux_y3_r) * ny 
                        + lambda * (v_left - v_right));
            left_sum3  += w_oned[j] * s * basis_side[left_side * n_p * n_quad1d + i * n_quad1d + j];
            right_sum3 += w_oned[j] * s * basis_side[right_side * n_p * n_quad1d + i * n_quad1d + n_quad1d - 1 - j];

            // 4th equation
            s = 0.5 * ((flux_x4_l + flux_x4_r) * nx + (flux_y4_l + flux_y4_r) * ny 
                        + lambda * (E_left - E_right));
            left_sum4  += w_oned[j] * s * basis_side[left_side * n_p * n_quad1d + i * n_quad1d + j];
            right_sum4 += w_oned[j] * s * basis_side[right_side * n_p * n_quad1d + i * n_quad1d + n_quad1d - 1 - j];
        }

        // store this side's contribution in the riemann rhs vectors
        left_riemann_rhs[num_sides * n_p * 0 + i * num_sides + idx]  = -len / 2 * left_sum1;
        left_riemann_rhs[num_sides * n_p * 1 + i * num_sides + idx]  = -len / 2 * left_sum2;
        left_riemann_rhs[num_sides * n_p * 2 + i * num_sides + idx]  = -len / 2 * left_sum3;
        left_riemann_rhs[num_sides * n_p * 3 + i * num_sides + idx]  = -len / 2 * left_sum4;
        right_riemann_rhs[num_sides * n_p * 0 + i * num_sides + idx] =  len / 2 * right_sum1;
        right_riemann_rhs[num_sides * n_p * 1 + i * num_sides + idx] =  len / 2 * right_sum2;
        right_riemann_rhs[num_sides * n_p * 2 + i * num_sides + idx] =  len / 2 * right_sum3;
        right_riemann_rhs[num_sides * n_p * 3 + i * num_sides + idx] =  len / 2 * right_sum4;
    }
}

/* volume integrals
 *
 * evaluates and adds the volume integral to the rhs vector
 * THREADS: num_elem
 */
__device__ void eval_volume(double *c_rho, double *c_u,
                            double *c_v,   double *c_E,
                            double *quad_rhs, 
                            double x_r, double y_r,
                            double x_s, double y_s,
                            int n_quad, int n_p, int num_elem, int idx) {
    int i, j, k;
    double rho, u, v, E;
    double flux_x1, flux_y1, flux_x2, flux_y2;
    double flux_x3, flux_y3, flux_x4, flux_y4;
    double sum1, sum2, sum3, sum4;

    // evaluate the volume integral for each coefficient
    for (i = 0; i < n_p; i++) {
        sum1 = 0.;
        sum2 = 0.;
        sum3 = 0.;
        sum4 = 0.;
        for (j = 0; j < n_quad; j++) {

            // evaluate rho, u, v, E at the integration point.
            rho = 0.;
            u   = 0.;
            v   = 0.;
            E   = 0.;
            for (k = 0; k < n_p; k++) {
                rho += c_rho[k] * basis[n_quad * k + j];
                u   += c_u[k]   * basis[n_quad * k + j];
                v   += c_v[k]   * basis[n_quad * k + j];
                E   += c_E[k]   * basis[n_quad * k + j];
            }

            // since we actually have coefficients for rho * u, rho * v
            u = u / rho;
            v = v / rho;

            // evaluate flux
            eval_flux(rho, u, v, E,
                 &flux_x1, &flux_y1, &flux_x2, &flux_y2,
                 &flux_x3, &flux_y3, &flux_x4, &flux_y4);
                 
            // Add to the sum
            // [fx fy] * [y_s, -y_r; -x_s, x_r] * [phi_x phi_y]
            sum1 += (  flux_x1 * ( basis_grad_x[n_quad * i + j] * y_s
                                  -basis_grad_y[n_quad * i + j] * y_r)
                     + flux_y1 * (-basis_grad_x[n_quad * i + j] * x_s 
                                 + basis_grad_y[n_quad * i + j] * x_r));
            sum2 += (  flux_x2 * ( basis_grad_x[n_quad * i + j] * y_s
                                  -basis_grad_y[n_quad * i + j] * y_r)
                     + flux_y2 * (-basis_grad_x[n_quad * i + j] * x_s 
                                 + basis_grad_y[n_quad * i + j] * x_r));
            sum3 += (  flux_x3 * ( basis_grad_x[n_quad * i + j] * y_s
                                  -basis_grad_y[n_quad * i + j] * y_r)
                     + flux_y3 * (-basis_grad_x[n_quad * i + j] * x_s 
                                 + basis_grad_y[n_quad * i + j] * x_r));
            sum4 += (  flux_x4 * ( basis_grad_x[n_quad * i + j] * y_s
                                  -basis_grad_y[n_quad * i + j] * y_r)
                     + flux_y4 * (-basis_grad_x[n_quad * i + j] * x_s 
                                 + basis_grad_y[n_quad * i + j] * x_r));
        }

        // store the result
        quad_rhs[num_elem * n_p * 0 + i * num_elem + idx] = sum1;
        quad_rhs[num_elem * n_p * 1 + i * num_elem + idx] = sum2;
        quad_rhs[num_elem * n_p * 2 + i * num_elem + idx] = sum3;
        quad_rhs[num_elem * n_p * 3 + i * num_elem + idx] = sum4;
    }
}

/* evaluate error
 * 
 * evaluates u at the three vertex points for output
 * THREADS: num_elem
 */
__device__ void eval_error(double *c, 
                       double v1x, double v1y,
                       double v2x, double v2y,
                       double v3x, double v3y,
                       double *Uv1, double *Uv2, double *Uv3,
                       int num_elem, int n_p, double t, int idx) {

    int i;
    double uv1, uv2, uv3;

    // calculate values at three vertex points
    uv1 = 0.;
    uv2 = 0.;
    uv3 = 0.;
    for (i = 0; i < n_p; i++) {
        uv1 += c[i] * basis_vertex[i * 3 + 0];
        uv2 += c[i] * basis_vertex[i * 3 + 1];
        uv3 += c[i] * basis_vertex[i * 3 + 2];
    }

    // store result
    Uv1[idx] = uv1 - uexact(v1x, v1y, t);
    Uv2[idx] = uv2 - uexact(v2x, v2y, t);
    Uv3[idx] = uv3 - uexact(v3x, v3y, t);
}

/* evaluate u
 * 
 * evaluates rho and E at the three vertex points for output
 * THREADS: num_elem
 */
__device__ void eval_u(double *c, 
                       double *Uv1, double *Uv2, double *Uv3,
                       int num_elem, int n_p, int idx) {
    int i;
    double uv1, uv2, uv3;

    // calculate values at the integration points
    uv1 = 0.;
    uv2 = 0.;
    uv3 = 0.;
    for (i = 0; i < n_p; i++) {
        uv1 += c[i] * basis_vertex[i * 3 + 0];
        uv2 += c[i] * basis_vertex[i * 3 + 1];
        uv3 += c[i] * basis_vertex[i * 3 + 2];
    }

    // store result
    Uv1[idx] = uv1;
    Uv2[idx] = uv2;
    Uv3[idx] = uv3;
}
/* evaluate u velocity
 * 
 * evaluates u and v at the three vertex points for output
 * THREADS: num_elem
 */
__device__ void eval_u_velocity(double *c, double *c_rho,
                       double *Uv1, double *Uv2, double *Uv3,
                       int num_elem, int n_p, int idx) {
    int i;
    double uv1, uv2, uv3;
    double rhov1, rhov2, rhov3;

    // calculate values at the integration points
    rhov1 = 0.;
    rhov2 = 0.;
    rhov3 = 0.;
    for (i = 0; i < n_p; i++) {
        rhov1 += c_rho[i] * basis_vertex[i * 3 + 0];
        rhov2 += c_rho[i] * basis_vertex[i * 3 + 1];
        rhov3 += c_rho[i] * basis_vertex[i * 3 + 2];
    }

    uv1 = 0.;
    uv2 = 0.;
    uv3 = 0.;
    for (i = 0; i < n_p; i++) {
        uv1 += c[i] * basis_vertex[i * 3 + 0];
        uv2 += c[i] * basis_vertex[i * 3 + 1];
        uv3 += c[i] * basis_vertex[i * 3 + 2];
    }

    uv1 = uv1 / rhov1;
    uv2 = uv2 / rhov2;
    uv3 = uv3 / rhov3;

    // store result
    Uv1[idx] = uv1;
    Uv2[idx] = uv2;
    Uv3[idx] = uv3;
}
