`timescale 1ns / 1ns

module downsampler_variable
/*********************************************************************************************/
#(
    parameter DATA_WIDTH_INP = 8,
    parameter DATA_WIDTH_RATE = 16
)
/*********************************************************************************************/
(
    input                   clk,
    input                   reset_n,
    input   wire    signed  [DATA_WIDTH_INP - 1:0]  s_axis_in_tdata,
    input                   s_axis_in_tvalid,
    input   wire    signed  [DATA_WIDTH_RATE - 1:0] s_axis_rate_tdata,
    input                   s_axis_rate_tvalid,
    output  reg     signed  [DATA_WIDTH_INP - 1:0]  m_axis_out_tdata,
    output  reg             m_axis_out_tvalid
);
/*********************************************************************************************/
reg [DATA_WIDTH_RATE - 1 : 0] counter;
reg [DATA_WIDTH_RATE - 1 : 0] rate_buf;
/*********************************************************************************************/
always @(posedge clk)
begin
    if (!reset_n)           rate_buf <= '1;
    else if (s_axis_rate_tvalid)  rate_buf <= s_axis_rate_tdata;
end
/*********************************************************************************************/
// decimation counter
always @(posedge clk)
begin
    if (!reset_n || s_axis_rate_tvalid)           counter <= '0;
    else if (s_axis_in_tvalid)  counter <= (counter < rate_buf - 1) ? counter + {{(DATA_WIDTH_RATE - 1){1'b0}}, 1'b1} : '0;
end
/*********************************************************************************************/
// output register
always @(posedge clk)
begin
    if (!reset_n || s_axis_rate_tvalid)           m_axis_out_tdata <= '0;
    else if (s_axis_in_tvalid)  m_axis_out_tdata <= (counter < rate_buf - 1) ? m_axis_out_tdata : s_axis_in_tdata;
end
/*********************************************************************************************/
// data valid register
always @(posedge clk)
begin
    if (!reset_n || s_axis_rate_tvalid)           m_axis_out_tvalid <= 1'b0;
    else if (s_axis_in_tvalid)  m_axis_out_tvalid <= (counter == rate_buf - 1);
    else                    m_axis_out_tvalid <= 1'b0;
end
/*********************************************************************************************/
endmodule