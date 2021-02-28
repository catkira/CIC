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

import importlib.util

CLK_PERIOD_NS = 8
CLK_PERIOD_S = CLK_PERIOD_NS * 0.000000001

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

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)        

        self.input = []

        tests_dir = os.path.abspath(os.path.dirname(__file__))
        model_dir = os.path.abspath(os.path.join(tests_dir, '../model/cic_d_model.py'))
        spec = importlib.util.spec_from_file_location("cic_d_model", model_dir)
        foo = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(foo)
        self.model = foo.Model(self.R, self.N, self.M, self.INP_DW, self.OUT_DW, self.VAR_RATE, self.EXACT_SCALING) 
        cocotb.fork(Clock(self.dut.clk, CLK_PERIOD_NS, units='ns').start())
        cocotb.fork(self.model_clk(CLK_PERIOD_NS, 'ns'))    
          
    async def model_clk(self, period, period_units):
        timer = Timer(period, period_units)
        while True:
            self.model.tick()
            await timer

    async def generate_input(self):
        phase = 0
        freq = 10000
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
        self.NUM_SHIFT = 5*self.N
        assert (self.NUM_SHIFT <= self.RATE_DW-2), F"RATE_DW = {self.RATE_DW} is too small for NUM_SHIFT = {self.NUM_SHIFT}"
        await RisingEdge(self.dut.clk)
        gain_diff = int(np.floor(self.initial_R << int(self.NUM_SHIFT / self.N)) / self.R) ** self.N;
        shift_number = int(np.floor(np.log2((gain_diff >> self.NUM_SHIFT))))
        #print(F"shift_number = {shift_number}")
        #self.dut.s_axis_rate_tdata <= (1 << (self.RATE_DW-2)) + (shift_number & (2**(self.RATE_DW-2)-1))
        self.dut.s_axis_rate_tdata <= (1 << (self.RATE_DW-2)) + shift_number
        self.dut.s_axis_rate_tvalid <= 1
        await RisingEdge(self.dut.clk)

        self.dut.s_axis_rate_tvalid <= 0
        await RisingEdge(self.dut.clk)
        # set output scaling
        mult_number = gain_diff >> shift_number
        #self.dut.s_axis_rate_tdata <= (2 << (self.RATE_DW-2)) + (mult_number & (2**(self.RATE_DW-2)-1))
        self.dut.s_axis_rate_tdata <= (2 << (self.RATE_DW-2)) + mult_number
        self.dut.s_axis_rate_tvalid <= 1
        await RisingEdge(self.dut.clk)
        self.dut.s_axis_rate_tvalid <= 0
        
        
@cocotb.test()
async def simple_test(dut):
    tb = TB(dut)
    await tb.cycle_reset()
    num_items = 100
    gen = cocotb.fork(tb.generate_input())
    output = []
    output_model = []
    tolerance = 1
    if tb.EXACT_SCALING:
        # exact scaling needs a bit more tolerance because of rounding errors
        tolerance = 0.005
    count = 0;
    max_count = num_items * tb.R * 2;
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
    
    for i in range(num_items):
        if tb.EXACT_SCALING:
            assert np.abs(output[i] - output_model[i])/max_out_value <= tolerance, f"hdl: {output[i]} \t model: {output_model[i]}"
        else:
            assert np.abs(output[i] - output_model[i]) <= tolerance, f"hdl: {output[i]} \t model: {output_model[i]}"
    #print(f"received {len(output)} samples")
    gen.kill()
    tb.dut.s_axis_in_tvalid <= 0
    
@cocotb.test()
async def variable_rate_test(dut):
    tb = TB(dut)
    rate_list = [15,100]
    for rate in rate_list:
        print(f"rate: {rate}")
        await tb.cycle_reset()
        await tb.set_rate(rate)

        num_items = 50
        output = []
        output_model = []
        gen = cocotb.fork(tb.generate_input())
        tolerance = 1
        if tb.EXACT_SCALING:
            # exact scaling needs a bit more tolerance because of rounding errors
            tolerance = 0.005        
        count = 0;
        max_count = num_items * rate * 2;
        max_out_value = (2**(tb.OUT_DW-1)-1)
        while len(output_model) < num_items or len(output) < num_items:
            await RisingEdge(dut.clk)
            if(tb.model.data_valid()):
                output_model.append(tb.model.get_data())
                print(f"model:\t[{len(output_model)}]\t {int(output_model[-1])} \t {output_model[-1]/max_out_value}")

            if dut.m_axis_out_tvalid == 1:
                a=dut.m_axis_out_tdata.value.integer
                if (a & (1 << (tb.OUT_DW - 1))) != 0:
                    a = a - (1 << tb.OUT_DW)
                output.append(a)
                print(f"hdl: \t[{len(output)}]\t {int(a)} \t {a/max_out_value} ")
            #print(f"{int(tb.model.data_valid())} {dut.m_axis_out_tvalid}")
            count += 1
            if count > max_count:
                assert False, "not enough items received"        
        gen.kill()
        tb.dut.s_axis_in_tvalid <= 0
        for i in range(num_items):
            if tb.EXACT_SCALING:
                assert np.abs(output[i] - output_model[i])/max_out_value <= tolerance, f"hdl: {output[i]} \t model: {output_model[i]}"
            else:
                assert np.abs(output[i] - output_model[i]) <= tolerance, f"hdl: {output[i]} \t model: {output_model[i]}"
                
