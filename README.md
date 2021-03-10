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

## Rounding
In signal processing applications it is usually desired to have a rounding method that does not produce a dc bias, these methods are called symmetric. They work by rounding up or down to the nearest integer whether the decimal value is larger or smaller than 0.5. If the decimal value is is exactly 0.5 a tie-breaker is needed. A commonly used method is [round-half-to-even](https://en.wikipedia.org/wiki/Rounding#Round_half_to_even), this is also the default method of the round() function in Python and in the IEEE 754 floating point standard. Xilinx and [Matlab](https://de.mathworks.com/help/fixedpoint/ug/rounding-mode-convergent.html) call this method *convergent rounding towards even*.
Another possibility is to use alternate or random tie-breaking. However alternate tie-breaking needs to remember the last rounding direction and random tie-breakign needs a random source. Some DSP components like the Xilinx complex multiplier use random tie-breaking and have a separate input, for the bit that decides tie-breaking. Depending on that bit it switches between round-half-up and round-half-down.
I have not yet decided whether to implement round-half-to-even or random tie-breaking for this CIC.

### Rounding in Xilinx FPGAs using the DSP48 units
This [document](https://www.xilinx.com/support/documentation/user_guides/ug193.pdf) describes different rounding methods that can efficiently be implemented on a DSP48 unit. Random rounding can easily be implemented by toggling the CARRYIN bit of a correctly configured DSP48 unit randomly. The symmetric rounding methods round-to-zero and round-to-infinity can also easily be implemented by usin the CARRYIN bit as described [here](https://www.xilinx.com/support/documentation/user_guides/ug193.pdf). 
Convergent rounding like round-half-to-even can also be implemented using the CARRYIN bit. But in this case the value of CARRYIN depends on the actual number, so it cannot be determined ahead of time. This calculation requires additional logic outside of the DSP48. [ug193](https://www.xilinx.com/support/documentation/user_guides/ug193.pdf) shows an example how the pattern matching facility of the DSP48 can be used for convergent rounding. This is especially simple when doing static convergent rounding (rounding bit is always at the same decimal position).

### Rounding in other CICs
The Xilinx CIC core does not specify how it performs rounding. The datasheet of the HSP43220 says that it uses symmetric rounding, but not which method exactly.

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

## References
- HSP50214 datasheet
- HSP43220 datasheet
- https://opencores.org/projects/cic_core_2
- https://opencores.org/projects/cic_core
- https://en.wikipedia.org/wiki/Rounding
- https://realpython.com/python-rounding/
- https://zipcpu.com/dsp/2017/07/22/rounding.html
- https://patents.google.com/patent/US20080028014A1/en
- https://www.xilinx.com/support/documentation/user_guides/ug193.pdf
- https://www.dsprelated.com/showarticle/1337.php
- https://www.design-reuse.com/articles/10028/understanding-cascaded-integrator-comb-filters.html
- https://www.dsprelated.com/showcode/269.php
- http://www.tsdconseil.fr/log/scriptscilab/cic/cic-en.pdf
- http://threespeedlogic.com/cic-compensation.html
- https://www.intel.com/content/dam/www/programmable/us/en/pdfs/literature/an/an455.pdf
- https://www.koheron.com/blog/2016/10/03/decimator-cic-filter
- https://liquidsdr.org/blog/firdespm-invsinc/


## License
GPL
(for old code from opencores LGPL)



