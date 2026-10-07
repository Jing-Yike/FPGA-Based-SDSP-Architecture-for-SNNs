# PYNQ-Z1 project: PS + DDR + MM2S DMA + SNN/SDSP custom IP inside the BD.
# Run package_snn_sdsp_ip.tcl first, or source build_all.tcl.
# Optional environment variables:
#   PYNQ_Z1_IP_BUILD_DIR  ASCII-only output directory (default: ./build)
#   PYNQ_Z1_BOARD_REPO    directory containing the Digilent PYNQ-Z1 board files

set system_script_dir [file dirname [file normalize [info script]]]
if {[info exists ::env(PYNQ_Z1_IP_BUILD_DIR)]} {
    set system_build_dir [file normalize $::env(PYNQ_Z1_IP_BUILD_DIR)]
} else {
    set system_build_dir [file normalize [file join $system_script_dir build]]
}
set system_core_dir [file join $system_build_dir ip_repo snn_sdsp_accelerator_1_0]
set system_project_dir [file join $system_build_dir pynq_z1_snn_sdsp_project]
set system_vlnv thesis.local:user:snn_sdsp_accelerator:1.0
set system_board_vlnv www.digilentinc.com:pynq-z1:part0:1.0
set system_bd_name pynq_z1_snn_sdsp

foreach path [list $system_script_dir $system_build_dir] {
    if {[regexp {[^\x00-\x7f]} $path]} {
        error "Vivado path contains non-ASCII characters: $path. Copy SourceCode to an ASCII-only path and run there."
    }
}
if {![file exists [file join $system_core_dir component.xml]]} {
    error "Packaged IP not found at $system_core_dir. Source package_snn_sdsp_ip.tcl first."
}

proc add_z1_board_repo {repo_path} {
    if {$repo_path eq "" || ![file isdirectory $repo_path]} { return }
    set_param board.repoPaths [lsort -unique \
        [concat [get_param board.repoPaths] [file normalize $repo_path]]]
}
if {[info exists ::env(PYNQ_Z1_BOARD_REPO)]} {
    add_z1_board_repo $::env(PYNQ_Z1_BOARD_REPO)
}
# Reuse a PYNQ-Z1 board definition installed by Vivado Board Store.
if {[info exists ::env(APPDATA)]} {
    foreach name_pattern {PYNQ-Z1 pynq-z1} {
        set xml_pattern [file join $::env(APPDATA) Xilinx Vivado * xhub \
            board_store * * Vivado * boards * $name_pattern * board.xml]
        foreach board_xml [glob -nocomplain $xml_pattern] {
            set board_repo [file normalize $board_xml]
            for {set level 0} {$level < 4} {incr level} {
                set board_repo [file dirname $board_repo]
            }
            add_z1_board_repo $board_repo
        }
    }
}

if {[llength [get_board_parts -quiet $system_board_vlnv]] == 0} {
    error "PYNQ-Z1 board definition '$system_board_vlnv' is unavailable. Install it in Vivado or set PYNQ_Z1_BOARD_REPO. The board preset is required for correct PS DDR/MIO configuration."
}
if {[llength [get_projects -quiet]] != 0} { close_project }
create_project pynq_z1_snn_sdsp $system_project_dir \
    -part xc7z020clg400-1 -force
set_property BOARD_PART $system_board_vlnv [current_project]
set_property TARGET_LANGUAGE VHDL [current_project]
set_property IP_REPO_PATHS [list $system_core_dir] [current_project]
update_ip_catalog
if {[llength [get_ipdefs -all -quiet $system_vlnv]] == 0} {
    error "Packaged SNN IP is not visible in Vivado IP Catalog: $system_vlnv"
}
foreach required_ip {
    xilinx.com:ip:processing_system7:5.5
    xilinx.com:ip:proc_sys_reset:5.0
    xilinx.com:ip:axi_dma:7.1
    xilinx.com:ip:axis_data_fifo:2.0
    xilinx.com:ip:smartconnect:1.0
    xilinx.com:ip:xlconcat:2.1
} {
    if {[llength [get_ipdefs -all -quiet $required_ip]] == 0} {
        error "Required Vivado IP is unavailable: $required_ip"
    }
}

create_bd_design $system_bd_name
current_bd_design $system_bd_name

# The PYNQ-Z1 board preset supplies DDR timing and PS MIO pin settings.
set ps7 [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {apply_board_preset "1" make_external "FIXED_IO, DDR"} $ps7
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.000000} \
] $ps7

set rst [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_0_100M]
connect_bd_net [get_bd_pins $ps7/FCLK_CLK0] \
    [get_bd_pins $rst/slowest_sync_clk] \
    [get_bd_pins $ps7/M_AXI_GP0_ACLK] \
    [get_bd_pins $ps7/S_AXI_HP0_ACLK]
connect_bd_net [get_bd_pins $ps7/FCLK_RESET0_N] \
    [get_bd_pins $rst/ext_reset_in]