@cocotb.test()
async def programmable_scaling_test(dut):
    tb = TB(dut)
    rate_list = [15,100]
    if tb.VAR_RATE == 0:
        rate_list = [tb.R]
    for rate in rate_list:
        print(f"rate: {rate}")
        await tb.cycle_reset()
        if tb.VAR_RATE:
            await tb.set_rate(rate)
        
        await tb.programm_scaling_parameters()
        num_items = 10
        output = []
        output_model = []
        gen = cocotb.fork(tb.generate_input())
        tolerance = 1
        if tb.EXACT_SCALING:
            # exact scaling needs a bit more tolerance because of rounding errors
            tolerance = 0.005        
        count = 0;
        max_count = num_items * rate * 2;
        max_out_value = (2**(tb.OUT_DW-1)-1)
        while len(output_model) < num_items or len(output) < num_items:
            await RisingEdge(dut.clk)
            if(tb.model.data_valid()):
                output_model.append(tb.model.get_data())
                print(f"model:\t[{len(output_model)}]\t {int(output_model[-1])} \t {output_model[-1]/max_out_value}")

            if dut.m_axis_out_tvalid == 1:
                a=dut.m_axis_out_tdata.value.integer
                if (a & (1 << (tb.OUT_DW - 1))) != 0:
                    a = a - (1 << tb.OUT_DW)
                output.append(a)
                print(f"hdl: \t[{len(output)}]\t {int(a)} \t {a/max_out_value} ")
            #print(f"{int(tb.model.data_valid())} {dut.m_axis_out_tvalid}")
            count += 1
            if count > max_count:
                assert False, "not enough items received"        
        gen.kill()
        tb.dut.s_axis_in_tvalid <= 0
        for i in range(num_items):
            if tb.EXACT_SCALING:
                assert np.abs(output[i] - output_model[i])/max_out_value <= tolerance, f"hdl: {output[i]} \t model: {output_model[i]}"
            else:
                assert np.abs(output[i] - output_model[i]) <= tolerance, f"hdl: {output[i]} \t model: {output_model[i]}"       
# cocotb-test


tests_dir = os.path.abspath(os.path.dirname(__file__))
rtl_dir = os.path.abspath(os.path.join(tests_dir, '..', 'hdl'))

def calculate_prune_bits(R, N, M, INP_DW, OUT_DW):
    tools_dir = os.path.abspath(os.path.join(tests_dir, '../tools/calculate_register_pruning.py'))
    spec = importlib.util.spec_from_file_location("calculate_register_pruning", tools_dir)
    foo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(foo)
    B_j = foo.calculate_register_pruning(R, N, M, INP_DW, OUT_DW)
    
    ret = 0
    for i in range(1,2*N+2):
        print(f"B_j[{i}] = {B_j[i]}")
        ret += int(B_j[i])<<(32*(i))
    return ret

@pytest.mark.parametrize("R", [100, 10])
@pytest.mark.parametrize("N", [6, 3])
@pytest.mark.parametrize("M", [1, 3])
@pytest.mark.parametrize("INP_DW", [16])
@pytest.mark.parametrize("OUT_DW", [14, 16])
@pytest.mark.parametrize("RATE_DW", [16])
@pytest.mark.parametrize("PRECALCULATE_PRUNE_BITS", [0, 1])
@pytest.mark.parametrize("VAR_RATE", [0])
@pytest.mark.parametrize("EXACT_SCALING", [0, 1])
def test_cic_d(request, R, N, M, INP_DW, OUT_DW, RATE_DW, VAR_RATE, EXACT_SCALING, PRECALCULATE_PRUNE_BITS):
    dut = "cic_d"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(rtl_dir, "comb.sv"),
        os.path.join(rtl_dir, "integrator.sv"),
        os.path.join(rtl_dir, "downsampler.sv"),
        os.path.join(rtl_dir, "downsampler_variable.sv"),
    ]
    includes = [
        os.path.join(rtl_dir, ""),
        os.path.join(rtl_dir, "cic_functions.vh"),
    ]    

    parameters = {}

    parameters['CIC_R'] = R
    parameters['CIC_M'] = M
    parameters['CIC_N'] = N
    parameters['INP_DW'] = INP_DW
    parameters['OUT_DW'] = OUT_DW
    parameters['RATE_DW'] = RATE_DW
    parameters['VAR_RATE'] = VAR_RATE
    parameters['EXACT_SCALING'] = EXACT_SCALING    
    if PRECALCULATE_PRUNE_BITS:
        parameters['PRUNE_BITS'] = calculate_prune_bits(R, N, M, INP_DW, OUT_DW)

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}
    sim_build="sim_build/" + "_".join(("{}={}".format(*i) for i in parameters.items()))
    cocotb_test.simulator.run(
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        includes=includes,
        toplevel=toplevel,
        module=module,
        parameters=parameters,
        sim_build=sim_build,
        extra_env=extra_env,
        testcase="simple_test",
    )
    
