#define nk           200
#define nx           9
#define nz           2
#define nssigmax     2
#define ns           nx*nz*nssigmax
#define nK           50
#define nq           50
#define nmarkup      50
#define tauchenwidth 3.0
#define tol          1e-4
#define outertol     1e-4
#define damp         0.5
#define maxconsec    20
#define maxiter      2000
#define SIMULPERIOD  1000
#define nhousehold   10000
#define kwidth       1.5

/* Includes, system */
#include <fstream>
#include <iostream>
#include <iomanip>
#include <string>

// Includes, Thrust
#include <thrust/for_each.h>
#include <thrust/extrema.h>
#include <thrust/tuple.h>
#include <thrust/reduce.h>
#include <thrust/device_vector.h>
#include <thrust/host_vector.h>
#include <thrust/device_ptr.h>
#include <thrust/iterator/counting_iterator.h>
#include <thrust/iterator/zip_iterator.h>

// Includes, cuda
#include <cublas_v2.h>
#include <curand.h>

// Includes, my own creation
#include "cudatools/include/cudatools.hpp"

// Includes model stuff
#include "invpricemodel.h"

// finds operating profit y-wl at each state given agg rules
struct updateprofit
{
	// Data member
	double *profit, *k_grid, *K_grid, *x_grid, *z_grid, *ssigmax_grid;
	para p;
	aggrules r;

	// Construct this object, create util from _util, etc.
	__host__ __device__
	updateprofit(
		double* profit_ptr,
		double* k_grid_ptr,
		double* K_grid_ptr,
		double* x_grid_ptr,
		double* z_grid_ptr,
		double* ssigmax_grid_ptr,
		para _p,
		aggrules _r
	) {
		profit       = profit_ptr;
		k_grid       = k_grid_ptr;
		K_grid       = K_grid_ptr;
		x_grid       = x_grid_ptr;
		z_grid       = z_grid_ptr;
		ssigmax_grid = ssigmax_grid_ptr;
		p            = _p;
		r            = _r;
	};

	__host__ __device__
	void operator()(int index) {
		// Perform ind2sub
		int i_s = index/(nk*nK);
		int i_K = (index-i_s*nk*nK)/(nk);
		int i_k = (index-i_s*nk*nK-i_K*nk)/(1);

		// Find aggregate stuff
		double k = k_grid[i_k];
		double K = K_grid[i_K];
		int i_ssigmax = i_s/(nx*nz);
		int i_z       = (i_s-i_ssigmax*nx*nz)/(nx);
		int i_x       = (i_s-i_ssigmax*nx*nz-i_z*nx)/(1);
		double x       = x_grid[i_x];
		double z       = z_grid[i_z];
		double C = exp( (r.pphi_CC+r.pphi_Czind*i_z+r.pphi_Cssigmaxind*i_ssigmax+r.pphi_Cssigmaxindzind*i_ssigmax*i_z) + (r.pphi_CK+r.pphi_CssigmaxindK*i_ssigmax+r.pphi_CzindK*i_z+r.pphi_CssigmaxindzindK*i_ssigmax*i_z) * log(K) );
		double w = p.ppsi_n*C;

		// Find profit finally
		double l = pow( w/z/x/p.v/pow(k,p.aalpha), 1.0/(p.v-1) );
		profit[index] = z*x*pow(k,p.aalpha)*pow(l,p.v) - w*l;
	};
};

// finds operating profit y-wl at each state given agg rules
struct updateU
{
	// Data member
	double *profit, *k_grid, *K_grid, *x_grid, *z_grid, *ssigmax_grid;
	double *q_grid, *EV;
	double *U, *V;
	para p;
	aggrules r;

	// Construct this object, create util from _util, etc.
	__host__ __device__
	updateU(
		double* profit_ptr,
		double* k_grid_ptr,
		double* K_grid_ptr,
		double* x_grid_ptr,
		double* z_grid_ptr,
		double* ssigmax_grid_ptr,
		double* q_grid_ptr,
		double* EV_ptr,
		double* U_ptr,
		double* V_ptr,
		para _p,
		aggrules _r
	) {
		profit       = profit_ptr;
		k_grid       = k_grid_ptr;
		K_grid       = K_grid_ptr;
		x_grid       = x_grid_ptr;
		z_grid       = z_grid_ptr;
		ssigmax_grid = ssigmax_grid_ptr;
		q_grid       = q_grid_ptr;
		EV           = EV_ptr,
		U            = U_ptr,
		V            = V_ptr,
		p            = _p;
		r            = _r;
	};

	__host__ __device__
	void operator()(int index) {
		// Perform ind2sub
		int i_s = index/(nk*nK);
		int i_K = (index-i_s*nk*nK)/(nk);
		int i_k = (index-i_s*nk*nK-i_K*nk)/(1);

		// Find aggregate stuff
		double k = k_grid[i_k];
		double K = K_grid[i_K];
		int i_ssigmax = i_s/(nx*nz);
		int i_z       = (i_s-i_ssigmax*nx*nz)/(nx);
		double C = exp( (r.pphi_CC+r.pphi_Czind*i_z+r.pphi_Cssigmaxind*i_ssigmax+r.pphi_Cssigmaxindzind*i_ssigmax*i_z) + (r.pphi_CK+r.pphi_CssigmaxindK*i_ssigmax+r.pphi_CzindK*i_z+r.pphi_CssigmaxindzindK*i_ssigmax*i_z) * log(K) );
		double Kplus = exp( (r.pphi_KC+r.pphi_Kzind*i_z+r.pphi_Kssigmaxind*i_ssigmax+r.pphi_Kssigmaxindzind*i_ssigmax*i_z) + (r.pphi_KK+r.pphi_KssigmaxindK*i_ssigmax+r.pphi_KzindK*i_z+r.pphi_KssigmaxindzindK*i_ssigmax*i_z) * log(K) );
		double qplus = exp( (r.pphi_qC+r.pphi_qzind*i_z+r.pphi_qssigmaxind*i_ssigmax+r.pphi_qssigmaxindzind*i_ssigmax*i_z) + (r.pphi_qK+r.pphi_qssigmaxindK*i_ssigmax+r.pphi_qzindK*i_z+r.pphi_qssigmaxindzindK*i_ssigmax*i_z) * log(K) );
		double llambda = 1/C;
		int i_Kplus = fit2grid(Kplus,nK,K_grid);
		int i_qplus = fit2grid(qplus,nq,q_grid);

		// find the indexes of (1-ddelta)*k
		int noinvest_ind = fit2grid((1-p.ddelta)*k,nk,k_grid);
		int i_left, i_right;
		if (noinvest_ind==nk-1) { // (1-ddelta)k>=maxK, then should use K[nk-2] as left point to extrapolate
			i_left = nk-2;
			i_right = nk-1;
		} else {
			i_left = noinvest_ind;
			i_right = noinvest_ind+1;
		};
		double kplus_left  = k_grid[i_left];
		double kplus_right = k_grid[i_right];

		// find EV_noinvest
		double EV_noinvest = linear_interp( (1-p.ddelta)*k, kplus_left, kplus_right, EV[i_left+i_Kplus*nk+i_qplus*nk*nK+i_s*nk*nK*nq], EV[i_right+i_Kplus*nk+i_qplus*nk*nK+i_s*nk*nK*nq]);
		/* double EV_noinvest = EV[noinvest_ind+i_Kplus*nk+i_qplus*nk*nK+i_s*nk*nK*nq]; */

		// Find U finally
		U[index] = llambda*profit[index] + p.bbeta*EV_noinvest;
	};
};

