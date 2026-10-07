# Package the existing SNN + SDSP RTL as one AXI peripheral.
# Source this file in Vivado, or run: vivado -mode batch -source package_snn_sdsp_ip.tcl
# Output root may be overridden with PYNQ_Z1_IP_BUILD_DIR.

set ip_script_dir [file dirname [file normalize [info script]]]
set ip_rtl_dir [file normalize [file join $ip_script_dir .. rtl_ip]]
if {[info exists ::env(PYNQ_Z1_IP_BUILD_DIR)]} {
    set ip_build_dir [file normalize $::env(PYNQ_Z1_IP_BUILD_DIR)]
} else {
    set ip_build_dir [file normalize [file join $ip_script_dir build]]
}
set ip_core_dir [file join $ip_build_dir ip_repo snn_sdsp_accelerator_1_0]
set ip_project_dir [file join $ip_build_dir ip_pack_project]

foreach path [list $ip_rtl_dir $ip_build_dir] {
    if {[regexp {[^\x00-\x7f]} $path]} {
        error "Vivado source/build path contains non-ASCII characters: $path. Copy SourceCode to an ASCII-only path and run there."
    }
}
if {![file isdirectory $ip_rtl_dir]} {
    error "Missing RTL directory: $ip_rtl_dir"
}
set ip_sources [lsort [glob -nocomplain [file join $ip_rtl_dir *.vhd]]]
if {[llength $ip_sources] != 38} {
    error "Expected 38 VHDL files in rtl_ip; found [llength $ip_sources]. Check the source copy."
}
if {![file exists [file join $ip_rtl_dir snn_axi_wrapper.vhd]]} {
    error "Missing IP top: snn_axi_wrapper.vhd"
}

file mkdir $ip_build_dir
if {[llength [get_projects -quiet]] != 0} { close_project }
create_project snn_sdsp_ip_pack $ip_project_dir -part xc7z020clg400-1 -force
set_property TARGET_LANGUAGE VHDL [current_project]
add_files -norecurse $ip_sources
foreach source $ip_sources {
    set_property FILE_TYPE {VHDL 2008} [get_files $source]
}
set_property top snn_axi_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

# Import the sources into the IP repository so it does not depend on the
# temporary packaging project or on the original RTL directory.
ipx::package_project -root_dir $ip_core_dir \
    -vendor thesis.local -library user -name snn_sdsp_accelerator \
    -version 1.0 -taxonomy /UserIP -import_files -set_current true -force
set ip_core [ipx::current_core]
set_property display_name {SNN SDSP Accelerator} $ip_core
set_property description {784-input 10-output SNN with online SDSP learning and AXI interfaces} $ip_core

foreach interface_name {s_axi s_axis aclk aresetn irq} {
    if {[llength [ipx::get_bus_interfaces $interface_name -of_objects $ip_core]] != 1} {
        error "IP Packager did not infer interface '$interface_name'."
    }
}
set axi_if [ipx::get_bus_interfaces s_axi -of_objects $ip_core]
set axis_if [ipx::get_bus_interfaces s_axis -of_objects $ip_core]
if {[get_property INTERFACE_MODE $axi_if] ne "slave" ||
    [get_property INTERFACE_MODE $axis_if] ne "slave"} {
    error "Expected AXI4-Lite and AXI4-Stream slave interfaces."
}

# The RTL decodes offsets 0x00..0x54. Keep the software-visible 64 KiB
# aperture used by the existing system, rather than the inferred 4 GiB.
set addr_blocks [ipx::get_address_blocks -of_objects \
    [ipx::get_memory_maps s_axi -of_objects $ip_core]]
if {[llength $addr_blocks] != 1} {
    error "Expected one AXI-Lite address block; found [llength $addr_blocks]."
}
set_property range 0x00010000 $addr_blocks

set clk_if [ipx::get_bus_interfaces aclk -of_objects $ip_core]
set clk_freq [ipx::add_bus_parameter FREQ_HZ $clk_if]
set_property value 100000000 $clk_freq
set clk_assoc [ipx::add_bus_parameter ASSOCIATED_BUSIF $clk_if]
set_property value {s_axis:s_axi} $clk_assoc
set clk_reset [ipx::add_bus_parameter ASSOCIATED_RESET $clk_if]
set_property value aresetn $clk_reset

if {![ipx::check_integrity $ip_core]} {
    error "IP integrity check failed; inspect Vivado IP Packager messages."
}
ipx::save_core $ip_core
if {![file exists [file join $ip_core_dir component.xml]]} {
    error "IP package did not create component.xml."
}
puts "Packaged [get_property VLNV $ip_core]"
puts "IP repository: $ip_core_dir"
puts "The packaging project remains open; the project script will close it."
