`timescale 1ns / 1ns
module integrator
/*********************************************************************************************/
#(parameter DATA_WIDTH_INP = 8 , DATA_WIDTH_OUT = 9)
/*********************************************************************************************/
(
    input                                       clk,
    input                                       reset_n,
    input wire signed   [DATA_WIDTH_INP - 1:0]  inp_samp_data,
    input                                       inp_samp_str,
    output wire signed  [DATA_WIDTH_OUT - 1:0]  out_samp_data,
    input                                       out_samp_str
);
/*********************************************************************************************/
reg             out_samp_str_reg;
always @(posedge clk or negedge reset_n)
begin
    if (!reset_n)           out_samp_str_reg <= '0;
    else                    out_samp_str_reg <= inp_samp_str;
end

assign out_samp_str = out_samp_str_reg;
/*********************************************************************************************/
localparam SUMMER_WIDTH = DATA_WIDTH_INP > DATA_WIDTH_OUT ? DATA_WIDTH_INP : DATA_WIDTH_OUT;
wire    signed  [SUMMER_WIDTH - 1:0]    sum;
reg     signed  [SUMMER_WIDTH - 1:0]    acc_reg;
assign #4       sum = acc_reg + inp_samp_data;  // delay for 18x18 multiplier of Cyclone V SE is 3.4 ns
always @(posedge clk or negedge reset_n)
begin
    if              (!reset_n)      acc_reg <= '0;
    else    if      (inp_samp_str)  acc_reg <= sum;
end

assign out_samp_data = acc_reg[SUMMER_WIDTH - 1 -: DATA_WIDTH_OUT];
/*********************************************************************************************/
endmodule