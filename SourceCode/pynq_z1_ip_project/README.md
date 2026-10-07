# PYNQ-Z1 SNN/SDSP IP project

Run the commands below from this `pynq_z1_ip_project` directory; all paths are
relative to it. `../rtl_ip/` is the source directory for this flow. It contains all
38 VHDL files used to package `snn_axi_wrapper`. The RAM and ROM initial values
are VHDL constants in `../rtl_ip/full_system_pkg.vhd`; no `.coe` file
is needed.

## Build in Vivado

Keep this directory and `../rtl_ip/` together under `SourceCode`. Clone or copy
them to a path containing only ASCII characters.
Install the Digilent PYNQ-Z1 board definition
(`www.digilentinc.com:pynq-z1:part0:1.0`). From this directory, run:

```sh
vivado -mode gui -source ./build_all.tcl
```

Or, with the Vivado Tcl working directory set to this directory:

```tcl
source ./build_all.tcl
```

`PYNQ_Z1_IP_BUILD_DIR` is optional; by default output goes into `./build/`.
For output under `../build/` instead, set `::env(PYNQ_Z1_IP_BUILD_DIR)` to
`[file normalize ../build]` before sourcing. If the board definition is stored
under `../board_files/`, set `::env(PYNQ_Z1_BOARD_REPO)` to
`[file normalize ../board_files]` before sourcing. These directories must use
ASCII-only paths.
Use a fresh output directory when rebuilding; the scripts use Vivado's
`-force` option and regenerate the build outputs.

The three Tcl files have separate roles:

1. `./package_snn_sdsp_ip.tcl` packages
   `../rtl_ip/snn_axi_wrapper.vhd` and its dependencies as
   `thesis.local:user:snn_sdsp_accelerator:1.0`.
2. `./create_pynq_z1_ip_project.tcl` creates
   the PS/DDR/DMA/SNN BD and makes its generated HDL wrapper the project top.
   It requires the packaged IP.
3. `./build_all.tcl` sources both scripts in
   sequence and leaves the completed project open in Vivado.

The default generated project is `./build/pynq_z1_snn_sdsp_project/`. Its top is
`pynq_z1_snn_sdsp_wrapper` and exposes only
the PS `DDR` and `FIXED_IO` interfaces. The BD contains the SNN IP, so PYNQ's
HWH metadata can identify its AXI-Lite address and interrupt. No user PL pin
XDC is needed for this top; the PS board preset and generated IP constraints
configure DDR, MIO and FCLK0.

The address map is DMA control at `0x40400000` and SNN control at
`0x43C00000`, each with a 64 KiB aperture. Both SNN and DMA are clocked at
100 MHz. `IRQ_F2P[0]` is DMA MM2S and `IRQ_F2P[1]` is SNN completion.

After inspecting the BD, run Synthesis, Implementation and Generate Bitstream.
The generated implementation run enables post-route physical optimization
(`Explore`) to improve a short internal SNN path. Check that setup and hold
WNS are nonnegative on your own build; routing can vary. Alternatively, in
the Tcl Console:

```tcl
launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
open_run impl_1
report_timing_summary
```

For PYNQ, copy the generated `.bit` from
`./build/pynq_z1_snn_sdsp_project/pynq_z1_snn_sdsp.runs/impl_1/`
and the `.hwh` from
`./build/pynq_z1_snn_sdsp_project/pynq_z1_snn_sdsp.gen/sources_1/bd/pynq_z1_snn_sdsp/hw_handoff/`
to the board. Rename
both to the same basename, such as `snn_sdsp.bit` and `snn_sdsp.hwh`. Then
load `Overlay("snn_sdsp.bit")` and inspect `ol.ip_dict` for `axi_dma_mm2s`
and `snn_sdsp_0`.

One image is `N_CYCLES=100` time steps. Each step is 25 little-endian 32-bit
words (100 bytes): 784 spike bits followed by 16 padding bits. A full image
is 10,000 bytes and DMA asserts TLAST on its final word. The current RTL
supports inference and SDSP learning with optional teacher current. Program
LABEL at offset `0x0C` (0..9) and TEACHER_CURRENT at `0x18` before starting an
image. TEACHER_CURRENT is a nonnegative Q9 raw integer; `0x80` means 0.25 and
is the default unless changed in the IP customization window. CTRL bit 6
enables teacher injection, while bit 2
must also enable learning. For example, write `0x55` to CTRL at offset `0x00`
to start with learning, interrupt, and teacher enabled; `0x15` leaves teacher
disabled. The label, current, and teacher enable are captured at start for
the entire image. Values above 32767 are saturated to 32767 when captured.
Labels 10..15 select no neuron. The current is added once at each generated
network-step start, before that step's Spiker fire/leak operation; this follows
the Python model's target-only teacher rule but is not a bit-exact replacement
for its floating-point neuron update.
The bitstream must be regenerated after repackaging the changed RTL IP.

## IP defaults and PS overrides

The IP customization window exposes these `snn_axi_wrapper` generics:

| Generic | AXI register reset value | Valid values |
| --- | --- | --- |
| `CA_INTERVAL_DEFAULT` | CA_INTERVAL, offset `0x10` | 0..65535 time steps; 0 disables calcium leak |
| `BIST_INTERVAL_DEFAULT` | BIST_INTERVAL, offset `0x14` | 0..65535 time steps; 0 disables BIST |
| `TEACHER_CURRENT_DEFAULT` | TEACHER_CURRENT, offset `0x18` | 0..32767 in Q9; 128 is 0.25 |
| `LABEL_DEFAULT` | LABEL, offset `0x0C` | 0..9 |
| `LEARN_ENABLE_DEFAULT` | CTRL bit 2 | 0 or 1 |
| `BIST_ENABLE_DEFAULT` | CTRL bit 3 | 0 or 1 |
| `TEACHER_ENABLE_DEFAULT` | CTRL bit 6 | 0 or 1 |

These are build-time **defaults**, not live hardware knobs. Changing an IP
generic requires regenerating the IP and bitstream. At hardware reset
(`aresetn=0`) the defaults load into the AXI registers. A PS AXI write then
overrides the corresponding register without regenerating the bitstream.
The wrapper's soft reset clears the running image but does not reload these
configuration defaults.

The CTRL register write updates all enable bits together. If software only
wants to start a run while preserving the IP-configured enable defaults, it
must first read CTRL at `0x00`, then write the read value OR 1 back to CTRL.
Writing only `0x01` starts a run but also clears the learning, BIST, and
teacher enable bits. A nonzero BIST interval still requires BIST enable;
teacher injection requires both teacher enable and learning enable.
