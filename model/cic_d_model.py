import math
import numpy as np

class Model:
    def __init__(self, R, N ,M, INP_DW, OUT_DW, VAR_RATE, EXACT_SCALING, register_pruning=1):
        self.R = R
        self.N = N
        self.M = M
        self.INP_DW = INP_DW
        self.OUT_DW = OUT_DW
        self.register_pruning = register_pruning
        self.VAR_RATE = VAR_RATE
        self.EXACT_SCALING = EXACT_SCALING

        self.cic_taps = np.zeros(R * M * N)
        self.cic_push_ptr = 0
        self.data_in_buf = 0
        
        if VAR_RATE:
            self.extra_delay   = self.N     
            self.extra_delay_2 = 4 + (self.N-1)*1 
        else:
            self.extra_delay   = self.N            
            self.extra_delay_2 = 4 + (self.N-1)*1 
            
        self.data_out_buf = np.zeros(self.extra_delay+1)
        self.data_out_buf_2 = np.zeros(self.extra_delay_2+1)
        self.out_valid = np.zeros(self.extra_delay+1)
        self.out_valid_2 = np.zeros(self.extra_delay_2+1)
        self.in_valid = 0
        self.decimation_counter = 0;

        self.CIC_Filter_Gain = (self.R*self.M)**self.N        
        Num_of_Bits_Growth = np.ceil(math.log2(self.CIC_Filter_Gain))
        self.Num_Output_Bits_Without_Truncation = Num_of_Bits_Growth + self.INP_DW 
        print(f"B_max: {self.Num_Output_Bits_Without_Truncation}")

    def cic_model_stage_get_out(self, stage):
        ret = 0
        # calculate moving sum for a given stage
        for i_t in np.arange(self.R*self.M):
            ret += self.cic_taps[i_t + stage * self.R*self.M]
        return ret
        
    def set_rate(self, rate):
        self.R = rate
        self.reset()

    def set_data(self, data_in):
        self.data_in_buf = data_in
        self.in_valid = 1
        
    def reset(self):
        self.decimation_counter = 0;
        self.cic_push_ptr = 0
        self.data_in_buf = 0       
        self.in_valid = 0
        self.cic_taps = np.zeros(self.R * self.M * self.N)        
        self.data_out_buf = np.zeros(self.extra_delay+1)
        self.data_out_buf_2 = np.zeros(self.extra_delay_2+1)
        self.out_valid = np.zeros(self.extra_delay+1)
        self.out_valid_2 = np.zeros(self.extra_delay_2+1)        
        self.CIC_Filter_Gain = (self.R*self.M)**self.N        
        self.Num_of_Bits_Growth = np.ceil(math.log2(self.CIC_Filter_Gain))
        self.Num_Output_Bits_Without_Truncation = self.Num_of_Bits_Growth + self.INP_DW        
        
    def tick(self):

        if self.in_valid == 1:
            self.cic_taps[self.cic_push_ptr] = self.data_in_buf
            self.cic_push_ptr = self.cic_push_ptr + 1 if self.cic_push_ptr < self.R*self.M - 1 else 0
            self.out_valid[0] = 1;
            self.in_valid = 0;

        # propagate data to next stage
        for i_s in np.arange(self.N-1,0,-1):
            self.cic_taps[self.cic_push_ptr + i_s * self.R*self.M] = self.cic_model_stage_get_out(i_s - 1)

        
        self.data_out_buf[0] = self.get_scaled_data()
        for i in np.arange(self.extra_delay-1,-1,-1):
            self.data_out_buf[i+1] = self.data_out_buf[i]
            self.out_valid[i+1] = self.out_valid[i]  # not used        
        
        if self.out_valid[self.extra_delay]:
            self.decimation_counter = self.decimation_counter + 1 if self.decimation_counter < (self.R-1) else 0
                    
        if self.out_valid[self.extra_delay] and self.decimation_counter == self.R-1:
            self.out_valid_2[0] = 1
        else:
            self.out_valid_2[0] = 0
            
        self.data_out_buf_2[0] = self.data_out_buf[0]
        for i in np.arange(self.extra_delay_2-1,-1,-1):
            self.data_out_buf_2[i+1] = self.data_out_buf_2[i]
            self.out_valid_2[i+1] = self.out_valid_2[i]
            
    
    # moving average is calculated for every sample of fast clock, but only every Rth sample is used for output
    def data_valid(self):
        if self.out_valid_2[self.extra_delay_2] == 1:
            return True
        return False
        
    def get_data(self):
        return self.data_out_buf_2[self.extra_delay_2]

    def get_scaled_data(self):
        if self.EXACT_SCALING:
            return int(self.cic_model_stage_get_out(self.N - 1) / self.CIC_Filter_Gain)*(2**(self.OUT_DW-self.INP_DW));
            #return int(self.cic_model_stage_get_out(self.N - 1)) >> int(self.Num_Output_Bits_Without_Truncation - self.OUT_DW)
        else:
            num_shift = self.Num_Output_Bits_Without_Truncation - self.OUT_DW
            if num_shift < 0:
                num_shift = 0
            return int(self.cic_model_stage_get_out(self.N - 1)) >> int(num_shift)
        