// finds W, and thus V because U is assumed to be computed beforehand!!
struct updateWV
{
	// Data member
	double *profit, *k_grid, *K_grid, *x_grid, *z_grid, *ssigmax_grid;
	double *q_grid, *EV;
	double *W, *U, *V;
	double *Vplus, *kopt;
	int    *active, *koptindplus;
	para p;
	aggrules r;

	// Construct this object, create util from _util, etc.
	__host__ __device__
	updateWV(
		double*  profit_ptr,
		double*  k_grid_ptr,
		double*  K_grid_ptr,
		double*  x_grid_ptr,
		double*  z_grid_ptr,
		double*  ssigmax_grid_ptr,
		double*  q_grid_ptr,
		double*  EV_ptr,
		double*  W_ptr,
		double*  U_ptr,
		double*  V_ptr,
		double*  Vplus_ptr,
		double*  kopt_ptr,
		int*     active_ptr,
		int*     koptindplus_ptr,
		para     _p,
		aggrules _r
	) {
		profit       = profit_ptr;
		k_grid       = k_grid_ptr;
		K_grid       = K_grid_ptr;
		x_grid       = x_grid_ptr;
		z_grid       = z_grid_ptr;
		ssigmax_grid = ssigmax_grid_ptr;
		q_grid       = q_grid_ptr;
		EV           = EV_ptr,
		W            = U_ptr,
		U            = U_ptr,
		V            = V_ptr,
		Vplus        = Vplus_ptr,
		koptindplus  = koptindplus_ptr,
		kopt         = kopt_ptr,
		active       = active_ptr,
		p            = _p;
		r            = _r;
	};

	__host__ __device__
	void operator()(int index) {
		// Perform ind2sub
		int i_s = (index)/(nk*nK*nq);
		int i_q = (index-i_s*nk*nK*nq)/(nk*nK);
		int i_K = (index-i_s*nk*nK*nq-i_q*nk*nK)/(nk);
		int i_k = (index-i_s*nk*nK*nq-i_q*nk*nK-i_K*nk)/(1);

		// Find aggregate stuff
		int i_ssigmax = i_s/(nx*nz);
		int i_z       = (i_s-i_ssigmax*nx*nz)/(nx);
		double k       = k_grid[i_k];
		double K       = K_grid[i_K];
		double q       = q_grid[i_q];
		double C = exp( (r.pphi_CC+r.pphi_Czind*i_z+r.pphi_Cssigmaxind*i_ssigmax+r.pphi_Cssigmaxindzind*i_ssigmax*i_z) + (r.pphi_CK+r.pphi_CssigmaxindK*i_ssigmax+r.pphi_CzindK*i_z+r.pphi_CssigmaxindzindK*i_ssigmax*i_z) * log(K) );
		double Kplus = exp( (r.pphi_KC+r.pphi_Kzind*i_z+r.pphi_Kssigmaxind*i_ssigmax+r.pphi_Kssigmaxindzind*i_ssigmax*i_z) + (r.pphi_KK+r.pphi_KssigmaxindK*i_ssigmax+r.pphi_KzindK*i_z+r.pphi_KssigmaxindzindK*i_ssigmax*i_z) * log(K) );
		double qplus = exp( (r.pphi_qC+r.pphi_qzind*i_z+r.pphi_qssigmaxind*i_ssigmax+r.pphi_qssigmaxindzind*i_ssigmax*i_z) + (r.pphi_qK+r.pphi_qssigmaxindK*i_ssigmax+r.pphi_qzindK*i_z+r.pphi_qssigmaxindzindK*i_ssigmax*i_z) * log(K) );
		double ttheta = exp( (r.pphi_tthetaC+r.pphi_tthetazind*i_z+r.pphi_tthetassigmaxind*i_ssigmax+r.pphi_tthetassigmaxindzind*i_ssigmax*i_z) + (r.pphi_tthetaK+r.pphi_tthetassigmaxindK*i_ssigmax+r.pphi_tthetazindK*i_z+r.pphi_tthetassigmaxindzindK*i_ssigmax*i_z) * log(K) + r.pphi_tthetaq*log(q) );

		double llambda = 1/C;
		double mmu = p.aalpha0*pow(ttheta,p.aalpha1);
		int i_Kplus = fit2grid(Kplus,nK,K_grid);
		int i_qplus = fit2grid(qplus,nq,q_grid);

		// find the indexes of (1-ddelta)*k
		int noinvest_ind = fit2grid((1-p.ddelta)*k,nk,k_grid);
		int i_left_noinv, i_right_noinv;
		if (noinvest_ind == nk-1) { // (1-ddelta)k>=maxK, then should use K[nk-2] as left point to extrapolate
			i_left_noinv = nk-2;
			i_right_noinv = nk-1;
		} else {
			i_left_noinv = noinvest_ind;
			i_right_noinv = noinvest_ind+1;
		};
		double kplus_left_noinv  = k_grid[i_left_noinv];
		double kplus_right_noinv = k_grid[i_right_noinv];

		// find EV_noinvest
		double EV_noinvest = linear_interp( (1-p.ddelta)*k, kplus_left_noinv, kplus_right_noinv, EV[i_left_noinv+i_Kplus*nk+i_qplus*nk*nK+i_s*nk*nK*nq], EV[i_right_noinv+i_Kplus*nk+i_qplus*nk*nK+i_s*nk*nK*nq]);
		/* double EV_noinvest = EV[noinvest_ind+i_Kplus*nk+i_qplus*nk*nK+i_s*nk*nK*nq]; */

		// search through all positve investment level
		double rhsmax = -999999999999999;
		int koptind_active = 0;
		for (int i_kplus = 0; i_kplus < nk; i_kplus++) {
			double convexadj = p.eeta*(k_grid[i_kplus]-(1-p.ddelta)*k)*(k_grid[i_kplus]-(1-p.ddelta)*k)/k;
			double effective_price = (k_grid[i_kplus]>(1-p.ddelta)*k) ? q : p.pphi*q;
			// compute kinda stupidly EV
			double EV_inv = EV[i_kplus+i_Kplus*nk+i_qplus*nk*nK+i_s*nk*nK*nq];
			double candidate = llambda*profit[i_k+i_K*nk+i_s*nk*nK] + mmu*( llambda*(-effective_price)*(k_grid[i_kplus]-(1-p.ddelta)*k) - llambda*convexadj + p.bbeta*EV_inv ) + (1-mmu)*p.bbeta*EV_noinvest;
			if (candidate > rhsmax) {
				rhsmax         = candidate;
				koptind_active = i_kplus;
			};
		};

		// I can find U here
		double U = llambda*profit[i_k+i_K*nk+i_s*nk*nK] + p.bbeta*EV_noinvest;

		// Find W and V finally
		if (rhsmax>U) {
			Vplus[index]       = rhsmax;
			koptindplus[index] = koptind_active;
			active[index]      = 1;
			kopt[index]        = k_grid[koptind_active];
		} else {
			Vplus[index]       = U;
			koptindplus[index] = noinvest_ind;
			active[index]      = 0;
			kopt[index]        = (1-p.ddelta)*k;
		}
	};
};

