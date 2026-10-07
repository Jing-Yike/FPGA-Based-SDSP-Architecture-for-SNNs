# FPGA-based Real-Time Learning Architecture with Partial Reconfiguration for Spiking Neural Networks

## ℹ️ Repository Information

---

**Student:** Yike Jing\
**Module:** Master-Thesis_NES\
**Links:** [Thesis](/../../../-/jobs/artifacts/main/file/Thesis.pdf?job=build_docs) · [Task Description](/../../../-/jobs/artifacts/main/file/TaskDescription.pdf?job=build_docs) · [GitLab Issue](https://git-ads.inf.tu-dresden.de/ads-staff/ads-students/-/work_items/270)[^*]

This repository contains the source code, experiment instructions, thesis,
presentations, and meeting minutes for the master's thesis. The research focuses
on FPGA-based spiking neural networks (SNNs), online spike-driven synaptic
plasticity (SDSP), and partial reconfiguration (PR).

The supplied hardware build integrates a 784-input, 10-output SNN with SDSP
learning into a PYNQ-Z1 AXI accelerator. Python scripts support algorithm
experiments and VHDL generation, while PYNQ notebooks support board tests,
training, and evaluation. The PR objective is included in the research checklist
below; the supplied Vivado scripts create the integrated accelerator project.

## 📂 Repository Structure

---

```text
.
├─ MeetingMinutes/      # Dated meeting minutes and the meeting template.
├─ Presentations/       # Introduction, intermediate, final, and defense slides.
├─ SourceCode/          # Python models, RTL, simulations, build scripts, and notebooks.
├─ TaskDescription/     # Task description maintained by the supervisor(s).
├─ Thesis/              # LaTeX thesis sources, references, figures, and tables.
├─ Thesis_PDF/          # Local exported thesis PDF; see the repository rules below.
├─ .gitignore           # Excludes generated and temporary files.
├─ .gitlab-ci.yml       # Builds the thesis and task-description PDF artifacts.
└─ README.md            # Repository overview and workflow entry points.
```

> Note: Do not add large files, such as datasets or complete Vivado/Vitis design projects, to the repository. Instead, create scripts and instructions in the form of a ReadMe file to reproduce your results. Send large datasets to your supervisor(s) separately, so they can archive them as well.

### Source Code

```text
SourceCode/
├─ py_model/                  # SDSP Python model, trainer, and VHDL-generation script.
├─ Spiker_output/             # Original Spiker-generated SNN VHDL and ROM initialization.
├─ rtl/
│  ├─ sdsp/                   # Standalone SDSP learning modules.
│  └─ tb/                     # Earlier standalone module testbenches.
├─ rtl_ip/                    # Integrated SNN/SDSP AXI IP: 38 VHDL source files.
├─ sim/                       # Integrated RTL regression and diagnostic simulations.
├─ pynq_z1_ip_project/        # Reproducible IP-packaging and Vivado project scripts.
├─ Jupyter_notebook/          # PYNQ board tests, training, and evaluation notebooks.
├─ mnist_full_epoch_data/     # Complete MNIST epoch preparation and local generated data.
├─ prepare_mnist_test10.py    # Prepare ten fixed MNIST test inputs on the host.
├─ prepare_mnist_train1000.py # Prepare a balanced 1,000-image training subset.
├─ py_model_results.xlsx     # Software experiment parameters and result summaries.
└─ README.md                 # Supported hardware build entry point.
```

`rtl_ip/` is the source directory used by the current Vivado packaging flow.
Keep it beside `pynq_z1_ip_project/`. `Spiker_output/` is the original generated
SNN baseline, and `rtl/sdsp/` contains the standalone learning implementation.
These directories include overlapping module names and should not be combined
into one synthesis fileset. The earlier `rtl/tb/` benches may require interface
updates; use the documented `sim/` workflow for the integrated implementation.

Generated datasets, bitstreams, hardware metadata, and build outputs may be
present in a local working copy for experiments. Their local presence does not
change the repository's large-file policy.

## 🚀 Running the Code and Experiments

---

### Python Model and VHDL Generation

Clone the Spiker repository and install its Python dependencies according to
its own instructions. Copy these files from `SourceCode/py_model/` into the
Spiker checkout:

| File | Destination |
| --- | --- |
| `model_run.py` | `Spiker/spiker/model_run.py` |
| `sdsp.py` | `Spiker/spiker/spikerplus/sdsp.py` |
| `sdsp_trainer.py` | `Spiker/spiker/spikerplus/sdsp_trainer.py` |

Run the model from `Spiker/spiker/`:

```sh
python model_run.py
```

For network VHDL generation, also copy `vhdl_gen.py` into `Spiker/spiker/` and
run it from that directory:

```sh
python vhdl_gen.py
```

See [the Python model README](SourceCode/py_model/README.md) for the file layout
and configuration details.

### Vivado Project and FPGA Overlay

Use Vivado with support for `xc7z020clg400-1` and the Digilent PYNQ-Z1 board
definition. The build scripts require ASCII-only source and output paths.
Prepare a working copy at a suitable path, open a terminal in its `SourceCode/`
directory, and run:

```sh
vivado -mode gui -source ./pynq_z1_ip_project/build_all.tcl
```

This packages the SNN/SDSP IP and creates the Zynq PS, DDR, AXI DMA, and
accelerator block design. It leaves the project open; synthesis, implementation,
and bitstream generation are separate steps. The default generated files are
under `SourceCode/pynq_z1_ip_project/build/`.

For board deployment, use the matching `.bit` and `.hwh` files from the same
build, with the same basename, such as `snn_sdsp.bit` and `snn_sdsp.hwh`.
See [the source-code README](SourceCode/README.md) and
[the Vivado project README](SourceCode/pynq_z1_ip_project/README.md) for full
build and deployment instructions.

### RTL Verification

The `SourceCode/sim/` directory contains checks for network step counts, AXI
transfers, output readout, teacher input, RAM behavior, and IP defaults.
`run_layer_output.tcl` runs a selected testbench;
`check_exc_weight_ram_synth.tcl` checks block-RAM inference separately.

See [the simulation README](SourceCode/sim/README.md) for test selection,
environment variables, and recorded results. Testbenches are simulation sources
and must not be included in the packaged synthesis IP.

### PYNQ Board Experiments

Upload the selected notebooks, matching overlay files, and required encoded
data to `/home/xilinx/jupyter_notebooks/snn_sdsp` on the PYNQ-Z1 board. Open the
notebooks through the board's Jupyter interface.

| Notebook | Experiment |
| --- | --- |
| `smoke_test.ipynb` | Hardware, register, DMA, zero-input, and dense-input checks. |
| `mnist_test.ipynb` | Ten-image inference baseline and teacher-learning controls. |
| `mnist_train1000.ipynb` | Training-subset pilot and fixed-test evaluation. |
| `mnist_train_full_epoch.ipynb` | Consecutive complete training epochs with fixed-test evaluation. |

Follow [the PYNQ notebook README](SourceCode/Jupyter_notebook/README.md) for
required files and execution order. In particular, the 1,000-image notebook
contains two experiment routes; choose the documented route to avoid training
the subset twice. Keep the FPGA programmed between consecutive training epochs
and post-training evaluation, since reloading the bitstream restores initial
weights.

Prepare input data on the host computer using the supplied scripts. The board
consumes pre-encoded data and does not need Spiker or PyTorch for these
notebooks. See [the full-epoch data README](SourceCode/mnist_full_epoch_data/README.md)
for reproducible training-archive generation.

## 📝 Thesis and Project Documents

---

- **Meeting minutes:** use `MeetingMinutes/20YY_MM_DD.md` as the template for
  dated records of discussions and tasks for the next meeting.
- **Presentations:** store project slides in `Presentations/`; defense slides
  are under `Presentations/Defense/`.
- **Task description:** the supervisor(s) maintain
  `TaskDescription/TaskDescription.tex`. Follow
  [the task-description README](TaskDescription/README.md) for template parameters.
- **Thesis:** `Thesis/thesis.tex` is the compilation entry point. Chapters,
  references, figures, tables, and other thesis content are maintained under
  `Thesis/`. Follow [the thesis README](Thesis/README.md) for dependencies and
  local compilation setup.

The thesis requires `Thesis/TaskDescriptionSigned.pdf`. Keep the signed task
description as the required source document. Generated thesis PDFs, including
local exports in `Thesis_PDF/`, should not be pushed to the repository.

The GitLab `build_docs` job is configured to run for changes under `Thesis/` or
`TaskDescription/`. It publishes `Thesis.pdf` and `TaskDescription.pdf` as job
artifacts. If the signed task description exists, CI uses it to produce the
task-description artifact; otherwise it compiles the task-description source.
Use the artifact links at the top of this README to access the generated PDFs.
The current CI configuration builds documents; it does not run the Python or
RTL tests.

## 📦 Repository and Reproducibility Rules

---

- Keep source code, build scripts, experiment instructions, and the required
  project documents in the repository.
- Generate MNIST datasets and complete Vivado/Vitis projects locally. Provide
  scripts and README instructions to reproduce them instead of committing large
  generated files.
- Send large datasets to the supervisor(s) separately for archiving, as required
  by the repository template.
- Follow `.gitignore` and the thesis instructions for generated files. Git
  ignore rules do not automatically remove files that are already tracked.
- Record experiment parameters, input-data hashes, and the matching hardware
  build when saving results. Evaluate with learning and teacher input disabled,
  and distinguish strict accuracy from argmax accuracy for silent samples.

## ✅ TODOs

---

>

- [ ] Conduct a literature review on:
    - [ ] Digital implementations (FPGA or ASIC) of SDSP training algorithm.
    - [ ] FPGA-based SNN implementations with PR-based real-time training algorithm.
- [ ] Design and optimize an architectural model for the SDSP algorithm.
- [ ] Implement the model into RTL Code, simulate and validate it.
- [ ] Integrate the training module into a simplified SNN design (taking advantage of an open-source SNN framework).
- [ ] Make the training dynamically reconfigurable (Apply PR to the complete training block).
- [ ] Test it on FPGA and get (both with and without PR) the following metrics:
    - [ ] Resource utilization, power consumption, latency, maximum frequency, accuracy, and for PR, reconfiguration time.
	- [ ] (Optional): Convergence speed for learning. 
- [ ] Comparison with other digital SNN architectures:
    - [ ] With real-time SDSP training possibility.
    - [ ] with PR-based real-time training possibility.
- [ ] (Optional) Extend the simplified SNN to support more neuron models and/or architecture settings.

- [ ] Documentation and draft the first version of Thesis
- [ ] Apply final comments to the thesis
- [ ] Push everything and notify that everything is ready for archive


[^*]: Access is restricted to supervisors only
