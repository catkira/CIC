PWD     =  $(shell pwd)
SIM     ?=  icarus

DUT         = cic_d
TOPLEVEL    = $(DUT)
MODULE      = spectral_analysis

VERILOG_SOURCES = $(PWD)/../hdl/*.sv

# module parameters
export CIC_R            ?= 128
export CIC_N            ?= 6
export CIC_M            ?= 1
export INP_DW       ?= 16
export OUT_DW       ?= 32
export RATE_DW      ?= 16
export NUM_SHIFT    ?= 10
export EXACT_SCALING ?= 0
export PRG_SCALING   ?= 1
export VAR_RATE      ?= 1
export PRUNE_BITS    ?= 0

# for verilator and icarus
COMPILE_ARGS += -I$(PWD)/../hdl/

ifeq ($(SIM), icarus)
    COMPILE_ARGS += -Pcic_d.CIC_R=$(CIC_R)
	COMPILE_ARGS += -Pcic_d.CIC_N=$(CIC_N)
	COMPILE_ARGS += -Pcic_d.CIC_M=$(CIC_M)
	COMPILE_ARGS += -Pcic_d.INP_DW=$(INP_DW)
	COMPILE_ARGS += -Pcic_d.OUT_DW=$(OUT_DW)
	COMPILE_ARGS += -Pcic_d.RATE_DW=$(RATE_DW)
	COMPILE_ARGS += -Pcic_d.NUM_SHIFT=$(NUM_SHIFT)
	COMPILE_ARGS += -Pcic_d.EXACT_SCALING=$(EXACT_SCALING)
	COMPILE_ARGS += -Pcic_d.PRG_SCALING=$(PRG_SCALING)
	COMPILE_ARGS += -Pcic_d.VAR_RATE=$(VAR_RATE)
	COMPILE_ARGS += -Pcic_d.PRUNE_BITS=$(PRUNE_BITS)
endif


ifeq ($(SIM), verilator)
    EXTRA_ARGS += $(PWD)/verilator_waiver.vlt
    VERILATOR_TRACE = 1
	#COMPILE_ARGS += -Wno-SELRANGE -Wno-WIDTH -Wno-CASEINCOMPLETE

	COMPILE_ARGS += -GR=$(R)
	COMPILE_ARGS += -GN=$(N)
	COMPILE_ARGS += -GM=$(M)
	COMPILE_ARGS += -GINP_DW=$(INP_DW)
	COMPILE_ARGS += -GOUT_DW=$(OUT_DW)
	COMPILE_ARGS += -GRATE_DW=$(RATE_DW)
	COMPILE_ARGS += -GNUM_SHIFT=$(NUM_SHIFT)
	COMPILE_ARGS += -GEXACT_SCALING=$(EXACT_SCALING)
	COMPILE_ARGS += -GPRG_SCALING=$(PRG_SCALING)
	COMPILE_ARGS += -GVAR_RATE=$(VAR_RATE)
	COMPILE_ARGS += -GPRUNE_BITS=$(PRUNE_BITS)
endif


include $(shell cocotb-config --makefiles)/Makefile.sim