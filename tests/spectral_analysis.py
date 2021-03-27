import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer
from cocotb.triggers import RisingEdge, ReadOnly
from fixedpoint import FixedPoint
from collections import deque

import random
import warnings
import os
import logging
import cocotb_test.simulator
import pytest
import math
import numpy as np
import matplotlib.pyplot as plt
from scipy import signal


import importlib.util

CLK_PERIOD_S = (1/500E6)  # 500 MHz

def dB20(array):
    with np.errstate(divide='ignore'):
        return 20 * np.log10(array)
        
def dB10(array):
    with np.errstate(divide='ignore'):
        return 10 * np.log10(array)    

class TB(object):
    def __init__(self,dut):
        random.seed(30) # reproducible tests
        self.dut = dut
        self.initial_R = int(dut.CIC_R)
        self.R = int(dut.CIC_R)
        self.N = int(dut.CIC_N)
        self.M = int(dut.CIC_M)
        self.INP_DW = int(dut.INP_DW)
        self.OUT_DW = int(dut.OUT_DW)
        self.RATE_DW = int(dut.RATE_DW)
        self.VAR_RATE = int(dut.VAR_RATE)
        self.EXACT_SCALING = int(dut.EXACT_SCALING)
        self.NUM_SHIFT = int(dut.NUM_SHIFT)

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)        
        
        self.f_mhz = 18.000
        self.f_clk = 122.88E6

        self.input = []

        tests_dir = os.path.abspath(os.path.dirname(__file__))
        model_dir = os.path.abspath(os.path.join(tests_dir, '../model/cic_d_model.py'))
        spec = importlib.util.spec_from_file_location("cic_d_model", model_dir)
        foo = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(foo)
        self.model = foo.Model(self.R, self.N, self.M, self.INP_DW, self.OUT_DW, self.VAR_RATE, self.EXACT_SCALING) 
        cocotb.fork(Clock(self.dut.clk, CLK_PERIOD_S * 1E9, units='ns').start())
        cocotb.fork(self.model_clk(CLK_PERIOD_S * 1E9, 'ns'))            
        
    async def model_clk(self, period, period_units):
        timer = Timer(period, period_units)
        while True:
            self.model.tick()
            await timer

    async def generate_input(self):
        phase = 0
        freq = self.f_mhz*1E6 / CLK_PERIOD_S / self.f_clk
        phase_step = CLK_PERIOD_S * 2 * freq * math.pi
        print(F"normalized freq = {CLK_PERIOD_S*freq:.12f} Hz")
        self.input = []
        while True:
            phase += phase_step
            value = int(np.round(math.sin(phase)*(2**(self.INP_DW-1)-1)))
            await RisingEdge(self.dut.clk)
            self.model.set_data(value) 
            self.input.append(value)
            self.dut.s_axis_in_tdata <= value
            self.dut.s_axis_in_tvalid <= 1

    async def cycle_reset(self):
        self.dut.s_axis_rate_tvalid <= 0
        self.dut.s_axis_in_tvalid <= 0
        self.dut.reset_n.setimmediatevalue(1)
        await RisingEdge(self.dut.clk)
        self.dut.reset_n <= 0
        await RisingEdge(self.dut.clk)
        self.dut.reset_n <= 1
        await RisingEdge(self.dut.clk)
        self.model.reset()
        
    async def set_rate(self, rate):
        print(f"set rate: {rate}")
        self.model.set_rate(rate)
        self.R = rate
        self.dut.s_axis_in_tvalid <= 0
        await RisingEdge(self.dut.clk)
        self.dut.s_axis_rate_tdata <= rate
        self.dut.s_axis_rate_tvalid <= 1
        await RisingEdge(self.dut.clk)
        self.dut.s_axis_rate_tvalid <= 0
        await RisingEdge(self.dut.clk)
    

        
    async def programm_scaling_parameters(self):
        # set input shift scaling
        assert (np.log2(self.NUM_SHIFT) <= self.RATE_DW-2), F"RATE_DW = {self.RATE_DW} is too small for NUM_SHIFT = {self.NUM_SHIFT}"
        await RisingEdge(self.dut.clk)
        shift_number = 0;
        mult_number = 0;
        if True:
            # exact floating-point calculation
            gain_factor_log2 = self.N * np.log2( 2**np.ceil(np.log2(self.initial_R)) / self.R )
            shift_number = int(gain_factor_log2) # rounded down
            mult_number = int(2**(gain_factor_log2 - shift_number) * 2**self.NUM_SHIFT) 
        if False:
            # fixed point calculation, needs more tolerance when testing against the model
            gain_diff = int(np.floor(self.initial_R << int(self.NUM_SHIFT / self.N)) / self.R) ** self.N;
            shift_number = int(np.floor(np.log2((gain_diff >> self.NUM_SHIFT))))
            mult_number = gain_diff >> shift_number
            
        print(F"shift_number = {shift_number}")
        print(F"mult_number = {mult_number}")
        self.dut.s_axis_rate_tdata <= (1 << (self.RATE_DW-2)) + (shift_number & (2**(self.RATE_DW-2)-1))
        self.dut.s_axis_rate_tvalid <= 1
        await RisingEdge(self.dut.clk)
        self.dut.s_axis_rate_tvalid <= 0
        await RisingEdge(self.dut.clk)
        # set output scaling
        self.dut.s_axis_rate_tdata <= (2 << (self.RATE_DW-2)) + (mult_number & (2**(self.RATE_DW-2)-1))
        self.dut.s_axis_rate_tvalid <= 1
        await RisingEdge(self.dut.clk)
        self.dut.s_axis_rate_tvalid <= 0
        
                
