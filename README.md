# CIC Filter with Python testbenches

This project is based on https://opencores.org/projects/cic_core_2 by Egor Igragimov.

The main additions and changes are
- added variable downsampling rate
- optimized pipeline structure of comb section -> has much less delay now
- register pruning calculation outside of hdl code -> great speed up for sim and synth if R is large
- python model for simulation
- unit tests using cocotb and cocotb-test

To run the unit tests install
- python 3.8
- iverilog 1.4
- pip3 install cocotb, cocotb_test, pytest,

and run pytest in the repo directory

# TODO
- write test with variable rate
- make interpolating CIC up to date

# License
for old code from opencores LGPL

for new code GPL


