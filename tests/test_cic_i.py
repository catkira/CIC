import random
import os
import logging
import cocotb_test.simulator
import pytest
import math
import numpy as np
import importlib.util

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

CLK_PERIOD_NS = 8
CLK_PERIOD_S = CLK_PERIOD_NS * 0.000000001


class TB(object):
    def __init__(self, dut):
        random.seed(30)  # reproducible tests
        self.dut = dut
        self.R = int(dut.r.value)
        self.N = int(dut.m.value)   # CIC order
        self.M = int(dut.g.value)   # differential delay
        self.INP_DW = int(dut.dw.value)

        # compute output width same as RTL: dw + $clog2((r**m)/r)
        interp_gain = (self.R ** self.N) // self.R
        if interp_gain > 1:
            self.OUT_DW = self.INP_DW + math.ceil(math.log2(interp_gain))
        else:
            self.OUT_DW = self.INP_DW

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        tests_dir = os.path.abspath(os.path.dirname(__file__))
        model_dir = os.path.abspath(os.path.join(tests_dir, '../model/cic_i_model.py'))
        spec = importlib.util.spec_from_file_location("cic_i_model", model_dir)
        foo = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(foo)
        self.model = foo.Model(self.R, self.N, self.M, self.INP_DW, self.OUT_DW)
        cocotb.start_soon(Clock(self.dut.clk, CLK_PERIOD_NS, units='ns').start())

    async def cycle_reset(self):
        self.dut.in_dv.value = 0
        self.dut.reset_n.setimmediatevalue(1)
        await RisingEdge(self.dut.clk)
        self.dut.reset_n.value = 0
        await RisingEdge(self.dut.clk)
        self.dut.reset_n.value = 1
        await RisingEdge(self.dut.clk)
        self.model.reset()


def signed_val(val, width):
    """Convert unsigned integer to signed."""
    if (val & (1 << (width - 1))) != 0:
        return val - (1 << width)
    return val


@cocotb.test()
async def simple_test(dut):
    tb = TB(dut)
    await tb.cycle_reset()

    tolerance = 1

    # input generation state
    phase = 0
    freq = 10000
    phase_step = CLK_PERIOD_S * tb.R * 2 * freq * math.pi
    print(f"normalized freq = {CLK_PERIOD_S * freq:.12f} Hz")

    # warmup: let pipeline prime before collecting output
    warmup_cycles = 3 * tb.R + 2 * tb.N
    num_collect = 300

    rtl_buf = []
    model_buf = []
    cycle_count = 0

    for _ in range(warmup_cycles + num_collect):
        await RisingEdge(dut.clk)
        # model.tick() here processes the PREVIOUS cycle's set_data,
        # aligned with the DUT which also processes previous cycle's signals
        tb.model.tick()

        # collect output after warmup
        if cycle_count >= warmup_cycles:
            a = dut.data_out.value.integer
            a = signed_val(a, tb.OUT_DW)
            rtl_buf.append(a)
            model_buf.append(int(tb.model.get_scaled_data()))

        # drive new input for NEXT cycle
        if cycle_count % tb.R == 0:
            phase += phase_step
            value = int(np.round(math.sin(phase) * (2 ** (tb.INP_DW - 1) - 1)))
            tb.model.set_data(value)
            dut.data_in.value = value
            dut.in_dv.value = 1
        else:
            dut.in_dv.value = 0

        cycle_count += 1

    # compare — allow small alignment offset for any residual pipeline difference
    num_compare = 200
    best_offset = 0
    best_err = float('inf')
    for offset in range(-10, 11):
        err = 0
        count = 0
        for i in range(num_compare):
            j = i + offset
            if 0 <= j < len(rtl_buf) and i < len(model_buf):
                err += abs(model_buf[i] - rtl_buf[j])
                count += 1
        if count > 0 and err / count < best_err:
            best_err = err / count
            best_offset = offset

    print(f"alignment offset: {best_offset}  avg_err: {best_err:.2f}")

    for i in range(num_compare):
        j = i + best_offset
        if 0 <= j < len(rtl_buf):
            print(f"hdl: \t[{i}]\t {rtl_buf[j]} \t model: \t {model_buf[i]}")
            assert np.abs(rtl_buf[j] - model_buf[i]) <= tolerance, \
                f"[{i}] hdl: {rtl_buf[j]} \t model: {model_buf[i]} \t offset: {best_offset}"


# cocotb-test

tests_dir = os.path.abspath(os.path.dirname(__file__))
rtl_dir = os.path.abspath(os.path.join(tests_dir, '..', 'hdl'))


@pytest.mark.parametrize("r", [4, 10])
@pytest.mark.parametrize("m", [3, 6])
@pytest.mark.parametrize("g", [1, 2])
@pytest.mark.parametrize("dw", [8, 16])
def test_cic_i(request, r, m, g, dw):
    dut = "cic_i"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(rtl_dir, "comb.sv"),
        os.path.join(rtl_dir, "integrator.sv"),
    ]
    includes = [
        os.path.join(rtl_dir, ""),
    ]

    parameters = {}
    parameters['r'] = r
    parameters['m'] = m
    parameters['g'] = g
    parameters['dw'] = dw

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}
    sim_build = "sim_build/" + "_".join(("{}={}".format(*i) for i in parameters.items()))
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
