`timescale 1ns / 1ns
module integrator
/*********************************************************************************************/
#(parameter DATA_WIDTH_INP = 8 , DATA_WIDTH_OUT = 9, SCALING_FACTOR_WIDTH = 16)
/*********************************************************************************************/
(
    input                                       clk,
    input                                       reset_n,
    input wire signed   [DATA_WIDTH_INP - 1:0]  inp_samp_data,
    input                                       inp_samp_str,
    input unsigned      [SCALING_FACTOR_WIDTH - 1:0]  scaling_factor,
    output wire signed  [DATA_WIDTH_OUT - 1:0]  out_samp_data
);
/*********************************************************************************************/
localparam SUMMER_WIDTH = DATA_WIDTH_INP > DATA_WIDTH_OUT ? DATA_WIDTH_INP : DATA_WIDTH_OUT;
wire    signed  [SUMMER_WIDTH - 1:0]    sum;
reg     signed  [SUMMER_WIDTH - 1:0]    acc_reg;
assign #4       sum = acc_reg + inp_samp_data;  // delay for 18x18 multiplier of Cyclone V SE is 3.4 ns
always @(posedge clk)
begin
    if              (!reset_n)      acc_reg <= '0;
    else    if      (inp_samp_str) begin
        acc_reg <= sum;
    end
end

if (SCALING_FACTOR_WIDTH != 0)
    assign out_samp_data = acc_reg[SUMMER_WIDTH - 1 -: DATA_WIDTH_OUT]  * scaling_factor;
else
    assign out_samp_data = acc_reg[SUMMER_WIDTH - 1 -: DATA_WIDTH_OUT];
/*********************************************************************************************/
endmodule