# CIC Decimator
## Overview
This project is based on https://opencores.org/projects/cic_core_2 by Egor Igragimov and on https://opencores.org/projects/cic_core by Vadim Kotelnikov.

The main differences are
- added variable/programmable downsampling rate
- added programmable pre and post scaling
- optimized pipeline structure of comb section -> has much less delay now
- register pruning calculation outside of hdl code -> great speed up for sim and synth if R is large
- python model for simulation
- unit tests using cocotb and cocotb-test

## Parameters
- INP_DW
- OUT_DW
- RATE_DW
- CIC_R
- CIC_N
- CIC_M
- PRUNE_BITS
- VAR_RATE
- EXACT_SCALING
- PRG_SCALING
- NUM_SHIFT

## Ports
- clk
- reset_n
- s_axis_in
- s_axis_rate
- m_axis_out

## Verification
To run the unit tests install
- python >3.8
- iverilog >1.4
- python modules: cocotb, cocotb_test, pytest, pytest-parallel, pytest-cov

and run pytest in the repo directory
```
pytest -v --workers 10
```

## TODO
- add CIC interpolator
- add rounding to last stage of decimator

## License
GPL
(for old code from opencores LGPL)



