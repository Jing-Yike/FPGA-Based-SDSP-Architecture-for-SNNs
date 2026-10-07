if {![info exists ::env(SNN_SIM_RTL_DIR)] || ![info exists ::env(SNN_SIM_TB)] || ![info exists ::env(SNN_SIM_PROJECT_DIR)]} {
    error "Set SNN_SIM_RTL_DIR, SNN_SIM_TB, and SNN_SIM_PROJECT_DIR"
}

set rtl_dir [file normalize $::env(SNN_SIM_RTL_DIR)]
set tb_file [file normalize $::env(SNN_SIM_TB)]
set project_dir [file normalize $::env(SNN_SIM_PROJECT_DIR)]
set sim_top tb_layer_step_output
if {[info exists ::env(SNN_SIM_TOP)]} {
    set sim_top $::env(SNN_SIM_TOP)
}
set rtl_files [lsort [glob -nocomplain [file join $rtl_dir *.vhd]]]

if {[llength $rtl_files] != 38} {
    error "Expected 38 RTL files, found [llength $rtl_files]"
}

create_project layer_output_sim $project_dir -part xc7z020clg400-1 -force
set_property target_language VHDL [current_project]
add_files -norecurse $rtl_files
foreach source $rtl_files {
    set_property FILE_TYPE {VHDL 2008} [get_files $source]
}
add_files -fileset sim_1 -norecurse $tb_file
set_property FILE_TYPE {VHDL 2008} [get_files $tb_file]
set_property top $sim_top [get_filesets sim_1]
if {[info exists ::env(SNN_SIM_GENERIC)]} {
    set_property generic $::env(SNN_SIM_GENERIC) [get_filesets sim_1]
}
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
run 2 ms
set sim_log [file join $project_dir layer_output_sim.sim sim_1 behav xsim simulate.log]
if {![file exists $sim_log]} {
    error "Missing XSim output log: $sim_log"
}
set log_handle [open $sim_log r]
set sim_output [read $log_handle]
close $log_handle
if {[string first "Failure:" $sim_output] >= 0 ||
    [string first "RESULT " $sim_output] < 0} {
    error "Simulation failed or did not complete; inspect $sim_log"
}
close_sim
close_project
