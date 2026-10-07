# Cycle-count diagnostic simulation

These files are **simulation-only**. Do not add this directory to the Vivado
synthesis fileset or package it into the accelerator IP.

- `tb_multi_cycle_count.vhd` checks the original multi-cycle controller with
  `n_cycles=2` and observes three `start_all` pulses.
- `tb_network_cycle_count.vhd` supplies two different spike vectors. Its
  third request sees the first vector again, modeling the current AXI
  wrapper's ping-pong buffer after both valid flags have been cleared.
- `tb_network_cycle_n1.vhd` runs the same test with `n_cycles=1`.
- `tb_snn_axi_wrapper_two_steps.vhd` sends 50 AXI-Stream words and checks the
  AXI-Lite status, accepted-step count and completed-step count.
- `tb_snn_axi_wrapper_100_steps.vhd` streams 2500 AXI words with online
  learning enabled and checks 100 accepted/completed network steps. Its
  `DENSE_INPUT=true` mode disables learning and checks nonzero output counts.
- `tb_layer_step_output.vhd` checks that completed-step spikes match the
  barrier's registered output for dense inputs.
- `tb_snn_axi_wrapper_dense_two_steps.vhd` checks ten nonzero AXI-Lite spike
  counts after two dense input frames.
- `run_layer_output.tcl` runs any of these benches when `SNN_SIM_RTL_DIR`,
  `SNN_SIM_TB`, `SNN_SIM_PROJECT_DIR`, and optionally `SNN_SIM_TOP` and
  `SNN_SIM_GENERIC` are set to ASCII-only paths and values.
- `tb_exc_weight_ram_bounds.vhd` checks addresses 0, 783, and 784, plus
  read-first behavior and valid weight writeback.
- `tb_comparator_theta_m.vhd` checks the Q9 theta_m=0.5 boundary at raw
  membrane values 255 and 256.
- `tb_snn_axi_ip_defaults.vhd` checks the packaged-IP generic reset defaults,
  PS AXI register overrides, and restoration after hardware reset.
- `tb_snn_axi_wrapper_100_steps.vhd` also accepts `TEACHER_TEST=true`
  (100 zero-input steps, label 2, Q9 teacher current 128) and
  `ZERO_INPUT=true` (same zero-input control with teacher disabled).
- `check_exc_weight_ram_synth.tcl` checks block-RAM inference separately.

Before the production RAM bounds check was added, xsim stopped at 8005 ns on
its first read of address 784 because the array is indexed only from 0 to 783.
With the updated production RAM, the integrated network completes and counts
are:

| Network `n_cycles` | `sample` | `input_accept` | `out_spikes_valid` |
| ---: | ---: | ---: | ---: |
| 2 | 3 | 3 | 3 |
| 1 | 2 | 2 | 2 |

The cycle-count and two-step tests disable learning. The 100-step AXI smoke
test enables learning, but does not assert how many weights actually change.

The two-step AXI wrapper test passes: 50 stream handshakes, two accepted and
completed network steps, STATUS=0x00000005 (done with no stream/TLAST error).
The default 100-step test also passes: 2500 stream handshakes, 100 accepted
and completed steps, STATUS=0x00000005. The RAM unit test passes. Vivado 2025.2
standalone synthesis infers one RAMB36E1 for the 784 x 30 excitatory RAM.

The output-readout regression first failed on the unmodified integrated layer:
at completed step 2 the barrier held `0x3FF` but `step_spikes` was `0x000`.
After selecting the barrier's registered output, steps 2-4 report `0x3FF`
on both signals. The dense two-step AXI test reports one spike for each of
the ten neurons. The 100-step dense-input mode reports 99 spikes per neuron,
100 accepted/completed steps, and STATUS=0x00000005.

After teacher integration, the 100-step zero-input teacher test reports
22 spikes for labelled neuron 2 and zero for the other nine; the disabled
control reports zero for all ten. The layer waits for the neuron/barrier
before issuing step-valid on empty input frames.
