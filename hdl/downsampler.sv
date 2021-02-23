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
    input   wire    signed  [DATA_WIDTH_INP - 1:0]  s_axis_in_tdata,
    input                   s_axis_in_tvalid,
    output  reg     signed  [DATA_WIDTH_INP - 1:0]  m_axis_out_tdata,
    output  reg             m_axis_out_tvalid
);
/*********************************************************************************************/
localparam DECIM_COUNTER_WIDTH = $clog2(CIC_R);
reg [DECIM_COUNTER_WIDTH - 1 : 0] counter;
/*********************************************************************************************/
// decimation counter
always @(posedge clk)
begin
    if (!reset_n)           counter <= '0;
    else if (s_axis_in_tvalid)  counter <= (32'(counter) < CIC_R - 1) ? counter + {{(DECIM_COUNTER_WIDTH - 1){1'b0}}, 1'b1} : '0;
end
/*********************************************************************************************/
// output register
always @(posedge clk)
begin
    if (!reset_n)           m_axis_out_tdata <= '0;
    else if (s_axis_in_tvalid)  m_axis_out_tdata <= (32'(counter) < CIC_R - 1) ? m_axis_out_tdata : s_axis_in_tdata;
end
/*********************************************************************************************/
// data valid register
always @(posedge clk)
begin
    if (!reset_n)           m_axis_out_tvalid <= 1'b0;
    else if (s_axis_in_tvalid)  m_axis_out_tvalid <= (32'(counter) == CIC_R - 1);
    else                    m_axis_out_tvalid <= 1'b0;
end
/*********************************************************************************************/
endmodule