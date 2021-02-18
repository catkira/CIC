`timescale 1ns / 1ns

module cic_d
/*********************************************************************************************/
#(
    parameter INP_DW = 32,          // input data width
    parameter OUT_DW = 32,          // output data width
    parameter RATE_DW = 32,          // rate data width
    parameter CIC_R = 10,           // decimation ratio, if VARIABLE_RATE = 1, R has to be set to the maximum decimation ratio
    parameter CIC_N = 7,            // number of stages
    parameter CIC_M = 1,            // delay in comb
    parameter [32*(CIC_N*2+2)-1:0] PRUNE_BITS = {(CIC_N*2+2){32'd0}},   // stage width can be given as a parameter to speed up synthesis
    parameter VARIABLE_RATE = 1
)
/*********************************************************************************************/
(
    input                                   clk,
    input                                   reset_n,
    input   wire    signed [INP_DW-1:0]     s_axis_in_tdata,
    input                                   s_axis_in_tvalid,
    input   wire    signed [RATE_DW-1:0]     s_axis_rate_tdata,
    input                                   s_axis_rate_tvalid,  
    output  wire    signed [OUT_DW-1:0]     m_axis_out_tdata,
    output                                  m_axis_out_tvalid 
);
/*********************************************************************************************/
`include "cic_functions.vh"
/*********************************************************************************************/
localparam      B_max = clog2_l((CIC_R * CIC_M) ** CIC_N) + INP_DW - 1;
localparam      dw_out = B_max - get_prune_bits(2*CIC_N) + 1;
reg        [RATE_DW-1:0]     current_R = CIC_R;
reg        [$clog2(CIC_R)-1:0]     current_scaling_factor = 0;

always @(posedge clk)
begin
    if (!reset_n) begin
        current_R <= CIC_R;
        current_scaling_factor <= 0;
    end
    else if (s_axis_rate_tvalid) begin
        current_R <= s_axis_rate_tdata;
        current_scaling_factor <= LUT[s_axis_rate_tdata];
    end
end
/*********************************************************************************************/

function integer get_prune_bits(input byte i);
    if (PRUNE_BITS[32*(CIC_N*2+2)-1:0] == 0) begin
        //$display("get_prune_bits(%d) = %d", i, B_calc(i, CIC_N, CIC_R, CIC_M, INP_DW, OUT_DW));
        return B_calc(i, CIC_N, CIC_R, CIC_M, INP_DW, OUT_DW);
    end
    else begin
        //#$display("stage=%d return %d calculated %d", i, STAGE_WIDTH[32*i +:32], B_calc(i, CIC_N, CIC_R, CIC_M, INP_DW, OUT_DW));
        //$display("get_prune_bits(%d) = %d", i, PRUNE_BITS[32*i +:32]);
        return PRUNE_BITS[32*i +:32];
    end
endfunction

typedef bit unsigned [$clog2(CIC_R)-1:0] LUT_t [1:CIC_R]; // possible rates are 1..CIC_R
LUT_t LUT;

integer k;
initial begin
    foreach (LUT[k]) begin
        LUT[k] = CIC_R/k;  // rounds down
        //$display("LUT[%d] = %d", k, LUT[k]);
    end
end