// finds profit generated from each household i at time t
struct profitfromhh {
	// data members
	double* kopt;
	int*    active;
	double* k_grid;
	double  q;
	double  w;
	double  mmu;
	double* matchshock;
	int     Kind;
	int     qind;
	int     zind;
	int     ssigmaxind;
	int*    kind_sim;
	int*    xind_sim;
	para    p;
	double* profit_temp;

	// constructor
	__host__ __device__
	profitfromhh(
		double* kopt_ptr,
		int*    active_ptr,
		double* k_grid_ptr,
		double  _q,
		double  _w,
		double  _mmu,
		double* matchshock_ptr,
		int     _Kind,
		int     _qind,
		int     _zind,
		int     _ssigmaxind,
		int*    kind_sim_ptr,
		int*    xind_sim_ptr,
		para    _p,
		double* profit_temp_ptr
	) {
		kopt        = kopt_ptr;
		active      = active_ptr;
		k_grid      = k_grid_ptr;
		q           = _q;
		w           = _w;
		mmu         = _mmu;
		matchshock  = matchshock_ptr;
		Kind        = _Kind;
		qind        = _qind;
		zind        = _zind;
		ssigmaxind  = _ssigmaxind;
		kind_sim       = kind_sim_ptr;
		xind_sim       = xind_sim_ptr;
		profit_temp = profit_temp_ptr;
		p           = _p;
	}

	// operator to find profit from each household
	__host__ __device__
	void operator() (int index) {
		int kind = kind_sim[index];
		int xind = xind_sim[index];
		int i_s  = xind + zind*nx + ssigmaxind*nx*nz;
		int i_state = kind + Kind*nk + qind*nk*nK + i_s*nk*nK*nq;
		if (matchshock[index] < mmu) {
			profit_temp[index] = (q-w)*double(active[i_state])*(kopt[i_state]-(1-p.ddelta)*k_grid[kind])/nhousehold;
		} else {
			profit_temp[index] = 0;
		};
	};
};

// finds profit generated from each household i at time t
struct simulateforward {
	// data members
	double* kopt;
	int*    koptind;
	int*    active;
	double* k_grid;
	double* z_grid;
	double* x_grid;
	double  q;
	double  w;
	double  mmu;
	double* matchshock;
	int     Kind;
	int     qind;
	int     zind;
	int     ssigmaxind;
	int*    kind_sim;
	double* k_sim;
	int*    xind_sim;
	double* clist;
	int*    activelist;
	para    p;

	// constructor
	__host__ __device__
	simulateforward(
		double* kopt_ptr,
		int*    koptind_ptr,
		int*    active_ptr,
		double* k_grid_ptr,
		double* z_grid_ptr,
		double* x_grid_ptr,
		double  _q,
		double  _w,
		double  _mmu,
		double* matchshock_ptr,
		int     _Kind,
		int     _qind,
		int     _zind,
		int     _ssigmaxind,
		int*    kind_sim_ptr,
		double* k_sim_ptr,
		int*    xind_sim_ptr,
		double* clist_ptr,
		int*    activelist_ptr,
		para    _p
	) {
		kopt       = kopt_ptr;
		koptind    = koptind_ptr;
		active     = active_ptr;
		k_grid     = k_grid_ptr;
		z_grid     = z_grid_ptr;
		x_grid     = x_grid_ptr;
		q          = _q;
		w          = _w;
		mmu        = _mmu;
		matchshock = matchshock_ptr;
		Kind       = _Kind;
		qind       = _qind;
		zind       = _zind;
		ssigmaxind = _ssigmaxind;
		kind_sim   = kind_sim_ptr;
		k_sim      = k_sim_ptr;
		xind_sim   = xind_sim_ptr;
		clist      = clist_ptr;
		activelist = activelist_ptr;
		p          = _p;
	}

	// operator to find profit from each household
	__host__ __device__
	void operator() (int index) {
		int kind    = kind_sim[index];
		double k    = k_grid[kind];
		int xind    = xind_sim[index];
		int i_s     = xind + zind*nx + ssigmaxind*nx*nz;
		int i_state = kind + Kind*nk + qind*nk*nK + i_s*nk*nK*nq;
		if (matchshock[index] < mmu && active[i_state] == 1) {
			kind_sim[index+nhousehold] = koptind[i_state];
			k_sim[index+nhousehold] = k_grid[kind_sim[index+nhousehold]];
		} else {
			int noinvest_ind = fit2grid((1-p.ddelta)*k,nk,k_grid);
			kind_sim[index+nhousehold] = noinvest_ind;
			k_sim[index+nhousehold] = (1-p.ddelta)*k;
		};
		double z = z_grid[zind];
		double x = x_grid[xind];
		double l = pow( w/z/x/p.v/pow(k,p.aalpha), 1.0/(p.v-1) );
		clist[index] = z*x*pow(k,p.aalpha)*pow(l,p.v);
		activelist[index] = active[i_state];
	};
};

// This unctor calculates the distance
struct myDist {
	// Tple is (V1low,Vplus1low,V1high,Vplus1high,...)
	template <typename Tuple>
	__host__ __device__
	double operator()(Tuple t)
	{
		return abs(thrust::get<0>(t)-thrust::get<1>(t));
	}
};

