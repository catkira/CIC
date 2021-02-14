`timescale 1ns / 1ns
module cic_d_tb
(
);
`include "../../rtl/verilog/cic_functions.vh"
`define M_PI 3.14159265359      // not all simulators defines PI 

// U. Meyer-Baese, Digital Signal Processing with Field Programmable Gate Arrays, 2nd Edition, Spinger, 2004.
// Example 5.5: Three-Stages CIC Decimator II
/*
localparam CIC_R = 32;
localparam SAMP_INP_DW = 8;
localparam SAMP_OUT_DW = 10;
localparam INP_SAMP_WIDTH_TO_SIGNAL_WIDTH = 2;
localparam CIC_N = 3;
localparam CIC_M = 2;
localparam SMALL_FOOTPRINT = 1;
*/
/*localparam CIC_R = 100;
localparam SAMP_INP_DW = 18;
localparam SAMP_OUT_DW = 18;
localparam INP_SAMP_WIDTH_TO_SIGNAL_WIDTH = 2;
localparam CIC_N = 7;
localparam CIC_M = 1;
localparam SMALL_FOOTPRINT = 1; ///< set to 1 for less registers usage, but for every sample CIC_N clocks required
*/
/*
//https://www.so-logic.net/documents/trainings/03_so_implementation_of_filters.pdf
localparam CIC_R = 16;
localparam SAMP_INP_DW = 16;
localparam SAMP_OUT_DW = 16;
localparam INP_SAMP_WIDTH_TO_SIGNAL_WIDTH = 1;
localparam CIC_N = 3;
localparam CIC_M = 1;
localparam SMALL_FOOTPRINT = 1;
*/
/*
// Eugene B. Hogenauer paper
// B: 1, 6, 9, 13, 14, 15, 16, 17
localparam CIC_R = 25;
localparam SAMP_INP_DW = 16;
localparam SAMP_OUT_DW = 16;
localparam CIC_N = 4;
localparam CIC_M = 1;
localparam SMALL_FOOTPRINT = 1;
localparam INP_SAMP_WIDTH_TO_SIGNAL_WIDTH = 0;
*/
/*localparam R = 8;
localparam SAMP_INP_DW = 12;
localparam SAMP_OUT_DW = 12;
localparam M = 3;
localparam G = 1;*/

localparam CIC_R = 100;
localparam SAMP_INP_DW = 17;
localparam SAMP_OUT_DW = 14;
localparam CIC_N = 7;
localparam CIC_M = 1;
localparam SMALL_FOOTPRINT = 1;
localparam INP_SAMP_WIDTH_TO_SIGNAL_WIDTH = 0;

/*************************************************************/
localparam integer CIC_RM = CIC_R * CIC_M;
localparam real T_clk_ns = 8;//ns
localparam time half_T = T_clk_ns/2;
/// parameters of CIC filter with bits prune
localparam B_max = B_max_calc(CIC_N, CIC_R, CIC_M, SAMP_INP_DW);
localparam B_out = B_out_calc(CIC_N, CIC_R, CIC_M, SAMP_INP_DW, SAMP_OUT_DW);
localparam B_2Np1 = B_max - SAMP_OUT_DW + 1;

localparam delta_f_offs = 200;  /// clock number to start delta-function in simulation
/*************************************************************/
reg                                     clk;                                    ///< clock
reg                                     reset_n;                                ///< reset, active 0
wire    signed  [SAMP_INP_DW-1:0]       filter_inp_data;                ///< input test data of filter
reg     signed  [SAMP_INP_DW-1:0]       filter_inp_data_d[0:2]; ///< delayed filter_inp_data, for reference model
wire                                    filter_out_str;                 ///< filter output sample ready strobe
reg                                     filter_out_str_d;               ///< filter_out_str delayed
wire    signed  [SAMP_OUT_DW-1:0]       filter_out;                             ///< filter output data
reg     signed  [SAMP_OUT_DW-1:0]       filter_out_reg;                 ///< 
wire    signed  [SAMP_OUT_DW-1:0]       filter_out_ref_wire;    ///< reference filter output data
reg     signed  [SAMP_OUT_DW-1:0]       filter_out_ref;                 ///< 
reg     signed  [SAMP_OUT_DW-1:0]       filter_out_diff;                ///< subtracting tested filter output and reference filter output 
integer clk_counter;    ///< counter of clock periods
integer samp_counter;   ///< counter of input samples
real phase_curr;                ///< phase of input signal
real phase_step;                ///< step of input signal phase increment
integer N_t_samp = 2;   ///< period of input samples frequency in clocks
integer samples_period_ctr;     ///< counter for generating input samples period
integer samples_period_val;     ///< period of input samples in clocks
wire    samples_period_rdy;     ///< signal is set at the end of input samples period
real    carry_freq;                     ///< frequency of test sin signal
longint cic_taps[CIC_R * CIC_M * CIC_N];        ///< storage of internal state of reference CIC filter model
integer cic_push_ptr;                                           ///< pointer to the FIFO buffer of reference CIC model
integer cic_model_out_int;                                      ///< output of reference CIC model
integer cic_B_scale_out;
integer cic_B_prune;
integer cic_B_prune_last_stage;
longint cic_S_prune;
longint cic_S_prune_last_stage;

/// the reference model of a CIC filter 
task cic_model_reset;   ///< set filter to the initial state
    integer i_s;
    integer i_t;
    for(i_s = CIC_N - 1; i_s >= 0; i_s = i_s - 1)
        for(i_t = 0; i_t < CIC_RM; i_t = i_t + 1)
            cic_taps[i_t + i_s * CIC_RM] = 0;
    cic_push_ptr = 0;
endtask

task cic_model_push(longint inp_samp);  ///< add input sample
    integer i_s;
    for (i_s = CIC_N - 1; i_s >= 1; i_s = i_s - 1)
        cic_taps[cic_push_ptr + i_s * CIC_RM] = cic_model_stage_get_out(i_s - 1);
    cic_taps[cic_push_ptr] = inp_samp;
    if (cic_push_ptr < CIC_RM - 1)          cic_push_ptr = cic_push_ptr + 1;
    else                                    cic_push_ptr = 0;
endtask

function longint cic_model_stage_get_out(integer stage);        ///< get output of stage
    integer i_t;
    cic_model_stage_get_out = 0;
    for(i_t = 0; i_t < CIC_RM; i_t = i_t + 1)
        cic_model_stage_get_out = cic_model_stage_get_out + cic_taps[i_t + stage * CIC_RM];
    cic_model_stage_get_out = cic_model_stage_get_out / cic_S_prune;
    if (stage == CIC_N - 1)
        cic_model_stage_get_out = cic_model_stage_get_out / cic_S_prune_last_stage;
endfunction

/*************************************************************/
initial begin : clk_gen
    clk = 1'b0;
    clk_counter = 0;
    carry_freq = 10000;
    samples_period_val = 6;
    samples_period_ctr = 0;
    phase_curr <= 0;
    phase_step = T_clk_ns * samples_period_val * 2 * carry_freq * `M_PI * 0.000000001;
    cic_model_reset();
    samp_counter <= 0;
    #half_T forever #half_T clk = ~clk;
