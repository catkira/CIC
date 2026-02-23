import math
import numpy as np

class Model:
    def __init__(self, R, N, M, INP_DW, OUT_DW, EXACT_SCALING=0):
        self.R = R
        self.N = N
        self.M = M
        self.INP_DW = INP_DW
        self.OUT_DW = OUT_DW
        self.EXACT_SCALING = EXACT_SCALING

        self.CIC_Filter_Gain = (self.R * self.M) ** self.N
        Num_of_Bits_Growth = np.ceil(math.log2(self.CIC_Filter_Gain))
        self.Num_Output_Bits_Without_Truncation = Num_of_Bits_Growth + self.INP_DW
        # ACC_DW matches RTL: dw + m * $clog2(r * g)
        self.ACC_DW = self.INP_DW + self.N * math.ceil(math.log2(max(self.R * self.M, 2)))
        print(f"B_max: {self.Num_Output_Bits_Without_Truncation}")
        print(f"ACC_DW: {self.ACC_DW}")

        # comb stage state — registered output per stage
        # RTL: all comb stages fire simultaneously on in_dv
        self.comb_delay = [[0] * M for _ in range(N)]
        self.comb_out_reg = [0] * N

        # integrator stage state (operates at output/fast rate)
        self.int_acc = [0] * N

        # I/O
        self.data_in_buf = 0
        self.in_valid = 0
        self.output_started = False

    def set_data(self, data_in):
        self.data_in_buf = data_in
        self.in_valid = 1

    def set_rate(self, rate):
        self.R = rate
        self.reset()

    def reset(self):
        self.comb_delay = [[0] * self.M for _ in range(self.N)]
        self.comb_out_reg = [0] * self.N
        self.int_acc = [0] * self.N
        self.data_in_buf = 0
        self.in_valid = 0
        self.output_started = False
        self.CIC_Filter_Gain = (self.R * self.M) ** self.N
        self.Num_of_Bits_Growth = np.ceil(math.log2(self.CIC_Filter_Gain))
        self.Num_Output_Bits_Without_Truncation = self.Num_of_Bits_Growth + self.INP_DW
        self.ACC_DW = self.INP_DW + self.N * math.ceil(math.log2(max(self.R * self.M, 2)))

    def _to_signed(self, val):
        """Wrap value to ACC_DW-bit signed (two's complement), matching RTL."""
        mask = (1 << self.ACC_DW) - 1
        val = val & mask
        if val >= (1 << (self.ACC_DW - 1)):
            val -= (1 << self.ACC_DW)
        return val

    def tick(self):
        # --- upsample (combinational in RTL) ---
        # RTL: wire upsample = (in_dv) ? comb_stage[m-1].comb_out : 0
        # uses the registered comb output BEFORE this clock edge updates it
        if self.in_valid:
            upsample_val = self.comb_out_reg[self.N - 1]
        else:
            upsample_val = 0

        # --- comb stages (all fire simultaneously on in_dv) ---
        # RTL: samp_inp_str(in_dv) wired to ALL comb stages directly
        # Each stage reads the registered output of the previous stage
        # (from the previous in_dv event, not the current one)
        new_comb_out = list(self.comb_out_reg)

        if self.in_valid:
            for i in range(self.N):
                # input data: stage 0 gets data_in, others get previous registered output
                if i == 0:
                    stage_inp = self.data_in_buf
                else:
                    stage_inp = self.comb_out_reg[i - 1]

                # comb: out = input - delay[end]
                new_comb_out[i] = self._to_signed(stage_inp - self.comb_delay[i][self.M - 1])

                # shift delay line
                for j in range(self.M - 1, 0, -1):
                    self.comb_delay[i][j] = self.comb_delay[i][j - 1]
                self.comb_delay[i][0] = stage_inp

        self.comb_out_reg = new_comb_out

        if self.in_valid:
            self.in_valid = 0
            self.output_started = True

        # --- integrator stages (operate every fast clock) ---
        # RTL: integrators always clocked with inp_samp_str = 1
        # all registers update simultaneously, so use old values for input
        # accumulator wraps at ACC_DW bits (modular arithmetic) to match RTL
        new_int_acc = list(self.int_acc)
        for i in range(self.N):
            inp = upsample_val if i == 0 else self.int_acc[i - 1]
            new_int_acc[i] = self._to_signed(self.int_acc[i] + inp)
        self.int_acc = new_int_acc

    def data_valid(self):
        return self.output_started

    def get_data(self):
        return self.get_scaled_data()

    def get_scaled_data(self):
        raw = self.int_acc[self.N - 1]
        if self.EXACT_SCALING:
            return int(raw / self.CIC_Filter_Gain) * (2 ** (self.OUT_DW - self.INP_DW))
        else:
            # match RTL: data_out = int_out[ACC_DW-1 -: OUT_DW]
            num_shift = self.ACC_DW - self.OUT_DW
            if num_shift < 0:
                num_shift = 0
            return int(raw) >> int(num_shift)