genvar  i;
generate
    for (i = 0; i < CIC_N; i = i + 1) begin : int_stage
        localparam B_jm1 = get_prune_bits(i);   ///< the number of bits to prune in previous stage
        localparam B_j   = get_prune_bits(i+1); ///< the number of bits to prune in current stage
        localparam idw_cur = B_max - B_jm1 + 1;         ///< data width on the input
        localparam odw_cur = B_max - B_j   + 1;         ///< data width on the output
        
        wire signed [idw_cur - 1 : 0] int_in;           ///< input data bus
        if ( i == 0 )   assign int_in = s_axis_in_tdata;                  ///< if it is the first stage, then takes data from input of CIC filter
        else            assign int_in = int_stage[i - 1].int_out;       ///< otherwise, takes data from the previous stage of the filter
        wire signed [odw_cur - 1 : 0] int_out;
        
        if (VARIABLE_RATE) begin
            localparam PIPELINE_STAGES = 3;
            reg [idw_cur-1:0] data_buf[0:PIPELINE_STAGES-1];
            reg  [0:PIPELINE_STAGES-1]        valid_buf;
            always @(posedge clk)
            begin
                if(!reset_n) begin
                    valid_buf = {PIPELINE_STAGES{1'b0}};
                end
                else begin
                    data_buf[0] <= int_in;
                    valid_buf[0] <= s_axis_in_tvalid;
                    for (reg [$clog2(PIPELINE_STAGES):0] j = 0; j < (PIPELINE_STAGES-1); j = j + 1) begin 
                        if (i != 0 && j == 1)
                            data_buf[j+1] <= data_buf[j] * current_scaling_factor;
                        else
                            data_buf[j+1] <= data_buf[j];
                        valid_buf[j+1] <= valid_buf[j];
                    end                 
                end
            end    
            integrator #(
                idw_cur,
                odw_cur
                )
                int_inst(
                .clk            (clk),
                .reset_n        (reset_n),
                .inp_samp_data  (data_buf[PIPELINE_STAGES-1]),
                .inp_samp_str   (valid_buf[PIPELINE_STAGES-1]),
                .out_samp_data  (int_out)
                );            
        end
        else begin        
            integrator #(
                idw_cur,
                odw_cur
                )
                int_inst(
                .clk            (clk),
                .reset_n        (reset_n),
                .inp_samp_data  (int_in),
                .inp_samp_str   (s_axis_in_tvalid),
                .out_samp_data  (int_out)
                );
        end       
        initial begin
            //$display("i:%d integ idw=%2d odw=%2d  B(%2d, %3d, %2d, %2d, %2d, %2d)=%2d, Bj-1=%2d, F_sq=%8d", i, idw_cur, odw_cur, i + 1, CIC_R, CIC_M, CIC_N, INP_DW, OUT_DW, B_j, B_jm1, F_sq_j);
            $display("i:%d integ idw=%d ", i, idw_cur);
        end
    end
endgenerate
/*********************************************************************************************/
localparam B_m = get_prune_bits(CIC_N);     ///< bits to prune on the m-th stage
localparam ds_dw = B_max - B_m + 1;         ///< data width of the downsampler
/*********************************************************************************************/
wire    signed [ds_dw - 1 : 0]  ds_out_samp_data;
wire                            ds_out_samp_str;
/*********************************************************************************************/
initial begin
        //$display("i downsamp dw %d , int_stage[%2d].dw_out = %2d", ds_dw, CIC_N - 1, int_stage[CIC_N - 1].odw_cur);
        $display("i downsamp dw %d", ds_dw);
end
if (VARIABLE_RATE) begin

    localparam PIPELINE_STAGES = 3;
    reg [ds_dw-1:0] data_buf[0:PIPELINE_STAGES-1];
    reg  [0:PIPELINE_STAGES-1]        valid_buf;
    
    always @(posedge clk)
    begin
        if(!reset_n) begin
            valid_buf = {PIPELINE_STAGES{1'b0}};
        end
        else begin
            data_buf[0] <= int_stage[CIC_N - 1].int_out;
            valid_buf[0] <= s_axis_in_tvalid;
            for (reg [$clog2(PIPELINE_STAGES):0] j = 0; j < (PIPELINE_STAGES-1); j = j + 1) begin 
                if(j==1)
                    data_buf[j+1] <= data_buf[j] * current_scaling_factor;
                else
                    data_buf[j+1] <= data_buf[j];
                valid_buf[j+1] <= valid_buf[j];
            end                 
        end
    end       

    downsampler_variable #(
            .DATA_WIDTH_INP (ds_dw),
            .DATA_WIDTH_RATE (RATE_DW)
        )
        downsampler_variable_inst
        (
            .clk                    (clk),
            .reset_n                (reset_n),
            .s_axis_in_tdata        (data_buf[PIPELINE_STAGES-1]),
            .s_axis_in_tvalid       (valid_buf[PIPELINE_STAGES-1]),
            .s_axis_rate_tdata      (s_axis_rate_tdata),
            .s_axis_rate_tvalid     (s_axis_rate_tvalid),
            .m_axis_out_tdata       (ds_out_samp_data),
            .m_axis_out_tvalid      (ds_out_samp_str)
        );
end
else begin
    downsampler #(
            .DATA_WIDTH_INP (ds_dw),
            .CIC_R                  (CIC_R)
        )
        downsampler_inst
        (
            .clk                    (clk),
            .reset_n                (reset_n),
            .s_axis_in_tdata        (int_stage[CIC_N - 1].int_out),
            .s_axis_in_tvalid       (s_axis_in_tvalid),
            .m_axis_out_tdata       (ds_out_samp_data),
            .m_axis_out_tvalid      (ds_out_samp_str)
        );