end
/*************************************************************/

initial begin
    $dumpfile("../out/cic_d_tb.vcd");
    $dumpvars(4, cic_d_tb);
end


initial begin : reset_gen

    reg [127:0] h_f0_pre;
    integer log2_h_f0_pre;
    integer h_f0_pre_limit_prec;
    integer h_f0_pre_divider;
    integer h_f0_divider_exp;
    real    h_f0;
    integer B_max;
    integer B_out;
    integer B_2Np1;
    $display("tb CIC INP_DW      %d", SAMP_INP_DW);
    $display("tb CIC OUT_DW      %d", SAMP_OUT_DW);
    $display("tb CIC R        %d", CIC_R);
    $display("tb CIC N        %d", CIC_N);
    $display("tb CIC M        %d", CIC_M);
    B_max = B_max_calc(CIC_N, CIC_R, CIC_M, SAMP_INP_DW);
    B_out = B_out_calc(CIC_N, CIC_R, CIC_M, SAMP_INP_DW, SAMP_OUT_DW);
    //B_2Np1 = B_max - B_out + 1;
    B_2Np1 = B_calc(CIC_N * 2, CIC_N, CIC_R, CIC_M, SAMP_INP_DW, SAMP_OUT_DW);
    $display("B_max= %2d, B_out = %2d, B_2N+1 = %2d", B_max, B_out, B_2Np1);
    h_f0_pre = (CIC_R*CIC_M)**CIC_N;
    h_f0_divider_exp = (B_2Np1 + 1);
    h_f0_pre_limit_prec = 30;
    log2_h_f0_pre = clog2_l(h_f0_pre);
    $display(" log2_h_f0_pre = %2d, lim %2d", log2_h_f0_pre, h_f0_pre_limit_prec);
    if (log2_h_f0_pre > h_f0_pre_limit_prec) begin
        h_f0_pre_divider = log2_h_f0_pre - h_f0_pre_limit_prec;
        $display(" h_f0_pre_divider = %2d", h_f0_pre_divider);
        h_f0_pre = h_f0_pre >> h_f0_pre_divider;
        h_f0_divider_exp = h_f0_divider_exp - h_f0_pre_divider;
        $display(" log2_h_f0_pre limited = %2d, divider_exp limited %2d", log2_h_f0_pre, h_f0_divider_exp);
        h_f0 = 1.0 * h_f0_pre / 2**(h_f0_divider_exp);
    end
    else begin
            h_f0 = h_f0_pre / 2**(B_2Np1 + 1);
    end
    $display("tb CIC h fwd    %2.8f", h_f0);
    // to avoid overflow in reference model, use cic_B_prune to 
    //cic_B_prune = B_2Np1 / CIC_N;
    cic_B_scale_out = B_max + 1 - SAMP_OUT_DW;
    cic_B_prune = 0;
    cic_S_prune = 1 << cic_B_prune;
    //cic_B_prune_last_stage = B_2Np1 + 1 - cic_B_prune * CIC_N;
    cic_B_prune_last_stage = cic_B_scale_out - cic_B_prune * CIC_N;
    cic_S_prune_last_stage = 1 << cic_B_prune_last_stage;
    $display("model:");
    $display(" B_max=%2d; B_out=%2d; cic_B_scale_out=%2d", B_max, B_out, cic_B_scale_out);
    $display("cic_B_prune = %2d, cic_B_prune_last = %2d, ", cic_B_prune, cic_B_prune_last_stage);
    $display($time, " << Starting the Simulation >>");
    reset_n = 1'b0;
    repeat (2) @(negedge clk);
    //$finish;
    $display($time, " << Coming out of reset >>");
    reset_n = 1'b1;
    repeat (40000) @(posedge clk);
    @(posedge clk);
    $display($time, " << Simulation done >>");
    $finish;

