# PYNQ SNN/SDSP Notebooks

This folder contains the notebooks, encoded MNIST data, and hardware overlay
files used to run the SNN/SDSP accelerator on a PYNQ-Z1 board. The notebooks
control the FPGA through PYNQ, send input spikes through AXI DMA, and read
output spike counts through AXI-Lite registers.

## Prepare the Board

1. Boot the PYNQ-Z1 board with a working PYNQ image and connect it to your
   computer through the network.
2. Open the board's Jupyter interface in a browser and use its Python kernel.
   The notebooks require `pynq` and `numpy` in the board's Python environment.
3. Create the following directory on the board, using a Jupyter terminal or
   another terminal connected to the board:

   ```sh
   mkdir -p /home/xilinx/jupyter_notebooks/snn_sdsp
   ```

4. Upload the notebooks, overlay files, and the data required for your chosen
   experiment into that directory. The notebook code uses this path explicitly.
   If you use a different directory, update the path definitions in the
   notebooks.
5. Keep `snn_sdsp.bit` and `snn_sdsp.hwh` together with the same basename. They
   must come from the same hardware build. For generating a new overlay, see
   [the Vivado project instructions](../pynq_z1_ip_project/README.md).

For the complete three-epoch experiment, the three training ZIP files alone
occupy approximately 242 MB. Check the board's available storage before upload.
The notebooks load training data one shard at a time.

The board uses pre-encoded data, so Spiker and PyTorch are not needed to run
these notebooks. Data preparation with Spiker is performed on the host computer.

## Files in This Folder

### Notebooks

| File | Purpose |
| --- | --- |
| `smoke_test.ipynb` | Checks the overlay files, hardware metadata, registers, and DMA; then runs zero-input and dense-input tests with learning and teacher input disabled. |
| `mnist_test.ipynb` | Runs inference on ten fixed MNIST images, saves a baseline, compares teacher-disabled and teacher-enabled learning, and verifies that reloading the bitstream restores the initial behavior. |
| `mnist_train1000.ipynb` | Runs a 1,000-image training pilot. It contains both a ten-image diagnostic evaluation and a separate fixed 1,000-image evaluation workflow. |
| `mnist_train_full_epoch.ipynb` | Trains on all 60,000 MNIST training images for up to three consecutive epochs and evaluates the same fixed 1,000-image test set before training and after each epoch. |

### Hardware Files

| File | Purpose |
| --- | --- |
| `snn_sdsp.bit` | FPGA bitstream loaded by PYNQ. Downloading it initializes the accelerator and its weight memory. |
| `snn_sdsp.hwh` | Hardware metadata used by PYNQ to identify the IP blocks, interfaces, and address map. |

The notebooks expect DMA IP `axi_dma_mm2s` at `0x40400000` and SNN IP
`snn_sdsp_0` at `0x43C00000`.

### Input Data

| File | Purpose |
| --- | --- |
| `mnist_test10_spikes.npz` | Ten fixed test images, their encoded spikes, packed DMA words, labels, and encoding metadata. Used for initial inference and teacher experiments. |
| `mnist_train1000_words.npz` | A fixed, shuffled training subset containing 100 images per digit, for 1,000 training images in total. |
| `mnist_test1000_fixed_words.npz` | A fixed test subset containing 100 images per digit. It excludes the first ten test images and is reused for before-and-after evaluation. |
| `mnist_train_epoch01.zip` | The complete 60,000-image training set encoded and shuffled with seed 2028. |
| `mnist_train_epoch02.zip` | The complete training set independently encoded and shuffled with seed 2029. |
| `mnist_train_epoch03.zip` | The complete training set independently encoded and shuffled with seed 2030. |

Each epoch ZIP contains 60 compressed NPZ shards of 1,000 images and a
`manifest.json` with encoding settings, shard order, and hashes. Upload the ZIP
files intact; the full-epoch notebook reads their members directly.

To regenerate data on the host computer, use:

- `../prepare_mnist_test10.py` for the ten-image test input.
- `../prepare_mnist_train1000.py` for the 1,000-image training subset.
- `../spiker_hardware_parity/prepare_fixed_eval1000.py` for the fixed evaluation
  subset.
- `../mnist_full_epoch_data/prepare_full_epochs.py` for complete training epochs;
  see [its README](../mnist_full_epoch_data/README.md).

Check the data and output paths in these scripts before running them. Reuse the
same encoded test files when comparing experiments so the input spikes remain
identical.

### Saved Baseline Results

| File | Purpose |
| --- | --- |
| `mnist_test10_baseline.npz` | An earlier baseline archive containing sample indices, labels, input spike counts, output counts, and result registers. |
| `mnist_test10_inference_baseline.npz` | The baseline archive written by the current `mnist_test.ipynb`; also records encoding settings, inference mode, and the bitstream SHA256. |

