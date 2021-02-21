/**
 * Library: cic_functions
 * 
 * library with functions for calculating parameters for CIC filter and Hogenauer pruning
 */
`ifndef _CIC_FUNCTIONS_VH_
`define _CIC_FUNCTIONS_VH_
`define M_PI 3.14159265359	// not all simulator defines PI 
 
function reg unsigned [127 : 0] nchoosek;	///< Binomial coefficient
	input   integer n;
	input   integer k;
	reg unsigned [127:0] tmp;
	integer i;
	begin
		tmp = 1.0;
		for (i = 1; i <= (n - k); i = i + 1)
			tmp = tmp * (k + i) / i;
		nchoosek = tmp;
	end
endfunction
 
 
// using $clog2 does not synthesize in vivado 2020.2
function integer clog2_l;
	input reg unsigned [127:0] depth;
	reg unsigned [127:0] i;
	begin
		clog2_l = 0;
		if (depth > 0) begin
			i = depth - 1;	// with "- 1" clog2(2^N) will be N, not N + 1
			for(clog2_l = 0; i > 0; clog2_l = clog2_l + 1)
				i = i >> 1;
		end else
			clog2_l = 0;
	end
endfunction
 
function integer B_max_calc;
	input integer N;
	input integer R;
	input integer M;
	input integer INP_DW;
	reg unsigned [127:0] RMpN;
	begin
		RMpN = (R * M) ** N;
		B_max_calc = clog2_l(RMpN) + INP_DW;
		//$display("B_max_calc: N=%2d, R=%2d, M=%2d, ret=%2d", N, R, M, B_max_calc);
	end
endfunction
 
function integer B_out_calc;
	input integer N;
	input integer R;
	input integer M;
	input integer INP_DW;
	input integer OUT_DW;
	begin
		B_out_calc = B_max_calc(N, R, M, OUT_DW) - B_calc(2 * N, N, R, M, INP_DW, OUT_DW);
	end
endfunction
 
 
function integer flog2_l;
	input reg unsigned [127:0] depth;
	reg unsigned [127:0] i;
	begin
		i = depth;        
		for(flog2_l = 0; i > 1; flog2_l = flog2_l + 1)
			i = i >> 1;
	end
endfunction
 
 
function reg signed [127:0] h_calc;
	input   integer j;
	input   integer k;
	input   integer N;
	input   integer R;
	input   integer M;
	integer c_stop;
	integer i;
	reg signed [127:0] tmp;
	reg signed [127:0] prod_1;
	reg signed [127:0] prod_2;
	reg signed [127:0] summ;
	begin
		c_stop = k / (R * M);
		if ((j >= 1)&&( j<=N )) begin
			tmp = 0;
			for (i = 0; i <= c_stop; i = i + 1) begin
				prod_1 = nchoosek(N, i);
				prod_2 = nchoosek(N - j + k - R * M * i, k - R * M * i);
				summ = prod_1 * prod_2;
				if (i % 2) summ = -summ;
				tmp = tmp + summ;
			end
		end
		else begin
			tmp = nchoosek(2 * N + 1 - j, k);
			if (k % 2) tmp = -tmp;
		end
		h_calc = tmp;
	end
endfunction
 
function reg signed [127:0] F_sq_calc;	///< F()**2
	input   integer j;
	input   integer N;
	input   integer R;
	input   integer M;
	integer c_stop;
	reg signed [127:0] tmp;
	integer i;
	reg signed [127:0] h_jk;
	begin
		tmp = 0;
		if (j <= N)
			c_stop = (((R * M -1 ) * N) + j - 1);
		else
			c_stop = 2 * N + 1 - j;
		for (i = 0;i <= c_stop; i = i + 1) begin
			h_jk = h_calc(j, i, N, R, M);
			tmp = tmp + h_jk ** 2;
		end
		F_sq_calc = tmp;
	end
endfunction
 
function integer B_calc;
	input   integer j;
	input   integer N;
	input   integer R;
	input   integer M;
	input   integer dw_in;
	input   integer dw_out;
	integer B_max;
	reg signed [127:0] sigma_T_2Np1_sq;
	reg signed [127:0] B_2Np1;
	reg signed [127:0] B_exp_real;
	integer B_out;
	reg signed [127:0] F_sq_j;
	reg signed [127:0] F_sq_2Np1;
	begin
		if (j <= 0) begin
			B_calc = 0;
		end else begin
			B_max = B_max_calc(N, R, M, dw_in);
			if (j == 2 * N + 1) begin
				B_calc = B_max - dw_out;
			end else begin
				B_2Np1 = B_max - dw_out;
				F_sq_j = F_sq_calc(j, N, R, M);
				F_sq_2Np1 = F_sq_calc(2 * N + 1, N, R, M);
				sigma_T_2Np1_sq = (128'b1 << (2 * B_2Np1)) * F_sq_2Np1 / 12;
				B_exp_real = (sigma_T_2Np1_sq / F_sq_j * 6 / N);
				B_out = flog2_l(B_exp_real) / 2;
				B_calc = B_out;
			end
		end
	end
endfunction
 
`endif