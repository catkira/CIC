# CIC Filter with Python testbenches

This project is based on https://opencores.org/projects/cic_core_2

The main addition is a python model and unit tests in python using cocotb

To run the unit tests install
- python 3.8
- iverilog 1.4
- pip3 install cocotb, cocotb_test, pytest,

and run pytest in the repo directory


# License
for old code from opencores LGPL

for new code GPL


# Old README.md

It is the CIC filter with Hogenauer pruning.
This project is based on https://opencores.org/projects/cic_core project.

Differences are listed below:
* calculations of pruning with large decimation ratio is improved ;
* project is rewritten in Verilog and simulated with Icarus;
* incorrect widths of registers of integrators and combs are fixed;

Getting sarted

* /rtl/verilog/cic\_d.sv - CIC filter decimator
* /rtl/verilog/cic\_functions.vh - functions for calculation parameters of CIC filter
* /rtl/verilog/comb.sv - comb part of CIC filter
* /rtl/verilog/downsampler.sv - downsampler part of CIC filter
* /rtl/verilog/integrator.sv - integrator of CIC filter

* /sim/rtl\_sim/run/cic\_d\_run_sim.sh - script to run simulation with Icarus Verilog
* /sim/rtl\_sim/run/cic\_d\_tb.gtkw - list of signals to watch with GTKWave
* /sim/rtl\_sim/src/cic\_d\_tb.sv - testbench for CIC filter decimator

Prerequisities

Icarus Verilog is used for simulation 
GTKWave is used for watching the results of simulation

Running the tests

To see simulation results run
/sim/rtl\_sim/bin/cic\_d\_run\_sim.sh

open output .vcd file with GTKWave
load list of signals to watch from cic\_d_tb.gtkw

Authors

Egor Ibragimov

Licence

LGPL