end

always @(posedge clk) if (~clk) clk_counter <= clk_counter + 1;
/*************************************************************/
assign samples_period_rdy = samples_period_ctr >= (samples_period_val - 1);
always @(posedge clk)
    if (samples_period_rdy) samples_period_ctr <= 0;
    else                            samples_period_ctr <= samples_period_ctr + 1;

always @(posedge clk)
begin
    if (samples_period_rdy == 1'b1) begin
        for (int i1 = 2; i1 >= 1; i1 = i1 - 1) filter_inp_data_d[i1] <= filter_inp_data_d[i1 - 1];
        filter_inp_data_d[0] <= filter_inp_data;
        cic_model_push(filter_inp_data_d[1]);
        samp_counter <= samp_counter + 1;
        phase_curr <= phase_curr + phase_step;
    end
end
/*************************************************************/
assign filter_inp_data = $rtoi((2**(SAMP_INP_DW - INP_SAMP_WIDTH_TO_SIGNAL_WIDTH - 1) - 1)*($sin(phase_curr)));
//assign filter_inp_data = samp_counter == delta_f_offs ? 10000 : 0;    ///< delta function
//assign filter_inp_data = samp_counter >= delta_f_offs && samp_counter < delta_f_offs + CIC_N ? 10000 : 0;
//assign filter_inp_data = samp_counter >= delta_f_offs ? 1 << (SAMP_INP_DW / 2) : 0;   ///< Hamming function
//assign filter_inp_data = samp_counter >= delta_f_offs ? 1 << (SAMP_INP_DW - INP_SAMP_WIDTH_TO_SIGNAL_WIDTH -1 ) : 0;  ///< Hamming function
/*************************************************************/

cic_d #(
    .INP_DW                         (SAMP_INP_DW),
    .OUT_DW                         (SAMP_OUT_DW),
    .CIC_R                          (CIC_R),
    .CIC_N                          (CIC_N),
    .CIC_M                          (CIC_M),
    .SMALL_FOOTPRINT        (SMALL_FOOTPRINT)
)
dut1
(
    .clk                        (clk),
    .reset_n            (reset_n),
    .clear                      (1'b0),
    .inp_samp_data      (filter_inp_data),
    .inp_samp_str       (samples_period_rdy),
    .out_samp_data      (filter_out),
    .out_samp_str       (filter_out_str)
);
always @(posedge clk)
        filter_out_str_d <= filter_out_str;
always @(posedge clk)
begin
    if (filter_out_str == 1'b1) begin
        filter_out_reg  <= filter_out;
        filter_out_ref  <= cic_model_stage_get_out(CIC_N - 1);
    end
end
always @(posedge clk)
begin
    if (filter_out_str_d == 1'b1) begin
        filter_out_diff <= filter_out - filter_out_ref;
    end
end

/*************************************************************/
endmodule
 