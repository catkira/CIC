`timescale 1ns / 1ns
module cic_i
/*********************************************************************************************/
#(parameter dw = 8, r = 4, m = 4, g = 1)
/*********************************************************************************************/
//m - CIC order (comb chain length, integrator chain length)
//r - interpolation ratio
//dw - input data width
//g - differential delay in combs
/*********************************************************************************************/
(
    input   clk,
    input   reset_n,
    input   in_dv,
    input   signed [dw-1:0] data_in,
    output  signed [dw+$clog2((r**(m))/r)-1:0] data_out
);
/*********************************************************************************************/
// Full accumulator width to handle CIC gain without overflow
localparam ACC_DW = dw + m * $clog2(r * g);

// Sign-extend input to ACC_DW
wire signed [ACC_DW-1:0] data_in_ext = {{(ACC_DW-dw){data_in[dw-1]}}, data_in};
/*********************************************************************************************/
genvar  i;
generate
    for (i = 0; i < m; i++) begin:comb_stage
        wire signed [ACC_DW-1:0] comb_in;
        if (i!=0)
            assign comb_in = comb_stage[i-1].comb_out;
        else
            assign comb_in = data_in_ext;
        wire signed [ACC_DW-1:0] comb_out;
        comb #(.SAMP_WIDTH(ACC_DW), .CIC_M(g)) comb_inst(
            .clk(clk), .reset_n(reset_n),
            .samp_inp_data(comb_in), .samp_inp_str(in_dv),
            .samp_out_data(comb_out), .samp_out_str());
    end
endgenerate
/*********************************************************************************************/
wire signed [ACC_DW-1:0] upsample = (in_dv) ? comb_stage[m-1].comb_out : 0;
/*********************************************************************************************/
genvar  j;
generate
    for (j = 0; j < m; j++) begin:int_stage
        wire signed [ACC_DW-1:0] int_in;
        if (j==0)
            assign int_in = upsample;
        else
            assign int_in = int_stage[j-1].int_out;
        wire signed [ACC_DW-1:0] int_out;
        integrator #(.DATA_WIDTH_INP(ACC_DW), .DATA_WIDTH_OUT(ACC_DW)) int_inst(
            .clk(clk), .reset_n(reset_n),
            .inp_samp_data(int_in), .inp_samp_str(1'b1),
            .out_samp_data(int_out), .out_samp_str());
    end
endgenerate
/*********************************************************************************************/
localparam OUT_DW = dw + $clog2((r**(m))/r);
assign data_out = int_stage[m-1].int_out[ACC_DW-1 -: OUT_DW];
/*********************************************************************************************/
endmodule
