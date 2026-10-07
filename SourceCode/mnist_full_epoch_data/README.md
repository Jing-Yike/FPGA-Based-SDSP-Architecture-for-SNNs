# Full MNIST training epoch data

Run the commands below from this `mnist_full_epoch_data` directory; all paths
are relative to it.

`prepare_full_epochs.py` reads the original Spiker `MnistDL` training set and
uses its `SpikeTransform` (100 time steps, gain 0.1). Each of the 60,000
training images is encoded once per epoch. Epochs 1, 2, and 3 use independent
seeds (2028, 2029, and 2030), separate random orders, and new Bernoulli spikes.

Place the cached MNIST dataset under `../mnist_data/` and keep the original
Spiker checkout beside this repository. Run from this directory:

```sh
python ./prepare_full_epochs.py --epoch 1 --data-dir ../mnist_data
python ./prepare_full_epochs.py --epoch 2 --data-dir ../mnist_data
python ./prepare_full_epochs.py --epoch 3 --data-dir ../mnist_data
```

Each run creates one archive in `./` named
`mnist_train_epochXX.zip`, containing 60 NPZ shards
of 1,000 images and `manifest.json`. The outer ZIP stores the already-compressed
NPZ shards without compressing them a second time. On PYNQ, open the outer ZIP
and load one member at a time with `np.load(io.BytesIO(archive.read(name)))`.
Never load all 60,000 frames into PYNQ memory at once. The `all` option retains
its original meaning of generating epochs 1 and 2; request epoch 3 explicitly.

The script refuses to overwrite an existing archive or partial archive. A
`.partial` file indicates an interrupted or failed run and is not a valid
training archive. Only upload a completed `.zip` after checking its printed
SHA256. Successive epochs must run on the same programmed FPGA; reprogramming
between them would reset learned weights.
