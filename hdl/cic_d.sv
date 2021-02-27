`timescale 1ns / 1ns

module cic_d
/*********************************************************************************************/
#(
    parameter INP_DW = 32,          // input data width
    parameter OUT_DW = 32,          // output data width
    parameter RATE_DW = 32,          // rate data width
    parameter CIC_R = 10,           // decimation ratio, if VAR_RATE = 1, R has to be set to the maximum decimation ratio
    parameter CIC_N = 7,            // number of stages
    parameter CIC_M = 1,            // delay in comb
    /* verilator lint_off WIDTH */
    parameter [32*(CIC_N*2+2)-1:0] PRUNE_BITS = {(CIC_N*2+2){32'd0}},   // stage width can be given as a parameter to speed up synthesis
    parameter VAR_RATE = 1,
    parameter EXACT_SCALING = 1,
    parameter NUM_SHIFT = 5 * CIC_N,
    parameter PRG_SCALING = 0
)
/*********************************************************************************************/
(
    input                                   clk,
    input                                   reset_n,
    input   wire    signed [INP_DW-1:0]     s_axis_in_tdata,
    input                                   s_axis_in_tvalid,
    input   wire    signed [RATE_DW-1:0]    s_axis_rate_tdata,
    input                                   s_axis_rate_tvalid,  
    output  wire    signed [OUT_DW-1:0]     m_axis_out_tdata,
    output                                  m_axis_out_tvalid 
);
/*********************************************************************************************/
`include "cic_functions.vh"
/*********************************************************************************************/
localparam bit unsigned [127:0]     Gain_max = (128'(CIC_R) * CIC_M) ** CIC_N;
localparam      B_max = clog2_l(Gain_max) + INP_DW;
localparam      truncated_bits = B_max - OUT_DW;
localparam      dw_out = B_max - get_prune_bits(2*CIC_N);
/*********************************************************************************************/
initial begin
    $display("Gain_max = %d", Gain_max);
    $display("B_max = %d", B_max);
end

function integer get_prune_bits(input integer i);
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

localparam      SCALING_FACTOR_WIDTH = clog2_l(clog2_l((CIC_R * CIC_M) ** CIC_N)) + 1;
localparam      EXACT_SCALING_FACTOR_WIDTH = PRG_SCALING ? RATE_DW - 2 : SCALING_FACTOR_WIDTH + NUM_SHIFT + 1;
localparam      CONFIG_DW = PRG_SCALING ? RATE_DW - 2 : RATE_DW;
reg unsigned       [SCALING_FACTOR_WIDTH-1:0]       current_scaling_factor = 0;
reg unsigned       [EXACT_SCALING_FACTOR_WIDTH-1:0] current_exact_scaling_factor = (((128'(2))**clog2_l(Gain_max))<<NUM_SHIFT)/Gain_max;
wire downsampler_rate_valid;
wire [CONFIG_DW - 1:0] config_data;
assign config_data = s_axis_rate_tdata[RATE_DW - 3:0];

if (PRG_SCALING) begin
    reg unsigned       [CONFIG_DW-1:0]                        scaling_factor_buf = 0;
    reg unsigned       [CONFIG_DW-1:0]                        exact_scaling_factor_buf = 0;
    wire [1:0] config_addr;
    assign config_addr = s_axis_rate_tdata[RATE_DW - 1: RATE_DW - 2];
    assign downsampler_rate_valid = (config_addr == 0) && s_axis_rate_tvalid;
    always_ff @(posedge clk) begin
        if (!reset_n) begin
            scaling_factor_buf <= 0;
            exact_scaling_factor_buf <= 0;
        end
        else if (s_axis_rate_tvalid) begin
            // $display("config_addr = %d", config_addr);
            if (config_addr == 1) begin
                scaling_factor_buf       <= !reset_n ? 0 : config_data;
                $display("shift_number = %d", config_data);
            end
            else if (config_addr == 2) begin
                exact_scaling_factor_buf <= !reset_n ? 0 : config_data;
                $display("mult_number = %d", config_data);
            end
        end
        // one pipeline stage
        current_scaling_factor <= !reset_n ? 0 : scaling_factor_buf;
        if (EXACT_SCALING) begin
            current_exact_scaling_factor <= !reset_n ? 0 : exact_scaling_factor_buf;
        end
    end    
end

// having verilog calculate the scaling factors is not recommended
// this is here as a compatibility modus for the Xilinx CIC
if  (!PRG_SCALING && VAR_RATE) begin
    assign downsampler_rate_valid = s_axis_rate_tvalid;
    (* ram_style = "distributed" *) reg unsigned [SCALING_FACTOR_WIDTH-1:0]         LUT  [1:CIC_R];
    (* ram_style = "distributed" *) reg unsigned [EXACT_SCALING_FACTOR_WIDTH-1:0]   LUT2 [1:CIC_R];
    initial begin
        // this LUT calculation in verilog is limited, it works for R=4095, N=6, M=1
        // if larger values are needed, do LUT calculation outside verilog, ie python
        reg unsigned [127:0] gain_diff;
        reg unsigned [31:0] pre_shift;
        reg unsigned [127:0] post_mult;
        reg unsigned [clog2_l(CIC_R):0] small_r;
        for(integer r=1;r<=CIC_R;r++) begin
            small_r = r[clog2_l(CIC_R):0];
            gain_diff = (((127'(CIC_R) << (NUM_SHIFT / CIC_N)) / r) ** CIC_N);
            pre_shift = flog2_l(gain_diff >> (NUM_SHIFT)); 
            LUT[small_r] = pre_shift[SCALING_FACTOR_WIDTH-1:0]; 
            if (EXACT_SCALING) begin
                // this calculation only makes the frequency response equal to the r = CIC_R case
                // but it does not make it 1! The calculation to make it 1 is too much for verilog :/
                post_mult = (gain_diff >> pre_shift);
                LUT2[small_r] = post_mult[EXACT_SCALING_FACTOR_WIDTH-1:0];
            end
            $display("scaling_factor[%d] = %d  factor rounded = %d  factor exact = %d  mult = %d", r, pre_shift[SCALING_FACTOR_WIDTH-1:0], 128'(2)**pre_shift, gain_diff>>NUM_SHIFT, post_mult[EXACT_SCALING_FACTOR_WIDTH-1:0]);
        end
    end           

    reg unsigned       [SCALING_FACTOR_WIDTH-1:0]           scaling_factor_buf = 0;
    reg unsigned       [EXACT_SCALING_FACTOR_WIDTH-1:0]     exact_scaling_factor_buf = 0;
    always_ff @(posedge clk) begin
        if (!reset_n) begin
            scaling_factor_buf <= 0;
            exact_scaling_factor_buf <= 0;
        end
        else if (s_axis_rate_tvalid) begin
            scaling_factor_buf <= !reset_n ? 0 : LUT[s_axis_rate_tdata];
            if (EXACT_SCALING)
                exact_scaling_factor_buf <= !reset_n ? 0 : LUT2[s_axis_rate_tdata];
            // $display("pre_shift = %d   rate = %d  lut-width = %d" , LUT[s_axis_rate_tdata], s_axis_rate_tdata,SCALING_FACTOR_WIDTH);
        end
        // one pipeline stage
        current_scaling_factor <= !reset_n ? 0 : scaling_factor_buf;
        if (EXACT_SCALING)
            current_exact_scaling_factor <= !reset_n ? 0 : exact_scaling_factor_buf;
    end
end


genvar  i;
generate
    for (i = 0; i < CIC_N; i++) begin : int_stage
        localparam B_jm1 = get_prune_bits(i);   ///< the number of bits to prune in previous stage
        localparam B_j   = get_prune_bits(i+1); ///< the number of bits to prune in current stage
        localparam idw_cur = B_max - B_jm1;         ///< data width on the input
        localparam odw_cur = B_max - B_j;           ///< data width on the output
        
        wire signed [idw_cur - 1 : 0] int_in;           ///< input data bus
        if ( i == 0 )   
            if ((idw_cur-INP_DW) >= 0)
                assign int_in = {{(idw_cur-INP_DW){s_axis_in_tdata[INP_DW-1]}},s_axis_in_tdata};
            else
                assign int_in = s_axis_in_tdata[idw_cur-1:0];
        else
            assign int_in = int_stage[i - 1].int_out;
        wire signed [odw_cur - 1 : 0] int_out;
        
        if (VAR_RATE) begin
            localparam PIPELINE_STAGES = 3;
            reg [idw_cur-1:0] data_buf[0:PIPELINE_STAGES-1];
            reg  [PIPELINE_STAGES-1:0]        valid_buf;
            always_ff @(posedge clk) begin
                if(i == 0)
                    data_buf[0] <= !reset_n ? 0 : (int_in << current_scaling_factor);
                else
                    data_buf[0] <= !reset_n ? 0 : int_in;
                valid_buf[0] <= !reset_n ? 0 : s_axis_in_tvalid;
                for (integer j = 0; j < (PIPELINE_STAGES-1); j++) begin 
                    data_buf[j+1] <= !reset_n ? 0 : data_buf[j];
                    valid_buf[j+1] <= !reset_n ? 0 : valid_buf[j];
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
localparam ds_dw = B_max - B_m;             ///< data width of the downsampler
/*********************************************************************************************/
wire    signed [ds_dw - 1 : 0]  ds_out_samp_data;
wire                            ds_out_samp_str;
/*********************************************************************************************/
initial begin
        //$display("i downsamp dw %d , int_stage[%2d].dw_out = %2d", ds_dw, CIC_N - 1, int_stage[CIC_N - 1].odw_cur);
        $display("i downsamp dw %d", ds_dw);
end
if (VAR_RATE) begin

    localparam PIPELINE_STAGES = 3;
    reg  signed [ds_dw-1:0]                  data_buf[0:PIPELINE_STAGES-1];
    reg         [PIPELINE_STAGES-1:0]        valid_buf;
    reg         [PIPELINE_STAGES-1:0]        rate_valid_buf;
    reg         [CONFIG_DW - 1:0]            rate_data_buf [PIPELINE_STAGES-1:0];
    
    always_ff @(posedge clk) begin
        foreach(data_buf[j]) begin
            data_buf[j] <= !reset_n ? 0 : (j == 0 ? int_stage[CIC_N - 1].int_out : data_buf[j-1]);
            valid_buf[j] <= !reset_n ? 0 : (j == 0 ? s_axis_in_tvalid : valid_buf[j-1]);
            rate_data_buf[j] <= !reset_n ? 0 : (j == 0 ? config_data : rate_data_buf[j-1]);
            rate_valid_buf[j] <= !reset_n ? 0 : (j == 0 ? downsampler_rate_valid : rate_valid_buf[j-1]);
        end                 
    end       

    downsampler_variable #(
            .DATA_WIDTH_INP (ds_dw),
            .DATA_WIDTH_RATE (RATE_DW - 2)
        )
        downsampler_variable_inst
        (
            .clk                    (clk),
            .reset_n                (reset_n),
            .s_axis_in_tdata        (data_buf[PIPELINE_STAGES-1]),
            .s_axis_in_tvalid       (valid_buf[PIPELINE_STAGES-1]),
            .s_axis_rate_tdata      (rate_data_buf[PIPELINE_STAGES-1]),
            .s_axis_rate_tvalid     (rate_valid_buf[PIPELINE_STAGES-1]),
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
    
    for (j = 0; j < CIC_N; j++) begin : comb_stage
        localparam B_m_j_m1             = get_prune_bits(CIC_N + j);
        localparam B_m_j                = get_prune_bits(CIC_N + j + 1);
        localparam idw_cur              = B_max - B_m_j_m1;
        localparam odw_cur              = B_max - B_m_j;
        wire signed [idw_cur - 1 : 0] comb_in;
        wire signed [idw_cur - 1 : 0] comb_inst_out;
        wire signed [odw_cur - 1 : 0] comb_out;
        if (j == 0)     assign comb_in = ds_out_samp_data;
        else            assign comb_in = comb_stage[j - 1].comb_out;
        assign comb_out = comb_inst_out[idw_cur - 1 -: odw_cur];  // throw away some LSBs
        
        wire comb_in_str;
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
// this mult pipeline is not necessary if EXACT_SCALING == 1, it is not used in this case
localparam MULT_PIPELINE_STAGES = 2;
reg signed      [dw_out-1:0]                         comb_out_samp_data_reg[MULT_PIPELINE_STAGES-1:0];
reg             [MULT_PIPELINE_STAGES-1:0]           comb_out_samp_str_reg;
reg signed      [EXACT_SCALING_FACTOR_WIDTH-1:0]     current_exact_scaling_factor_reg[MULT_PIPELINE_STAGES-1:0];

if (EXACT_SCALING) begin
    always_ff @(posedge clk) begin
        foreach(comb_out_samp_data_reg[k]) begin
            if (k == 0) begin
                comb_out_samp_data_reg[0]           <= !reset_n ? 0 : comb_stage[CIC_N - 1].comb_out;    
                current_exact_scaling_factor_reg[0] <= !reset_n ? 0 : current_exact_scaling_factor;
                comb_out_samp_str_reg[0]            <= !reset_n ? 0 : comb_chain_out_str;
            end
            else begin
                comb_out_samp_data_reg[k]           <= !reset_n ? 0 : comb_out_samp_data_reg[k-1];                
                current_exact_scaling_factor_reg[k] <= !reset_n ? 0 : current_exact_scaling_factor_reg[k-1];                
                comb_out_samp_str_reg[k]            <= !reset_n ? 0 : comb_out_samp_str_reg[k-1];                
            end
        end
    end
end
wire signed [dw_out-1+EXACT_SCALING_FACTOR_WIDTH:0] out_mult_result;
if (EXACT_SCALING)
    // this mult operation is done in dw_out+EXACT_SCALING_FACTOR_WIDTH bit, context-determined expression 
    // its important that both operands are signed because of this rule
    // "If any operand is unsigned, the result is unsigned, regardless of the operator"
    assign out_mult_result = comb_out_samp_data_reg[MULT_PIPELINE_STAGES-1] * current_exact_scaling_factor_reg[MULT_PIPELINE_STAGES-1];

// output pipeline
localparam OUT_PIPELINE_STAGES = 2;
reg signed  [OUT_DW-1:0]                 out_data_buf[OUT_PIPELINE_STAGES-1:0];
reg         [OUT_PIPELINE_STAGES-1:0]    out_valid_buf;
always_ff @(posedge clk) begin
    foreach(out_data_buf[j]) begin
        if (j==0) begin
            if (EXACT_SCALING) begin
                out_data_buf[0]  <= !reset_n ? 0 : out_mult_result[dw_out - 1 + NUM_SHIFT : NUM_SHIFT  + (dw_out - OUT_DW)];  
                out_valid_buf[0] <= !reset_n ? 0 : comb_out_samp_str_reg[MULT_PIPELINE_STAGES-1];         
            end   
            else begin
                out_data_buf[0]  <= !reset_n ? 0 : comb_stage[CIC_N - 1].comb_out[dw_out - 1 -: OUT_DW];
                out_valid_buf[0] <= !reset_n ? 0 : comb_chain_out_str;            
            end
        end
        else begin
            out_data_buf[j]  <= !reset_n ? 0 : out_data_buf[j-1];
            out_valid_buf[j] <= !reset_n ? 0 : out_valid_buf[j-1];
        end
    end
end

assign m_axis_out_tdata      = out_data_buf[OUT_PIPELINE_STAGES-1];
assign m_axis_out_tvalid     = out_valid_buf[OUT_PIPELINE_STAGES-1];
/*********************************************************************************************/

`ifdef COCOTB_SIM
initial begin
  $dumpfile ("cic_d.vcd");
  $dumpvars (0, cic_d);
  //#1;
end
`endif

endmodule