# PYNQ-Z1 SNN/SDSP source code

The supported Vivado flow in this directory creates a PYNQ-Z1 project with a
packaged SNN/SDSP AXI IP, a Zynq processing system, and an AXI DMA. The project
creation entry point is `./pynq_z1_ip_project/build_all.tcl`.
Run the commands below from this `SourceCode` directory; all paths are relative
to it.

## Files needed to create the Vivado project

```text
./
├── pynq_z1_ip_project/
│   ├── build_all.tcl
│   ├── package_snn_sdsp_ip.tcl
│   ├── create_pynq_z1_ip_project.tcl
│   └── README.md
└── rtl_ip/
    └── 38 VHDL source files, including snn_axi_wrapper.vhd
```

`./pynq_z1_ip_project/build_all.tcl` sources the other two Tcl files in order.
The packaging script reads all 38 `./rtl_ip/*.vhd` files through a path relative
to its own location. The project script then uses the packaged IP to create the
block design and its HDL wrapper. Keep `./pynq_z1_ip_project/` and `./rtl_ip/`
as sibling directories. Other directories under `./` are not inputs to this
Vivado project creation flow. No `.coe` file, user XDC file, Python package, or
MNIST dataset is needed to create this project.

## Prerequisites

- AMD Vivado with support for the `xc7z020clg400-1` part and the standard
  processing-system, reset, AXI DMA, AXI FIFO, SmartConnect, and concat IPs
  checked by `./pynq_z1_ip_project/create_pynq_z1_ip_project.tcl`.
- The Digilent PYNQ-Z1 board definition
  `www.digilentinc.com:pynq-z1:part0:1.0`, installed in Vivado or supplied
  through `PYNQ_Z1_BOARD_REPO`.
- A checkout and build path containing only ASCII characters. The Tcl scripts
  check this because Vivado may fail on non-ASCII source or output paths.

## Create the project

Open a terminal in this `SourceCode` directory and run:

```sh
vivado -mode gui -source ./pynq_z1_ip_project/build_all.tcl
```

Alternatively, start Vivado with its Tcl working directory set to this
`SourceCode` directory and enter:

```tcl
source ./pynq_z1_ip_project/build_all.tcl
```

The default output is `./pynq_z1_ip_project/build/`. The Vivado project is
created in `./pynq_z1_ip_project/build/pynq_z1_snn_sdsp_project/`, and the
packaged IP is created under `./pynq_z1_ip_project/build/ip_repo/`.
The build directory is ignored
by Git. To use `./build/` instead, set `PYNQ_Z1_IP_BUILD_DIR` to
`[file normalize ./build]` in the Vivado Tcl Console before sourcing the script.
If the board definition is not installed in Vivado, place its repository under
`./board_files/` and set `PYNQ_Z1_BOARD_REPO` to
`[file normalize ./board_files]` before sourcing. Both paths must contain only
ASCII characters.

`./pynq_z1_ip_project/build_all.tcl` creates and opens the project; it does not
run synthesis or generate a bitstream. Run Synthesis, Implementation, and
Generate Bitstream in Vivado after inspecting the block design. Detailed build,
timing, bitstream, and register instructions are in
`./pynq_z1_ip_project/README.md`.