@cocotb.test()
async def programmable_scaling_test(dut):
    tb = TB(dut)
    rate_list = [3]
    if tb.VAR_RATE == 0:
        rate_list = [tb.R]
    for rate in rate_list:
        print(f"rate: {rate}")
        await tb.cycle_reset()
        if tb.VAR_RATE:
            await tb.set_rate(rate)
        
        await tb.programm_scaling_parameters()
        num_items = 1E4 
        output = []
        output_model = []
        gen = cocotb.fork(tb.generate_input())
        tolerance = 1
        if tb.EXACT_SCALING:
            # exact scaling needs a bit more tolerance because of rounding errors
            tolerance = 0.0005    # 0.0005 is enough if fp is used for calculation of the exact scaling factor   
        count = 0;
        max_count = num_items * rate * 2;
        max_out_value = (2**(tb.OUT_DW-1)-1)
        while len(output_model) < num_items or len(output) < num_items:
            await RisingEdge(dut.clk)
            if(tb.model.data_valid()):
                output_model.append(tb.model.get_data())
                #print(f"model:\t[{len(output_model)}]\t {int(output_model[-1])} \t {output_model[-1]/max_out_value}")

            if dut.m_axis_out_tvalid == 1:
                a=dut.m_axis_out_tdata.value.integer
                if (a & (1 << (tb.OUT_DW - 1))) != 0:
                    a = a - (1 << tb.OUT_DW)
                output.append(a)
                #print(f"hdl: \t[{len(output)}]\t {int(a)} \t {a/max_out_value} ")
            #print(f"{int(tb.model.data_valid())} {dut.m_axis_out_tvalid}")
            count += 1
            if count > max_count:
                assert False, "not enough items received"        
        gen.kill()
        tb.dut.s_axis_in_tvalid <= 0
        if True:
            use_window = True
            window_text = "none"
            if use_window:
                window = signal.hann(len(output))
                window_text = "hann"
                output *= window
                output /= sum(window)/len(output)
            fig1 = plt.figure()
            plt.title(F"CIC output\nf_clk = {tb.f_clk*1E-6} MHz, f_signal = {tb.f_mhz} Mhz, n = {num_items}, window = {window_text}")
            plt.plot(range(len(output)),output)
            #plt.plot(range(len(output_model)),output_model)
            fig2 = plt.figure()
            plt.title(F"Two-sided Spectrum of CIC output\nf_clk = {tb.f_clk*1E-6} MHz, f_signal = {tb.f_mhz} Mhz, n = {num_items}, window = {window_text}")
            output_float = np.array(output) / (2**(tb.OUT_DW-1)-1)
            S = np.fft.fftshift(np.fft.fft(output_float))
            freq = np.fft.fftshift(np.fft.fftfreq(n=len(output_float), d=1/tb.f_clk*tb.R))
            tiny_offset = 0
            ydata = dB20(np.abs(S+tiny_offset)/(len(output_float)))
            plt.plot(freq,ydata)
            plt.ylim(np.maximum(-200,ydata.min()), ydata.max()+10)        
            fig3 = plt.figure()
            plt.title(F"Power Spectrum of CIC output\nf_clk = {tb.f_clk*1E-6} MHz, f_signal = {tb.f_mhz} Mhz, n = {num_items}, window = {window_text}")
            ydata_onesided = ydata[int(len(ydata)/2):] + 6
            ydata_onesided[0] -= 6
            plt.plot(freq[int(len(ydata)/2):],ydata_onesided)
            plt.ylim(np.maximum(-200,ydata_onesided.min()), ydata_onesided.max()+10)        
            plt.xlabel("Hz")
            plt.ylabel("Normalized Power in dB")
            plt.show()        
        for i in range(num_items):
            if tb.EXACT_SCALING:
                assert np.abs(output[i] - output_model[i])/max_out_value <= tolerance, f"hdl: {output[i]} \t model: {output_model[i]}"
            else:
                assert np.abs(output[i] - output_model[i]) <= tolerance, f"hdl: {output[i]} \t model: {output_model[i]}"      

        