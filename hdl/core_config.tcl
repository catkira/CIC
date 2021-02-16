set display_name {CIC}

set core [ipx::current_core]

set_property DISPLAY_NAME $display_name $core
set_property DESCRIPTION $display_name $core

core_parameter INP_DW {OPERAND WIDTH INPUT} {Width of the data-in-a operands}
core_parameter OUT_DW {OPERAND WIDTH OUTPUT} {Width of the data-in-b operands}
core_parameter RATE_DW {OPERAND WIDTH OUTPUT} {Width of the rate operands}
core_parameter CIC_R  {R} {R - max R if variable rate is used}
core_parameter CIC_N  {N} {N}
core_parameter CIC_M  {M} {M}
core_parameter PRUNE_BITS      {PRUNE_BITS} {precalculated prune bits, set zero if not used}
core_parameter VARIABLE_RATE   {VARIABLE_RATE} {one if variable rate is used, zero otherwise}

set bus [ipx::get_bus_interfaces -of_objects $core s_axis_in]
set_property NAME S_AXIS_IN $bus
set_property INTERFACE_MODE slave $bus

set bus [ipx::get_bus_interfaces -of_objects $core s_axis_rate]
set_property NAME S_AXIS_RATE $bus
set_property INTERFACE_MODE slave $bus

set bus [ipx::get_bus_interfaces -of_objects $core m_axis_out]
set_property NAME M_AXIS_OUT $bus
set_property INTERFACE_MODE master $bus

set bus [ipx::get_bus_interfaces clk]
set parameter [ipx::get_bus_parameters -of_objects $bus ASSOCIATED_BUSIF]
set_property VALUE S_AXIS_IN:S_AXIS_RATE:M_AXIS_OUT $parameter
