# Standalone BRAM-inference check. Run from an ASCII-only source path.
set check_dir [file dirname [file normalize [info script]]]
set rtl_dir [file normalize [file join $check_dir .. rtl_ip]]
create_project -in_memory -part xc7z020clg400-1
read_vhdl -vhdl2008 [list \
    [file join $rtl_dir full_system_pkg.vhd] \
    [file join $rtl_dir exc_weight_ram_sdsp.vhd]]
synth_design -top exc_weight_ram_sdsp -part xc7z020clg400-1 -no_iobuf
set ram18 [get_cells -quiet -hier -filter {REF_NAME =~ RAMB18*}]
set ram36 [get_cells -quiet -hier -filter {REF_NAME =~ RAMB36*}]
puts "BRAM_INFERENCE RAMB18=[llength $ram18] RAMB36=[llength $ram36]"
if {[llength $ram18] + [llength $ram36] == 0} {
    error "No block RAM primitive was inferred for exc_weight_ram_sdsp"
}
