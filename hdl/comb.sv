`timescale 1ns / 1ns
/**
 * Module: comb
 * 
 * Comb stage for CIC filter
 * There is two variants of realisation.
 * For every stage in the output extra register added for isolation combinatorial logic outside own adder.
 * 
 */
module comb
/*********************************************************************************************/
#(
    parameter       SAMP_WIDTH = 8,
    parameter       CIC_M = 1,
    parameter       USE_DSP = 1
)
/*********************************************************************************************/
(
    input                                                   clk,
    input                                                   reset_n,
    input   wire    signed  [SAMP_WIDTH - 1:0]              samp_inp_data,
    input                                                   samp_inp_str,
    output  wire    signed  [SAMP_WIDTH - 1:0]              samp_out_data,
    output  wire                                            samp_out_str
);
/*********************************************************************************************/
integer i;
reg             signed  [SAMP_WIDTH - 1 : 0]    data_reg[CIC_M - 1 : 0];        ///< the storage for the FIFO register
wire                                            data_reg_push_str;              ///< strobe to push data into data_reg FIFO
/*********************************************************************************************/


reg             samp_out_str_reg;
if (USE_DSP) begin : genblk1
    (* use_dsp = "yes" *) reg signed      [SAMP_WIDTH - 1 : 0]    data_out_reg;
end else begin : genblk1
    reg signed      [SAMP_WIDTH - 1 : 0]    data_out_reg;
end

assign data_reg_push_str = samp_inp_str;
always @(posedge clk)
begin
    if (!reset_n)           genblk1.data_out_reg <= '0;
    else if (samp_inp_str)  genblk1.data_out_reg <= samp_inp_data - data_reg[CIC_M - 1];
end

assign samp_out_data = genblk1.data_out_reg;
always @(posedge clk)
begin
    if (!reset_n)           samp_out_str_reg <= '0;
    else                    samp_out_str_reg <= samp_inp_str;
end
assign samp_out_str = samp_out_str_reg;
        


/*********************************************************************************************/
// FIFO register with reset
always @(posedge clk)
begin
    if (!reset_n)      for (i = 0; i < CIC_M; i = i + 1)       data_reg[i] <= '0;
    else if (data_reg_push_str) begin
        data_reg[0] <= samp_inp_data;
        for (i = 1; i < CIC_M; i = i + 1)       data_reg[i] <= data_reg[i - 1];
    end
end

/*********************************************************************************************/
endmodule