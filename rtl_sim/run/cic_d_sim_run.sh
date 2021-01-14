#!/bin/sh
PATH_CIC=../../rtl/verilog
mkdir -p ../out
iverilog -g2005-sv -g2012 -o ../out/cic_d.out -I $PATH_CIC/ $PATH_CIC/cic_functions.vh $PATH_CIC/cic_d.sv $PATH_CIC/integrator.sv $PATH_CIC/comb.sv $PATH_CIC/downsampler.sv ../src/cic_d_tb.sv || exit	# if error then stop
echo "iverilog ready, run vvp"
vvp ../out/cic_d.out
echo "vvp ready"