Baseline archives store measurements, not learned weights. The current
`mnist_test.ipynb` refuses to overwrite an existing
`mnist_test10_inference_baseline.npz`. Before recording a new baseline, archive
the existing file under a different name or in a separate results directory.

## Recommended Workflow

### 1. Check the Hardware

Open `smoke_test.ipynb` on the board and run its cells in order.

Required files: `snn_sdsp.bit` and `snn_sdsp.hwh`.

Confirm that the zero-input test completes 100 accepted time steps with zero
output spikes, and that the dense-input test produces nonzero spike counts
without DMA or stream errors.

### 2. Run the Ten-Image and Teacher Experiments

Open `mnist_test.ipynb` and run its cells in order, after handling any existing
baseline output file as described above.

Required files: the overlay pair and `mnist_test10_spikes.npz`.

This notebook intentionally reloads the bitstream between control conditions
to restore the initial weights. It first records inference with learning and
teacher input disabled, then compares learning with teacher input disabled and
enabled. After training, inference again disables both learning and teacher
input to measure the effect of the learned weights.

### 3. Run a 1,000-Image Training Experiment

`mnist_train1000.ipynb` contains two routes. Choose one route for a fresh
experiment rather than running every cell consecutively.

Required files: the overlay pair, `mnist_train1000_words.npz`, and
`mnist_test10_spikes.npz`. The fixed evaluation route also requires
`mnist_test1000_fixed_words.npz`.

| Route | Steps to run | Purpose |
| --- | --- | --- |
| Ten-image pilot | Steps 1-9 | Establish a ten-image baseline, train the first image, continue to 20 images, complete 1,000 images, and evaluate the ten test images again. |
| Fixed 1,000-image evaluation | Steps 1-5, then Steps 10-13; skip Steps 6-9 | Establish the fixed test-set baseline, train the 1,000-image subset once, and evaluate the same fixed test set afterward. |

Use a fresh kernel and run Step 2 to program the initial weights for each
independent route. Running Steps 1-13 consecutively trains the subset once in
Steps 6-8 and again in Step 12; Step 11 would then measure an already-trained
model instead of the initial model.

Both routes use calcium leak every 10 steps, BIST disabled, and teacher current
128 in Q9 format, equivalent to 0.25. Keep the overlay loaded between training
and post-training evaluation.

### 4. Run Complete Training Epochs

Open `mnist_train_full_epoch.ipynb` in a fresh kernel and run its cells in order.

Required files:

- `snn_sdsp.bit` and `snn_sdsp.hwh`.
- `mnist_test1000_fixed_words.npz`.
- `mnist_train_epoch01.zip` and `mnist_train_epoch02.zip`.
- `mnist_train_epoch03.zip` for the third epoch.
- `mnist_train1000.ipynb` in the same directory: the full-epoch notebook extracts
  its `run_frame()` function without running the pilot's experiment cells.

Steps 1-10 perform two consecutive epochs. Steps 11-13 add the third epoch.
The notebook programs the FPGA once, evaluates the initial model, and then
alternates training and evaluation. Each epoch continues from the weights
learned in the preceding epoch.

Do not reload the bitstream between epochs or before post-training evaluation.
The notebook verifies shard hashes and loads one shard at a time. Training
cells track progress and reject some repeated executions; after a failed or
interrupted transfer, inspect the state before attempting to continue.

## Input Format and Evaluation

Each image contains 100 time steps. Each time step contains 784 binary input
spikes packed into 25 little-endian 32-bit words, with 16 zero padding bits.
One image therefore uses 2,500 words, or 10,000 bytes, in a DMA transfer.

The accelerator returns ten output spike counts and a winning-neuron result.
The fixed-test workflows report:

- **Strict accuracy:** an image with no output spikes is counted as incorrect.
- **Argmax accuracy:** the largest count selects the class; an all-zero vector
  selects class 0.
- **Active-image accuracy:** accuracy among images with at least one output
  spike.
- Silent-image counts and total output spikes.

Use inference with learning and teacher input disabled for accuracy evaluation.
The target neuron's response while teacher current is enabled is a training
diagnostic.

## Hardware State and Results

- Downloading the bitstream restores the initial weights. Running another
  notebook that programs the FPGA also discards the currently learned weights.
- The per-image soft reset used by `run_frame()` clears the running image's
  state while preserving learned weights.
- Restarting a Python kernel removes its variables and progress tracking; it
  does not itself restore FPGA weights. Initialization cells that download the
  overlay do restore them.
- Run cells in the documented order. Training cells change hardware state and
  must not be repeated casually.
- Save the notebooks after an experiment to retain their printed outputs.
  Most training and evaluation arrays remain in kernel memory; these notebooks
  do not export a learned-weight checkpoint for later restoration.
- Keep the matching input data and overlay files with each experiment record.
  A baseline's bitstream hash can be used to identify the hardware build.