int main(int argc, char ** argv)
{
	// Select Device from the first argument of main
	int num_devices;
	cudaGetDeviceCount(&num_devices);
	if (argc > 1) {
		int gpu = min(num_devices,atoi(argv[1]));
		cudaSetDevice(gpu);
	};

	// set parameters
	para p; // in #include "invpricemodel.h"
	p.bbeta        = 0.99;
	p.ttau         = 0.1;
	p.aalpha       = 0.25;
	p.v            = 0.5;
	p.ddelta       = .1/double(4);
	p.pphi         = 0.000000;
	p.MC           = 1;
	p.rrhox        = 0.95;
	p.ppsi         = -100000000000.00;
	p.rrhoz        = p.rrhox;
	p.ssigmaz      = 0.01;
	p.ssigmax_low  = 0.04;
	p.ssigmax_high = 0.04*3;
	p.ppsi_n       = 1;
	p.aalpha0      = 0.95;
	p.aalpha1      = 0.01;
	p.eeta         = 0.1;
	p.Pssigmax[0] = 0.95; p.Pssigmax[2] = 0.05;
	p.Pssigmax[1] = 0.08; p.Pssigmax[3] = 0.92;

	// Create all STATE, SHOCK grids here
	h_vec_d h_k_grid(nk,0.0);
	h_vec_d h_K_grid(nK,0.0);
	h_vec_d h_z_grid(nz,0.0);
	h_vec_d h_x_grid(nx,0.0);
	h_vec_d h_ssigmax_grid(nssigmax,0.0);
	h_vec_d h_q_grid(nq,0.0);
	h_vec_d h_markup_grid(nmarkup,0.0);
	h_vec_d h_logZ(nz,0.0);
	h_vec_d h_logX(nx,0.0);
	h_vec_d h_PZ(nz*nz, 0.0);
	h_vec_d h_PX_low(nx*nx, 0.0);
	h_vec_d h_PX_high(nx*nx, 0.0);
	h_vec_d h_P(ns*ns, 0.0);
	h_vec_d h_V(nk*ns*nK*nq,0.0);
	h_vec_d h_Vplus(nk*ns*nK*nq,0.0);
	h_vec_d h_W(nk*ns*nK*nq,0.0);
	h_vec_d h_U(nk*ns*nK,0.0);
	h_vec_d h_EV(nk*ns*nK*nq,0.0);
	h_vec_d h_profit(nk*ns*nK,0.0);
	h_vec_i h_koptind(nk*ns*nK*nq,0);
	h_vec_i h_koptindplus(nk*ns*nK*nq,0);
	h_vec_d h_kopt(nk*ns*nK*nq,0.0);
	h_vec_i h_active(nk*ns*nK*nq,0);

	load_vec(h_V,"./results/Vgrid.csv"); // in #include "cuda_helpers.h"

	// Create capital grid
	double maxK = 70.0;
	double minK = 0.5;
	/* for (int i_k = 0; i_k < nk; i_k++) { */
	/* 	h_k_grid[i_k] = maxK*pow(1-p.ddelta,nk-1-i_k); */
	/* }; */
	linspace(minK,maxK,nk,thrust::raw_pointer_cast(h_k_grid.data())); // in #include "cuda_helpers.h" */
	linspace(h_k_grid[0],h_k_grid[nk-1],nK,thrust::raw_pointer_cast(h_K_grid.data())); // in #include "cuda_helpers.h"

	// Create TFP grids and transition matrix
	h_ssigmax_grid[0] = p.ssigmax_low;
	h_ssigmax_grid[1] = p.ssigmax_high;
	double* h_logZ_ptr = thrust::raw_pointer_cast(h_logZ.data());
	double* h_PZ_ptr   = thrust::raw_pointer_cast(  h_PZ.data());
	/* tauchen(p.rrhoz, p.ssigmaz, h_logZ, h_PZ, tauchenwidth); // in #include "cuda_helpers.h" */
	/* for (int i_z = 0; i_z < nz; i_z++) { */
	/* 	h_z_grid[i_z] = exp(h_logZ[i_z]); */
	/* }; */
	h_z_grid[0] = 0.99; h_z_grid[1] = 1.01;
	h_PZ[0] = 0.875;   h_PZ[2] = 1-0.875;
	h_PZ[1] = 1-0.875; h_PZ[3] = 0.875;

	// create idio prod grid and transition
	double* h_logX_ptr    = thrust::raw_pointer_cast(h_logX   .data());
	double* h_PX_low_ptr  = thrust::raw_pointer_cast(h_PX_low .data());
	double* h_PX_high_ptr = thrust::raw_pointer_cast(h_PX_high.data());
	tauchen(           p.rrhox, p.ssigmax_high, h_logX, h_PX_high, tauchenwidth); // in #include "cuda_helpers.h"
	tauchen_givengrid( p.rrhox, p.ssigmax_low,  h_logX, h_PX_low,  tauchenwidth); // in #include "cuda_helpers.h"
	for (int i_x = 0; i_x < nx; i_x++) {
		h_x_grid[i_x] = exp(h_logX[i_x]);
	};

	// find combined transition matrix P
	for (int i_s = 0; i_s < ns; i_s++) {
		int i_ssigmax = i_s/(nx*nz);
		int i_z       = (i_s-i_ssigmax*nx*nz)/(nx);
		int i_x       = (i_s-i_ssigmax*nx*nz-i_z*nx)/(1);
		for (int i_splus = 0; i_splus < ns; i_splus++) {
			int i_ssigmaxplus = i_splus/(nx*nz);
			int i_zplus       = (i_splus-i_ssigmaxplus*nx*nz)/(nx);
			int i_xplus       = (i_splus-i_ssigmaxplus*nx*nz-i_zplus*nx)/(1);
			if (i_ssigmaxplus==0) {
				h_P[i_s+i_splus*ns] = h_PX_low[i_x+i_xplus*nx]*h_PZ[i_z+i_zplus*nz]* p.Pssigmax[i_ssigmax+i_ssigmaxplus*nssigmax];
			} else {
				h_P[i_s+i_splus*ns] = h_PX_high[i_x+i_xplus*nx]*h_PZ[i_z+i_zplus*nz]*p.Pssigmax[i_ssigmax+i_ssigmaxplus*nssigmax];
			}
		};
	};

	// find cdf on host then transfer to device
	cudavec<double> CDF_z(nz*nz,0);                   pdf2cdf(h_PZ_ptr,nz,CDF_z.hptr);                   CDF_z.h2d();
	cudavec<double> CDF_ssigmax(nssigmax*nssigmax,0); pdf2cdf(p.Pssigmax,nssigmax,CDF_ssigmax.hptr); CDF_ssigmax.h2d();
	cudavec<double> CDF_x_low(nx*nx,0);               pdf2cdf(h_PX_low_ptr,nx,CDF_x_low.hptr);           CDF_x_low.h2d();
	cudavec<double> CDF_x_high(nx*nx,0);              pdf2cdf(h_PX_high_ptr,nx,CDF_x_high.hptr);         CDF_x_high.h2d();

	// Create pricing grids
	double minq = 0.8;
	double maxq = 3.0;
	double minmarkup = 1.0;
	double maxmarkup = 1.6;
	linspace(minq,maxq,nq,thrust::raw_pointer_cast(h_q_grid.data())); // in #include "cuda_helpers.h"
	linspace(minmarkup,maxmarkup,nmarkup,thrust::raw_pointer_cast(h_markup_grid.data())); // in #include "cuda_helpers.h"

	// set initial agg rules
	aggrules r;
	r.pphi_qC = log(1.01); // constant term
	r.pphi_qzind = 0; // w.r.t agg TFP
	r.pphi_qssigmaxind = 0; // w.r.t uncertainty
	r.pphi_qssigmaxindzind = 0; // w.r.t uncertainty
	r.pphi_qK = 0; // w.r.t agg K
	r.pphi_qssigmaxindK = 0; // w.r.t agg K
	r.pphi_qzindK = 0; // w.r.t agg K
	r.pphi_qssigmaxindzindK = 0; // w.r.t agg K

	r.pphi_KC = log(1); // constant term
	r.pphi_Kzind = 0; // w.r.t agg TFP
	r.pphi_Kssigmaxind = 0; // w.r.t uncertainty
	r.pphi_Kssigmaxindzind = 0; // w.r.t uncertainty
	r.pphi_KK = 0.99; // w.r.t agg K
	r.pphi_KssigmaxindK = 0; // w.r.t agg K
	r.pphi_KzindK = 0; // w.r.t agg K
	r.pphi_KssigmaxindzindK = 0; // w.r.t agg K

	r.pphi_CC = log((maxq+minq)/(maxmarkup+minmarkup)/p.ppsi_n); // constant term
	r.pphi_Czind = 0; // w.r.t agg TFP
	r.pphi_Cssigmaxind = 0; // w.r.t uncertainty
	r.pphi_Cssigmaxindzind = 0; // w.r.t uncertainty
	r.pphi_CK = 0.0; // w.r.t agg K
	r.pphi_CssigmaxindK = 0; // w.r.t agg K
	r.pphi_CzindK = 0; // w.r.t agg K
	r.pphi_CssigmaxindzindK = 0; // w.r.t agg K

	r.pphi_tthetaC = log(0.95); // constant term
	r.pphi_tthetazind = 0; // w.r.t agg TFP
	r.pphi_tthetassigmaxind = 0; // w.r.t uncertainty
	r.pphi_tthetassigmaxindzind = 0; // w.r.t uncertainty
	r.pphi_tthetaK = 0.0; // w.r.t agg K
	r.pphi_tthetassigmaxindK = 0; // w.r.t agg K
	r.pphi_tthetazindK = 0; // w.r.t agg K
	r.pphi_tthetassigmaxindzindK = 0; // w.r.t agg K
	r.pphi_tthetaq = 0.1;// lower q -- more firms invest -- lower ttheta

	r.loadfromfile("./results/aggrules.csv");

	// Copy to the device
	d_vec_d d_k_grid       = h_k_grid;
	d_vec_d d_K_grid       = h_K_grid;
	d_vec_d d_x_grid       = h_x_grid;
	d_vec_d d_z_grid       = h_z_grid;
	d_vec_d d_q_grid       = h_q_grid;
	d_vec_d d_ssigmax_grid = h_ssigmax_grid;
	d_vec_d d_profit       = h_profit;
	d_vec_d d_V            = h_V;
	d_vec_d d_Vplus        = h_Vplus;
	d_vec_d d_W            = h_W;
	d_vec_d d_U            = h_U;
	d_vec_d d_EV           = h_EV;
	d_vec_d d_P            = h_P;
	d_vec_d d_kopt         = h_kopt;
	d_vec_i d_koptind      = h_koptind;
	d_vec_i d_koptindplus  = h_koptindplus;
	d_vec_i d_active       = h_active;

	// Obtain device pointers to be used by cuBLAS
	double* d_k_grid_ptr       = raw_pointer_cast(d_k_grid.data());
	double* d_K_grid_ptr       = raw_pointer_cast(d_K_grid.data());
	double* d_x_grid_ptr       = raw_pointer_cast(d_x_grid.data());
	double* d_z_grid_ptr       = raw_pointer_cast(d_z_grid.data());
	double* d_ssigmax_grid_ptr = raw_pointer_cast(d_ssigmax_grid.data());
	double* d_profit_ptr       = raw_pointer_cast(d_profit.data());
	double* d_q_grid_ptr       = raw_pointer_cast(d_q_grid.data());
	double* d_V_ptr            = raw_pointer_cast(d_V.data());
	double* d_EV_ptr           = raw_pointer_cast(d_EV.data());
	double* d_W_ptr            = raw_pointer_cast(d_W.data());
	double* d_Vplus_ptr        = raw_pointer_cast(d_Vplus.data());
	double* d_U_ptr            = raw_pointer_cast(d_U.data());
	double* d_P_ptr            = raw_pointer_cast(d_P.data());
	double* d_kopt_ptr         = raw_pointer_cast(d_kopt.data());
	int* d_koptind_ptr         = raw_pointer_cast(d_koptind.data());
	int* d_koptindplus_ptr     = raw_pointer_cast(d_koptindplus.data());
	int* d_active_ptr          = raw_pointer_cast(d_active.data());

	// Firstly a virtual index array from 0 to nk*nk*nz
	thrust::counting_iterator<int> begin(0);
	thrust::counting_iterator<int> end(nk*ns*nK*nq);
	thrust::counting_iterator<int> begin_noq(0);
	thrust::counting_iterator<int> end_noq(nk*ns*nK);
	thrust::counting_iterator<int> begin_hh(0);
	thrust::counting_iterator<int> end_hh(nhousehold);

	// generate aggregate shocks
	cudavec<double> innov_z(SIMULPERIOD);
	cudavec<double> innov_ssigmax(SIMULPERIOD);
	cudavec<double> innov_x(nhousehold*SIMULPERIOD);
	cudavec<double> innov_match(nhousehold*SIMULPERIOD);
	curandGenerator_t gen;
	curandCreateGenerator(&gen, CURAND_RNG_PSEUDO_DEFAULT);
	curandSetPseudoRandomGeneratorSeed(gen, 1234ULL);
	curandGenerateUniformDouble(gen, innov_z.dptr,       SIMULPERIOD);
	curandGenerateUniformDouble(gen, innov_ssigmax.dptr, SIMULPERIOD);
	curandGenerateUniformDouble(gen, innov_x.dptr,       nhousehold*SIMULPERIOD);
	curandGenerateUniformDouble(gen, innov_match.dptr,   nhousehold*SIMULPERIOD);
	innov_z.d2h();
	innov_ssigmax.d2h();
	innov_x.d2h();
	curandDestroyGenerator(gen);

	// simulate z and ssigmax index beforehand
	cudavec<int>    zind_sim(SIMULPERIOD,(nz-1)/2);
	cudavec<int>    ssigmaxind_sim(SIMULPERIOD,(nssigmax-1)/2);
	cudavec<int>    xind_sim(nhousehold*SIMULPERIOD,(nx-1)/2);
	cudavec<double> z_sim(SIMULPERIOD,h_z_grid[(nz-1)/2]);
	cudavec<double> ssigmax_sim(SIMULPERIOD,h_ssigmax_grid[(nssigmax-1)/2]);
	for (int t = 1; t < SIMULPERIOD; t++) {
		zind_sim.hptr[t]       = markovdiscrete(zind_sim.hptr[t-1],CDF_z.hptr,nz,innov_z.hptr[t]);
		ssigmaxind_sim.hptr[t] = markovdiscrete(ssigmaxind_sim.hptr[t-1],CDF_ssigmax.hptr,nssigmax,innov_ssigmax.hptr[t]);
		z_sim.hptr[t] = h_z_grid[zind_sim.hptr[t]];
		ssigmax_sim.hptr[t] = h_ssigmax_grid[ssigmaxind_sim.hptr[t]];
		for (int i_household = 0; i_household < nhousehold; i_household++) {
			if (ssigmax_sim.hptr[t-1]==0) {
				xind_sim[i_household+t*nhousehold] = markovdiscrete(xind_sim[i_household+(t-1)*nhousehold],CDF_x_low.hptr,nx,innov_x.hptr[i_household+t*nhousehold]);
			};
			if (ssigmax_sim.hptr[t-1]==1) {
				xind_sim[i_household+t*nhousehold] = markovdiscrete(xind_sim[i_household+(t-1)*nhousehold],CDF_x_high.hptr,nx,innov_x.hptr[i_household+t*nhousehold]);
			};
		};
	};
	zind_sim.h2d();
	ssigmaxind_sim.h2d();
	xind_sim.h2d();
	display_vec(zind_sim);
	display_vec(z_sim);
	display_vec(CDF_z);
	display_vec(CDF_ssigmax);

	// Prepare for cuBLAS things
	cublasHandle_t handle;
	cublasCreate(&handle);
	const double alpha = 1.0;
	const double beta = 0.0;

	// intialize simulaiton records
	cudavec<double> K_sim(SIMULPERIOD,(h_K_grid[0]+h_K_grid[nK-1])/2);
	cudavec<double> Kind_sim(SIMULPERIOD,(nK-1)/2);
	cudavec<double> k_sim(nhousehold*SIMULPERIOD,h_k_grid[(nk-1)/2]);
	cudavec<int>    kind_sim(nhousehold*SIMULPERIOD,(nk-1)/2);
	cudavec<double> profit_temp(nhousehold,0.0);
	cudavec<double> clist(nhousehold,0.0);
	cudavec<int>    activelist(nhousehold,0.0);
	cudavec<int>    qind_sim(SIMULPERIOD,(nq-1)/2);
	cudavec<double> q_sim(SIMULPERIOD,h_q_grid[(nq-1)/2]);
	cudavec<double> C_sim(SIMULPERIOD,0.0);
	cudavec<double> ttheta_sim(SIMULPERIOD,0.0);

	double outer_Rsq=0.0;
	while (outer_Rsq < 0.9) {

		// Create Timer
		cudaEvent_t start, stop;
		cudaEventCreate(&start);
		cudaEventCreate(&stop);
		// Start Timer
		cudaEventRecord(start,NULL);

		// find profit at (i_k,i_s,i_K)
		thrust::for_each(
			begin_noq,
			end_noq,
			updateprofit(
				d_profit_ptr,
				d_k_grid_ptr,
				d_K_grid_ptr,
				d_x_grid_ptr,
				d_z_grid_ptr,
				d_ssigmax_grid_ptr,
				p,
				r
			)
		);

		// vfi begins
		double diff = 10;  int iter = 0; int consec = 0;
		while ((diff>tol)&&(iter<maxiter)&&(consec<maxconsec)){
			// Find EV = V*tran(P), EV is EV(i_kplus,i_Kplus,i_qplus,i_s)
			cublasDgemm(
				handle,
				CUBLAS_OP_N,
				CUBLAS_OP_T,
				nk*nK*nq,
				ns,
				ns,
				&alpha,
				d_V_ptr,
				nk*nK*nq,
				d_P_ptr,
				ns,
				&beta,
				d_EV_ptr,
				nk*nK*nq
			);

			// find W/V currently
			thrust::for_each(
				begin,
				end,
				updateWV(
					d_profit_ptr,
					d_k_grid_ptr,
					d_K_grid_ptr,
					d_x_grid_ptr,
					d_z_grid_ptr,
					d_ssigmax_grid_ptr,
					d_q_grid_ptr,
					d_EV_ptr,
					d_W_ptr,
					d_U_ptr,
					d_V_ptr,
					d_Vplus_ptr,
					d_kopt_ptr,
					d_active_ptr,
					d_koptindplus_ptr,
					p,
					r
				)
			);

			// Find diff
			diff = thrust::transform_reduce(
				thrust::make_zip_iterator(thrust::make_tuple(d_V.begin(),d_Vplus.begin())),
				thrust::make_zip_iterator(thrust::make_tuple(d_V.end()  ,d_Vplus.end())),
				myDist(),
				0.0,
				thrust::maximum<double>()
			);

			// Check how many consecutive periods policy hasn't change
			int policy_diff = thrust::transform_reduce(
				thrust::make_zip_iterator(thrust::make_tuple(d_koptind.begin(),d_koptindplus.begin())),
				thrust::make_zip_iterator(thrust::make_tuple(d_koptind.end()  ,d_koptindplus.end())),
				myDist(),
				0.0,
				thrust::maximum<int>()
			);
			if (policy_diff == 0) {
				consec++;
			} else {
				consec = 0;
			};


			std::cout << "diff is: "<< diff << std::endl;
			std::cout << "consec is: "<< consec << std::endl;

			// update correspondence
			d_V       = d_Vplus;
			d_koptind = d_koptindplus;

			std::cout << ++iter << std::endl;
			std::cout << "=====================" << std::endl;
		};
		// VFI ends //

		// simulation given policies
		for (unsigned int t = 0; t < SIMULPERIOD; t++) {
			// find aggregate K from distribution of k
			K_sim[t] =  thrust::reduce(k_sim.dvec.begin()+t*nhousehold, k_sim.dvec.begin()+nhousehold+t*nhousehold, (double) 0, thrust::plus<double>())/double(nhousehold);
			Kind_sim[t] = fit2grid(K_sim[t],nK,thrust::raw_pointer_cast(h_K_grid.data()));

			// find current wage from aggregate things
			double C = exp( (r.pphi_CC+r.pphi_Czind*zind_sim[t]+r.pphi_Cssigmaxind*ssigmaxind_sim[t]+r.pphi_Cssigmaxindzind*ssigmaxind_sim[t]*zind_sim[t]) + (r.pphi_CK+r.pphi_CssigmaxindK*ssigmaxind_sim[t]+r.pphi_CzindK*zind_sim[t]+r.pphi_CssigmaxindzindK*ssigmaxind_sim[t]*zind_sim[t]) * log(K_sim[t]) );
			double w = p.ppsi_n*C;
			double* matchshock_ptr = thrust::raw_pointer_cast(innov_match.dvec.data()+t*nhousehold);
			int* kindlist_ptr      = thrust::raw_pointer_cast(kind_sim.dvec.data()+t*nhousehold);
			double* klist_ptr      = thrust::raw_pointer_cast(k_sim.dvec.data()+t*nhousehold);
			int* xindlist_ptr      = thrust::raw_pointer_cast(xind_sim.dvec.data()+t*nhousehold);

			// given markup find optimal price for monopolist
			double profitmax = -9999999;
			int i_qmax = 0;
			for (unsigned int i_markup = 0; i_markup < nmarkup; i_markup++) {
				// find current variables
				double q           = h_markup_grid[i_markup]*w;
				int i_q            = fit2grid(q, nq, thrust::raw_pointer_cast(h_q_grid.data()));
				double ttheta_temp = exp( (r.pphi_tthetaC+r.pphi_tthetazind*zind_sim[t]+r.pphi_tthetassigmaxind*ssigmaxind_sim[t]+r.pphi_tthetassigmaxindzind*ssigmaxind_sim[t]*zind_sim[t]) + (r.pphi_tthetaK+r.pphi_tthetassigmaxindK*ssigmaxind_sim[t]+r.pphi_tthetazindK*zind_sim[t]+r.pphi_tthetassigmaxindzindK*ssigmaxind_sim[t]*zind_sim[t]) * log(K_sim[t]) + r.pphi_tthetaq*log(q) );
				double mmu    = p.aalpha0*pow(ttheta_temp,p.aalpha1);

				// compute profit from each hh
				thrust::for_each(
					begin_hh,
					end_hh,
					profitfromhh(
						d_kopt_ptr,
						d_active_ptr,
						d_k_grid_ptr,
						q,
						w,
						mmu,
						matchshock_ptr,
						Kind_sim[t],
						i_q,
						zind_sim.hvec[t],
						ssigmaxind_sim.hvec[t],
						kindlist_ptr,
						xindlist_ptr,
						p,
						profit_temp.dptr
					)
				);

				// sum over profit to find total profit
				double totprofit = thrust::reduce(profit_temp.dvec.begin(), profit_temp.dvec.end(), (double) 0, thrust::plus<double>());
				if (totprofit > profitmax) {
					profitmax = totprofit;
					i_qmax    = i_q;
				};
			}
			qind_sim[t] = i_qmax;
			double qmax = h_q_grid[i_qmax];
			q_sim[t] = qmax;

			// evolution under qmax!
			double ttheta_temp = exp( (r.pphi_tthetaC+r.pphi_tthetazind*zind_sim[t]+r.pphi_tthetassigmaxind*ssigmaxind_sim[t]+r.pphi_tthetassigmaxindzind*ssigmaxind_sim[t]*zind_sim[t]) + (r.pphi_tthetaK+r.pphi_tthetassigmaxindK*ssigmaxind_sim[t]+r.pphi_tthetazindK*zind_sim[t]+r.pphi_tthetassigmaxindzindK*ssigmaxind_sim[t]*zind_sim[t]) * log(K_sim[t]) + r.pphi_tthetaq*log(qmax) ) ;
			double mmu_temp    = p.aalpha0*pow(ttheta_temp,p.aalpha1);
			thrust::for_each(
				begin_hh,
				end_hh,
				simulateforward(
					d_kopt_ptr,
					d_koptind_ptr,
					d_active_ptr,
					d_k_grid_ptr,
					d_z_grid_ptr,
					d_x_grid_ptr,
					qmax,
					w,
					mmu_temp,
					matchshock_ptr,
					Kind_sim[t],
					i_qmax,
					zind_sim.hvec[t],
					ssigmaxind_sim.hvec[t],
					kindlist_ptr,
					klist_ptr,
					xindlist_ptr,
					clist.dptr,
					activelist.dptr,
					p
				)
			);

			// find aggregate C and active ttheta
			C_sim.hptr[t]        = thrust::reduce(clist.dvec.begin(), clist.dvec.end(), (double) 0, thrust::plus<double>())/double(nhousehold);
			int activecount = thrust::reduce(activelist.dvec.begin(), activelist.dvec.end(), (int) 0, thrust::plus<int>());
			if (activecount != 0) {
				ttheta_sim.hptr[t]   = double(nhousehold)/double(activecount);
			} else {
				ttheta_sim.hptr[t]   = 1234567789.0;
			};
		};

		// prepare regressors.
		cudavec<double> constant(SIMULPERIOD,1.0);
		cudavec<double> ssigmaxind(SIMULPERIOD,0);  /// remember we need to use lag ssigmax as uncertainty
		cudavec<double> zind(SIMULPERIOD,0);
		cudavec<double> ssigmaxindzind(SIMULPERIOD,0);  /// remember we need to use lag ssigmax as uncertainty
		cudavec<double> logK(SIMULPERIOD,0);
		cudavec<double> logq(SIMULPERIOD,1.0);
		cudavec<double> logC(SIMULPERIOD,1.0);
		cudavec<double> logttheta(SIMULPERIOD,1.0);
		cudavec<double> ssigmaxindK(SIMULPERIOD,0);
		cudavec<double> zindK(SIMULPERIOD,0);
		cudavec<double> ssigmaxindzindK(SIMULPERIOD,0);
		for (int t = 0; t < SIMULPERIOD; t++) {
			if (t==0) {     /// assuming at time 0 uncertainty is low, meaning ssigma_x at time -1 is low
				ssigmaxindzind[t] = 0;
				ssigmaxind[t] = 0;
			} else {
				ssigmaxind[t] = ssigmaxind_sim[t-1];
				ssigmaxindzind[t] = ssigmaxind[t]*double(zind_sim[t]);
			}
			logK[t] = log(K_sim[t]);
			logq[t] = log(q_sim[t]);
			logC[t] = log(C_sim[t]);
			logttheta[t] = log(ttheta_sim[t]);
			ssigmaxindK[t] = ssigmaxind[t]*logK[t];
			zind[t] = double(zind_sim[t]);
			zindK[t] = zind[t]*logK[t];
			ssigmaxindzindK[t] = ssigmaxind[t]*zind[t]*logK[t];
		};
		double bbeta[9];
		double* X[9];
		X[0] = constant.hptr;
		X[1] = ssigmaxind.hptr;
		X[2] = zind.hptr;
		X[3] = ssigmaxindzind.hptr;
		X[4] = logK.hptr;
		X[5] = ssigmaxindK.hptr;
		X[6] = zindK.hptr;
		X[7] = ssigmaxindzindK.hptr;
		X[8] = logq.hptr;

		// save simulations
		save_vec(K_sim,"./results/K_sim.csv");             // in #include "cuda_helpers.h"
		save_vec(z_sim,"./results/z_sim.csv");             // in #include "cuda_helpers.h"
		save_vec(ssigmax_sim,"./results/ssigmax_sim.csv"); // in #include "cuda_helpers.h"
		save_vec(q_sim,"./results/q_sim.csv");       // in #include "cuda_helpers.h"
		save_vec(C_sim,"./results/C_sim.csv");       // in #include "cuda_helpers.h"
		save_vec(ttheta_sim,"./results/ttheta_sim.csv");       // in #include "cuda_helpers.h"

		// run each regression and report
		double Rsq_K = levelOLS(logK.hptr+1,X,SIMULPERIOD-1,8,bbeta);
		r.pphi_KC               = (1.0-damp)*r.pphi_KC               + damp*bbeta[0];
		r.pphi_Kssigmaxind      = (1.0-damp)*r.pphi_Kssigmaxind      + damp*bbeta[1];
		r.pphi_Kzind            = (1.0-damp)*r.pphi_Kzind            + damp*bbeta[2];
		r.pphi_Kssigmaxindzind  = (1.0-damp)*r.pphi_Kssigmaxindzind  + damp*bbeta[3];
		r.pphi_KK               = (1.0-damp)*r.pphi_KK               + damp*bbeta[4];
		r.pphi_KssigmaxindK     = (1.0-damp)*r.pphi_KssigmaxindK     + damp*bbeta[5];
		r.pphi_KzindK           = (1.0-damp)*r.pphi_KzindK           + damp*bbeta[6];
		r.pphi_KssigmaxindzindK = (1.0-damp)*r.pphi_KssigmaxindzindK + damp*bbeta[7];
		printf("Rsq_K = %.4f, log(Kplus) = (%.2f+%.2f*ssigmaxind_lag+%.2f*zind+%.2f*ssigmaxind_lag*zind) + (%.2f+%.2f*ssigmaxind_lag+%.2f*zind+%.2f*ssigmaxind_lag*zind) * log(K) \n",Rsq_K,r.pphi_KC,r.pphi_Kssigmaxind,r.pphi_Kzind,r.pphi_Kssigmaxindzind,r.pphi_KK,r.pphi_KssigmaxindK,r.pphi_KzindK,r.pphi_KssigmaxindzindK);

		double Rsq_q = levelOLS(logq.hptr+1,X,SIMULPERIOD-1,8,bbeta);
		r.pphi_qC               = (1.0-damp)*r.pphi_qC               + damp*bbeta[0];
		r.pphi_qssigmaxind      = (1.0-damp)*r.pphi_qssigmaxind      + damp*bbeta[1];
		r.pphi_qzind            = (1.0-damp)*r.pphi_qzind            + damp*bbeta[2];
		r.pphi_qssigmaxindzind  = (1.0-damp)*r.pphi_qssigmaxindzind  + damp*bbeta[3];
		r.pphi_qK               = (1.0-damp)*r.pphi_qK               + damp*bbeta[4];
		r.pphi_qssigmaxindK     = (1.0-damp)*r.pphi_qssigmaxindK     + damp*bbeta[5];
		r.pphi_qzindK           = (1.0-damp)*r.pphi_qzindK           + damp*bbeta[6];
		r.pphi_qssigmaxindzindK = (1.0-damp)*r.pphi_qssigmaxindzindK + damp*bbeta[7];
		printf("Rsq_q = %.4f, log(qplus) = (%.2f+%.2f*ssigmaxind_lag+%.2f*zind+%.2f*ssigmaxind_lag*zind) + (%.2f+%.2f*ssigmaxind_lag+%.2f*zind+%.2f*ssigmaxind_lag*zind) * log(K) \n",Rsq_q,r.pphi_qC,r.pphi_qssigmaxind,r.pphi_qzind,r.pphi_qssigmaxindzind,r.pphi_qK,r.pphi_qssigmaxindK,r.pphi_qzindK,r.pphi_qssigmaxindzindK);

		double Rsq_C = levelOLS(logC.hptr,X,SIMULPERIOD,8,bbeta);
		r.pphi_CC               = (1.0-damp)*r.pphi_CC               + damp*bbeta[0];
		r.pphi_Cssigmaxind      = (1.0-damp)*r.pphi_Cssigmaxind      + damp*bbeta[1];
		r.pphi_Czind            = (1.0-damp)*r.pphi_Czind            + damp*bbeta[2];
		r.pphi_Cssigmaxindzind  = (1.0-damp)*r.pphi_Cssigmaxindzind  + damp*bbeta[3];
		r.pphi_CK               = (1.0-damp)*r.pphi_CK               + damp*bbeta[4];
		r.pphi_CssigmaxindK     = (1.0-damp)*r.pphi_CssigmaxindK     + damp*bbeta[5];
		r.pphi_CzindK           = (1.0-damp)*r.pphi_CzindK           + damp*bbeta[6];
		r.pphi_CssigmaxindzindK = (1.0-damp)*r.pphi_CssigmaxindzindK + damp*bbeta[7];
		printf("Rsq_C = %.4f, log(C) = (%.2f+%.2f*ssigmaxind_lag+%.2f*zind+%.2f*ssigmaxind_lag*zind) + (%.2f+%.2f*ssigmaxind_lag+%.2f*zind+%.2f*ssigmaxind_lag*zind) * log(K) \n",Rsq_C,r.pphi_CC,r.pphi_Cssigmaxind,r.pphi_Czind,r.pphi_Cssigmaxindzind,r.pphi_CK,r.pphi_CssigmaxindK,r.pphi_CzindK,r.pphi_CssigmaxindzindK);

		double Rsq_ttheta = levelOLS(logttheta.hptr,X,SIMULPERIOD,9,bbeta);
		r.pphi_tthetaC               = (1.0-damp)*r.pphi_tthetaC               + damp*bbeta[0];
		r.pphi_tthetassigmaxind      = (1.0-damp)*r.pphi_tthetassigmaxind      + damp*bbeta[1];
		r.pphi_tthetazind            = (1.0-damp)*r.pphi_tthetazind            + damp*bbeta[2];
		r.pphi_tthetassigmaxindzind  = (1.0-damp)*r.pphi_tthetassigmaxindzind  + damp*bbeta[3];
		r.pphi_tthetaK               = (1.0-damp)*r.pphi_tthetaK               + damp*bbeta[4];
		r.pphi_tthetassigmaxindK     = (1.0-damp)*r.pphi_tthetassigmaxindK     + damp*bbeta[5];
		r.pphi_tthetazindK           = (1.0-damp)*r.pphi_tthetazindK           + damp*bbeta[6];
		r.pphi_tthetassigmaxindzindK = (1.0-damp)*r.pphi_tthetassigmaxindzindK + damp*bbeta[7];
		r.pphi_tthetaq               = (1.0-damp)*r.pphi_tthetaq               + damp*bbeta[8];
		printf("Rsq_ttheta = %.4f, log(ttheta) = (%.2f+%.2f*ssigmaxind_lag+%.2f*zind+%.2f*ssigmaxind_lag*zind) + (%.2f+%.2f*ssigmaxind_lag+%.2f*zind+%.2f*ssigmaxind_lag*zind) * log(K) + %.2f*log(q) \n",Rsq_ttheta,r.pphi_tthetaC,r.pphi_tthetassigmaxind,r.pphi_tthetazind,r.pphi_tthetassigmaxindzind,r.pphi_tthetaK,r.pphi_tthetassigmaxindK,r.pphi_tthetazindK,r.pphi_tthetassigmaxindzindK,r.pphi_tthetaq);

		outer_Rsq =  min(min(Rsq_K,Rsq_q),min(Rsq_C,Rsq_ttheta));


		// Stop Timer
		cudaEventRecord(stop,NULL);
		cudaEventSynchronize(stop);
		float msecTotal = 0.0;
		cudaEventElapsedTime(&msecTotal, start, stop);

		// Compute and print the performance
		float msecPerMatrixMul = msecTotal;
		std::cout << "Time= " << msecPerMatrixMul/1000 << " secs, iter= " << iter << std::endl;

		// Copy back to host and print to file
		h_V       = d_V;
		h_koptind = d_koptind;
		h_kopt = d_kopt;
		h_active  = d_active;
		h_profit  = d_profit;

		r.savetofile("./results/aggrules.csv");
		save_vec(h_K_grid,"./results/K_grid.csv");         // in #include "cuda_helpers.h"
		save_vec(h_k_grid,"./results/k_grid.csv");         // in #include "cuda_helpers.h"
		save_vec(h_V,"./results/Vgrid.csv");               // in #include "cuda_helpers.h"
		save_vec(h_active,"./results/active.csv");         // in #include "cuda_helpers.h"
		save_vec(h_koptind,"./results/koptind.csv");       // in #include "cuda_helpers.h"
		save_vec(h_kopt,"./results/kopt.csv");             // in #include "cuda_helpers.h"
		std::cout << "Policy functions output completed." << std::endl;
	}


	// Export parameters to MATLAB
	p.exportmatlab("./MATLAB/vfi_para.m");

	// to be safe destroy cuBLAS handle
	cublasDestroy(handle);

	return 0;
}
