# Set the library directory
set libdir ./work

# Create a new library if it doesn't exist
if {![file exists $libdir]} {
    vlib $libdir
}
vmap work $libdir

# Compile the Verilog source files
# vlog -sv17compat -vopt -override_timescale=1ns/1ps +notimingchecks +delay_mode_zero -work WORK -64 -O1 -mfcu  +cover +acc=npr -assertdebug -bitscalars -floatparameters -cover bcest -f flist_rtl.f
vlog -sv17compat -vopt -override_timescale=1ns/1ps +notimingchecks +delay_mode_zero -work WORK -64 -O1 -mfcu  +cover +acc=npr -assertdebug -bitscalars -floatparameters -cover bcest -f flist_netlist.f

# Run the simulation
vsim -t 1ps -lib work tb_Block_PE_wrapper

# Set up waveforms (optional, for viewing in the waveform viewer)
add wave -r /*
run -all