# DDR -> DMA (MM2S) -> stream FIFO -> SNN input.
set dma [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_mm2s]
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {0} \
    CONFIG.c_sg_length_width {26} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_include_mm2s_dre {0} \
    CONFIG.c_mm2s_burst_size {64} \
] $dma
set fifo [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:axis_data_fifo:2.0 axis_fifo_snn]
set_property -dict [list \
    CONFIG.TDATA_NUM_BYTES {4} \
    CONFIG.FIFO_DEPTH {512} \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
] $fifo
set snn [create_bd_cell -type ip -vlnv $system_vlnv snn_sdsp_0]
connect_bd_intf_net [get_bd_intf_pins $dma/M_AXIS_MM2S] \
    [get_bd_intf_pins $fifo/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins $fifo/M_AXIS] \
    [get_bd_intf_pins $snn/s_axis]

# GP0 configures both the DMA and the SNN AXI4-Lite register bank.
set ctrl_smc [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:smartconnect:1.0 axi_ctrl_smc]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] $ctrl_smc
connect_bd_intf_net [get_bd_intf_pins $ps7/M_AXI_GP0] \
    [get_bd_intf_pins $ctrl_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $ctrl_smc/M00_AXI] \
    [get_bd_intf_pins $dma/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins $ctrl_smc/M01_AXI] \
    [get_bd_intf_pins $snn/s_axi]

# DMA reads its source buffer in PS DDR through HP0.
set hp_smc [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:smartconnect:1.0 axi_hp0_smc]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $hp_smc
connect_bd_intf_net [get_bd_intf_pins $dma/M_AXI_MM2S] \
    [get_bd_intf_pins $hp_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $hp_smc/M00_AXI] \
    [get_bd_intf_pins $ps7/S_AXI_HP0]

foreach pin_name {
    axi_dma_mm2s/s_axi_lite_aclk
    axi_dma_mm2s/m_axi_mm2s_aclk
    axis_fifo_snn/s_axis_aclk
    axi_ctrl_smc/aclk
    axi_hp0_smc/aclk
    snn_sdsp_0/aclk
} {
    set pin [get_bd_pins -quiet $pin_name]
    if {[llength $pin] != 1} { error "Missing clock pin: $pin_name" }
    connect_bd_net [get_bd_pins $ps7/FCLK_CLK0] $pin
}
foreach pin_name {
    axi_dma_mm2s/axi_resetn
    axis_fifo_snn/s_axis_aresetn
    snn_sdsp_0/aresetn
} {
    set pin [get_bd_pins -quiet $pin_name]
    if {[llength $pin] != 1} { error "Missing peripheral reset pin: $pin_name" }
    connect_bd_net [get_bd_pins $rst/peripheral_aresetn] $pin
}
foreach pin_name {axi_ctrl_smc/aresetn axi_hp0_smc/aresetn} {
    set pin [get_bd_pins -quiet $pin_name]
    if {[llength $pin] != 1} { error "Missing interconnect reset pin: $pin_name" }
    connect_bd_net [get_bd_pins $rst/interconnect_aresetn] $pin
}

# PS IRQ_F2P[0] = DMA MM2S; IRQ_F2P[1] = SNN done.
set irq_concat [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:xlconcat:2.1 irq_concat]
set_property CONFIG.NUM_PORTS {2} $irq_concat
connect_bd_net [get_bd_pins $dma/mm2s_introut] \
    [get_bd_pins $irq_concat/In0]
connect_bd_net [get_bd_pins $snn/irq] \
    [get_bd_pins $irq_concat/In1]
connect_bd_net [get_bd_pins $irq_concat/dout] \
    [get_bd_pins $ps7/IRQ_F2P]

assign_bd_address -offset 0x00000000 -range 0x20000000 \
    -target_address_space [get_bd_addr_spaces $dma/Data_MM2S] \
    [get_bd_addr_segs $ps7/S_AXI_HP0/HP0_DDR_LOWOCM] -force
assign_bd_address -offset 0x40400000 -range 0x00010000 \
    -target_address_space [get_bd_addr_spaces $ps7/Data] \
    [get_bd_addr_segs $dma/S_AXI_LITE/Reg] -force
set snn_seg [get_bd_addr_segs -quiet $snn/s_axi/reg0]
if {[llength $snn_seg] != 1} {
    error "The packaged SNN IP has no AXI-Lite segment 's_axi/reg0'."
}
assign_bd_address -offset 0x43C00000 -range 0x00010000 \
    -target_address_space [get_bd_addr_spaces $ps7/Data] \
    $snn_seg -force

validate_bd_design
save_bd_design
set bd_file [get_files -quiet */$system_bd_name.bd]
generate_target all $bd_file
set wrapper_files [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper_files
set_property top ${system_bd_name}_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

# A small SNN internal path benefits from post-route physical optimization.
# Enable it for normal GUI/launch_runs implementation as well as batch builds.
set impl_run [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true $impl_run
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE Explore $impl_run

puts "Project: $system_project_dir"
puts "Top: ${system_bd_name}_wrapper"
puts "AXI addresses: DMA 0x40400000, SNN 0x43C00000"
puts "BD contains the packaged SNN/SDSP IP. Run Synthesis, Implementation, and Generate Bitstream in Vivado."
