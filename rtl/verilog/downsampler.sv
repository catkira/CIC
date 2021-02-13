`timescale 1ns / 1ns

module downsampler
/*********************************************************************************************/
#(
    parameter DATA_WIDTH_INP = 8,
    parameter CIC_R = 4
)
/*********************************************************************************************/
(
    input                   clk,
    input                   reset_n,
    input   wire    signed  [DATA_WIDTH_INP - 1:0]  inp_samp_data,
    input                   inp_samp_str,
    output  reg     signed  [DATA_WIDTH_INP - 1:0]  out_samp_data,
    output  reg             out_samp_str
);
/*********************************************************************************************/
localparam DECIM_COUNTER_WIDTH = $clog2(CIC_R);
reg [DECIM_COUNTER_WIDTH - 1 : 0] counter;
/*********************************************************************************************/
// decimation counter
always @(posedge clk or negedge reset_n)
begin
    if (!reset_n)           counter <= '0;
    else if (inp_samp_str)  counter <= (counter < CIC_R - 1) ? counter + {{(DECIM_COUNTER_WIDTH - 1){1'b0}}, 1'b1} : '0;
end
/*********************************************************************************************/
// output register
always @(posedge clk or negedge reset_n)
begin
    if (!reset_n)           out_samp_data <= '0;
    else if (inp_samp_str)  out_samp_data <= (counter < CIC_R - 1) ? out_samp_data : inp_samp_data;
end
/*********************************************************************************************/
// data valid register
always @(posedge clk or negedge reset_n)
begin
    if (!reset_n)           out_samp_str <= 1'b0;
    else if (inp_samp_str)  out_samp_str <= (counter == CIC_R - 1);
    else                    out_samp_str <= 1'b0;
end
/*********************************************************************************************/
endmodule