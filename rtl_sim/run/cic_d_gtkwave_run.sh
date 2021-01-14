#!/bin/sh
gtkwave ../out/cic_d_tb.vcd ./cic_d_tb.gtkw
#shmidcat ../out/cic_d_tb.vcd | gtkwave -v -I ./cic_d_tb.gtkw