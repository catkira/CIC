`timescale 1ns / 1ns
module integrator
/*********************************************************************************************/
#(
    parameter DATA_WIDTH_INP = 8,
    parameter DATA_WIDTH_OUT = 9,
    parameter USE_DSP = 1
    )
/*********************************************************************************************/
(
    input                                       clk,
    input                                       reset_n,
    input wire signed   [DATA_WIDTH_INP - 1:0]  inp_samp_data,
    input                                       inp_samp_str,
    output wire signed  [DATA_WIDTH_OUT - 1:0]  out_samp_data,
    output reg                                  out_samp_str
);
/*********************************************************************************************/
localparam SUMMER_WIDTH = DATA_WIDTH_INP > DATA_WIDTH_OUT ? DATA_WIDTH_INP : DATA_WIDTH_OUT;
if (USE_DSP) begin : genblk1
    (* use_dsp = "yes" *)   reg     signed  [SUMMER_WIDTH - 1:0]    acc_reg;
end else begin : genblk1
                            reg     signed  [SUMMER_WIDTH - 1:0]    acc_reg;
end
                            
always_ff @(posedge clk)
begin
    if (!reset_n) begin
        genblk1.acc_reg <= 0;
        out_samp_str <= 0;
    end 
    else begin
        genblk1.acc_reg <= inp_samp_str ? genblk1.acc_reg + inp_samp_data : genblk1.acc_reg;
        out_samp_str <= inp_samp_str;
    end
end

assign out_samp_data = genblk1.acc_reg[SUMMER_WIDTH - 1 -: DATA_WIDTH_OUT];
/*********************************************************************************************/
endmodule