end
/*********************************************************************************************/
genvar  j;
wire                    comb_chain_out_str;
reg     [CIC_N : 0]     comb_inp_str_d;
generate
    
    for (j = 0; j < CIC_N; j = j + 1) begin : comb_stage
        localparam B_m_j_m1             =    get_prune_bits(CIC_N + j);
        localparam B_m_j                =    get_prune_bits(CIC_N + j + 1);
        localparam idw_cur = B_max - B_m_j_m1 + 1;
        localparam odw_cur = B_max - B_m_j + 1;
        wire signed [idw_cur - 1 : 0] comb_in;
        wire signed [idw_cur - 1 : 0] comb_inst_out;
        wire signed [odw_cur - 1 : 0] comb_out;
        if (j == 0)     assign comb_in = ds_out_samp_data;
        else            assign comb_in = comb_stage[j - 1].comb_out;
        assign comb_out = comb_inst_out[idw_cur - 1 -: odw_cur];  // throw away some LSBs
        
        wire                          comb_in_str;
        if (j == 0)     assign comb_in_str = ds_out_samp_str;
        else            assign comb_in_str = comb_stage[j - 1].comb_dv;
        
        comb #(
                .SAMP_WIDTH     (idw_cur),
                .CIC_M          (CIC_M)
            )
            comb_inst(
                .clk            (clk),
                .reset_n        (reset_n),
                .samp_inp_str   (comb_in_str),
                .samp_inp_data  (comb_in),
                .samp_out_str   (comb_dv),
                .samp_out_data  (comb_inst_out)
                );
        wire comb_dv;
        assign comb_chain_out_str = comb_stage[CIC_N - 1].comb_dv;  // use buffered inp_str 
        initial begin
            //$display("i:%d  comb idw=%2d odw=%2d  B(%2d, %3d, %2d, %2d, %2d, %2d)=%2d", j, idw_cur, odw_cur, CIC_N + j + 1, CIC_R, CIC_M, CIC_N, INP_DW, OUT_DW, B_m_j);
            //if (j != 0) $display("odw_prev=%2d, comb_stage[j - 1].odw_cur=%2d", odw_prev, comb_stage[j - 1].odw_cur);
            $display("i:%d  comb idw=%d", j, idw_cur);
        end
    end
endgenerate
/*********************************************************************************************/
reg             signed [OUT_DW-1:0]     comb_out_samp_data_reg;
reg                                     comb_out_samp_str_reg;

always @(posedge clk)
begin
    if      (~reset_n)                      comb_out_samp_data_reg <= '0;
    else if (comb_chain_out_str) begin
        comb_out_samp_data_reg <= comb_stage[CIC_N - 1].comb_out[dw_out - 1 -: OUT_DW];    
        // $display("comb_out = %x   ds_out = %x",comb_stage[CIC_N - 1].comb_out,ds_out_samp_data);
        // if (current_dw_out < OUT_DW) begin
            // $display("%x",comb_stage[CIC_N - 1].comb_out);
            // comb_out_samp_data_reg <= (comb_stage[CIC_N - 1].comb_out[get_prune_bits(2*CIC_N)-1:0]>>2);
        // end
        // else
            // comb_out_samp_data_reg <= comb_stage[CIC_N - 1].comb_out[current_dw_out - 1 -: OUT_DW];
    end
end

always @(posedge clk)
    if      (~reset_n)                      comb_out_samp_str_reg <= '0;
    else                                    comb_out_samp_str_reg <= comb_chain_out_str;

assign m_axis_out_tdata      = comb_out_samp_data_reg;
assign m_axis_out_tvalid     = comb_out_samp_str_reg;
/*********************************************************************************************/

`ifdef COCOTB_SIM
initial begin
  $dumpfile ("cic_d.vcd");
  $dumpvars (0, cic_d);
  #1;
end
`endif

endmodule