@pytest.mark.parametrize("R", [4095])    # max rate
@pytest.mark.parametrize("N", [6, 3])
@pytest.mark.parametrize("M", [1, 2])
@pytest.mark.parametrize("INP_DW", [32])
@pytest.mark.parametrize("OUT_DW", [32, 14])
@pytest.mark.parametrize("RATE_DW", [16])
@pytest.mark.parametrize("CALC_PRUNING", [1])
@pytest.mark.parametrize("VAR_RATE", [1])
@pytest.mark.parametrize("EXACT_SCALING", [1, 0])
def test_cic_d_variable_rate(request, R, N, M, INP_DW, OUT_DW, RATE_DW, VAR_RATE, EXACT_SCALING, CALC_PRUNING):
    dut = "cic_d"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(rtl_dir, "comb.sv"),
        os.path.join(rtl_dir, "integrator.sv"),
        os.path.join(rtl_dir, "downsampler.sv"),
        os.path.join(rtl_dir, "downsampler_variable.sv"),
    ]
    includes = [
        os.path.join(rtl_dir, ""),
        os.path.join(rtl_dir, "cic_functions.vh"),
    ]    

    parameters = {}

    parameters['CIC_R'] = R
    parameters['CIC_M'] = M
    parameters['CIC_N'] = N
    parameters['INP_DW'] = INP_DW
    parameters['OUT_DW'] = OUT_DW
    parameters['RATE_DW'] = RATE_DW
    parameters['VAR_RATE'] = VAR_RATE
    parameters['EXACT_SCALING'] = EXACT_SCALING
    if CALC_PRUNING:
        parameters['PRUNE_BITS'] = calculate_prune_bits(R, N, M, INP_DW, OUT_DW)

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}
    sim_build="sim_build/" + "_".join(("{}={}".format(*i) for i in parameters.items()))
    cocotb_test.simulator.run(
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        includes=includes,
        toplevel=toplevel,
        module=module,
        parameters=parameters,
        sim_build=sim_build,
        extra_env=extra_env,
        testcase="variable_rate_test",        
    )    
    
@pytest.mark.parametrize("R", [4095])    # max rate
@pytest.mark.parametrize("N", [3, 5])
@pytest.mark.parametrize("M", [1])
@pytest.mark.parametrize("INP_DW", [32])
@pytest.mark.parametrize("OUT_DW", [32])
@pytest.mark.parametrize("RATE_DW", [32])
@pytest.mark.parametrize("VAR_RATE", [1])
@pytest.mark.parametrize("EXACT_SCALING", [0, 1])
@pytest.mark.parametrize("PRG_SCALING", [1])
@pytest.mark.parametrize("CALC_PRUNING", [1])
def test_cic_d_programmable_scaling(request, R, N, M, INP_DW, OUT_DW, RATE_DW, VAR_RATE, EXACT_SCALING, PRG_SCALING, CALC_PRUNING):
    dut = "cic_d"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(rtl_dir, "comb.sv"),
        os.path.join(rtl_dir, "integrator.sv"),
        os.path.join(rtl_dir, "downsampler.sv"),
        os.path.join(rtl_dir, "downsampler_variable.sv"),
    ]
    includes = [
        os.path.join(rtl_dir, ""),
        os.path.join(rtl_dir, "cic_functions.vh"),
    ]    

    parameters = {}

    parameters['CIC_R'] = R
    parameters['CIC_M'] = M
    parameters['CIC_N'] = N
    parameters['INP_DW'] = INP_DW
    parameters['OUT_DW'] = OUT_DW
    parameters['RATE_DW'] = RATE_DW
    parameters['VAR_RATE'] = VAR_RATE
    parameters['EXACT_SCALING'] = EXACT_SCALING
    parameters['NUM_SHIFT'] = 5*N
    parameters['PRG_SCALING'] = PRG_SCALING
    if CALC_PRUNING:
        parameters['PRUNE_BITS'] = calculate_prune_bits(R, N, M, INP_DW, OUT_DW)

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}
    sim_build="sim_build/" + "_".join(("{}={}".format(*i) for i in parameters.items()))
    cocotb_test.simulator.run(
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        includes=includes,
        toplevel=toplevel,
        module=module,
        parameters=parameters,
        sim_build=sim_build,
        extra_env=extra_env,
        testcase="programmable_scaling_test",        
    )    
    
