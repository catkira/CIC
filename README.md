# CIC Filter with Python testbenches

This project is based on https://opencores.org/projects/cic_core_2 by Egor Igragimov.

The main additions are
- optimized pipeline structure of comb section -> has much less delay now
- register pruning calculation outside of hdl code -> great speed up for sim and synth if R is large
- python model for simulation
- unit tests using cocotb and cocotb-test

To run the unit tests install
- python 3.8
- iverilog 1.4
- pip3 install cocotb, cocotb_test, pytest,

and run pytest in the repo directory

# SMALL_FOOTPRINT Option

if SMALL_FOOTPRINT is 1, the outputs of the comb stages are buffered with a register. This additional pipelining isolates the adder of the comb from the following logic and therefore allows higher clock speeds. The drawback is a higher latency.

SMALL_FOOTPRINT = 1 requires CIC_R > CIC_N to give N clock cycles to the adders of the comb stages.

If one adder is much faster than one clock cycle, the number of delays for the comb stages can be reduced, ie to CIC_N/2.


# License
for old code from opencores LGPL

for new code GPL


