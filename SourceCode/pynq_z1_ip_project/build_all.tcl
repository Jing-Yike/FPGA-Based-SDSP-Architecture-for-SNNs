# One-command entry point. The project stays open for inspection/bitstream.
set all_script_dir [file dirname [file normalize [info script]]]
source [file join $all_script_dir package_snn_sdsp_ip.tcl]
source [file join $all_script_dir create_pynq_z1_ip_project.tcl]
