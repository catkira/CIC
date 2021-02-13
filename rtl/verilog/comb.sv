`timescale 1ns / 1ns
/**
 * Module: comb
 * 
 * Comb stage for CIC filter
 * There is two variants of realisation.
 * Ordinary (SMALL_FOOTPRINT = 0).
 * For every stage in the output extra register added for isolation combinatorial logic outside own adder.
 * Small footprint (SMALL_FOOTPRINT = 1)
 * No additional register, adders are in the chain of CIC_N cells.
 * Output sample generated after CIC_N clocks, f_clk / f_comb_samp > CIC_N required.
 * 
 */
module comb
/*********************************************************************************************/
#(
    parameter       SAMP_WIDTH = 8,
    parameter       CIC_M = 1,
    parameter       SMALL_FOOTPRINT = 0     ///< set to 1 for less registers usage, but for every sample CIC_N clocks required
)
/*********************************************************************************************/
(
    input                                                   clk,
    input                                                   reset_n,
    input   wire    signed  [SAMP_WIDTH - 1:0]              samp_inp_data,
    input                                                   samp_inp_str,
    input                                                   summ_rdy_str,   ///< for SMALL_FOOTPRINT set 1 after CIC_N cycles from inp_str to load FIFO registers with new sample
                                                                            ///< output data must be latched before summ_rdy_str is set, read output data at CIC_N - 1 clock after inp_str
    output  wire    signed  [SAMP_WIDTH - 1:0]              samp_out_data,
    output  wire                                            samp_out_str
);
/*********************************************************************************************/
integer i;
reg             signed  [SAMP_WIDTH - 1 : 0]    data_reg[CIC_M - 1 : 0];        ///< the storage for the FIFO register
wire                                            data_reg_push_str;              ///< strobe to push data into data_reg FIFO
/*********************************************************************************************/


if (SMALL_FOOTPRINT == 0) begin
    reg             samp_out_str_reg;
    reg signed      [SAMP_WIDTH - 1 : 0]    data_out_reg;
    assign data_reg_push_str = samp_inp_str;
    always @(posedge clk or negedge reset_n)
    begin
        if (!reset_n)           data_out_reg <= '0;
        else if (samp_inp_str)  data_out_reg <= samp_inp_data - data_reg[CIC_M - 1];
    end
    assign samp_out_data = data_out_reg;
    always @(posedge clk or negedge reset_n)
    begin
        if (!reset_n)           samp_out_str_reg <= '0;
        else                    samp_out_str_reg <= samp_inp_str;
    end
    assign samp_out_str = samp_out_str_reg;
        
end else begin
    assign data_reg_push_str = summ_rdy_str;
    assign #4 samp_out_data = samp_inp_data - data_reg[CIC_M - 1];  // delay for 18x18 multiplier of Cyclone V SE is 3.4 ns
    assign samp_out_str = summ_rdy_str;
        
end


/*********************************************************************************************/
// FIFO register with reset
always @(posedge clk or negedge reset_n)
begin
    if (!reset_n)      for (i = 0; i < CIC_M; i = i + 1)       data_reg[i] <= '0;
    else if (data_reg_push_str) begin
        data_reg[0] <= samp_inp_data;
        for (i = 1; i < CIC_M; i = i + 1)       data_reg[i] <= data_reg[i - 1];
    end
end

/*********************************************************************************************/
endmodule