from pathlib import Path
import hashlib
import importlib.util

import numpy as np
import torch


data_dir = Path(r"D:\SourceCode\mnist_data")
output_path = Path(r"D:\SourceCode\mnist_train1000_words.npz")

num_steps = 100
gain = 0.1
seed = 2026
samples_per_class = 100

if output_path.exists():
    raise FileExistsError(f"Output file already exists: {output_path}")

package_spec = importlib.util.find_spec("spikerplus")
if package_spec is None or not package_spec.submodule_search_locations:
    raise RuntimeError("spikerplus is not installed")

package_dir = Path(next(iter(package_spec.submodule_search_locations)))
loader_path = package_dir / "dataloaders" / "mnist_dl.py"

module_spec = importlib.util.spec_from_file_location(
    "spiker_mnist_dl", loader_path
)
if module_spec is None or module_spec.loader is None:
    raise RuntimeError(f"Cannot load {loader_path}")

module = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(module)
MnistDL = module.MnistDL

torch.manual_seed(seed)

mnist = MnistDL(
    data_dir=str(data_dir),
    num_steps=num_steps,
    gain=gain,
    download=True,
)

targets = mnist.train_set.targets.detach().cpu().numpy()
rng = np.random.default_rng(seed)

indices = np.concatenate([
    rng.choice(
        np.flatnonzero(targets == digit),
        size=samples_per_class,
        replace=False,
    )
    for digit in range(10)
]).astype(np.int64)

rng.shuffle(indices)

sample_count = len(indices)
words_array = np.empty((sample_count, num_steps, 25), dtype="<u4")
labels_array = np.empty(sample_count, dtype=np.uint8)
spike_counts = np.empty(sample_count, dtype=np.uint32)

for position, index in enumerate(indices):
    spike_tensor, label = mnist.train_set[int(index)]
    spikes = spike_tensor.detach().cpu().numpy().astype(
        np.uint8, copy=False
    )

    assert spikes.shape == (num_steps, 784)
    assert np.all((spikes == 0) | (spikes == 1))

    padded = np.pad(spikes, ((0, 0), (0, 16)))
    packed_bytes = np.packbits(
        padded, axis=1, bitorder="little"
    )
    words = np.ascontiguousarray(packed_bytes).view("<u4")

    assert words.shape == (num_steps, 25)
    assert np.all((words[:, 24] & 0xFFFF0000) == 0)

    recovered = np.unpackbits(
        np.ascontiguousarray(words).view(np.uint8).reshape(
            num_steps, 100
        ),
        axis=1,
        bitorder="little",
    )[:, :784]
    assert np.array_equal(recovered, spikes)

    words_array[position] = words
    labels_array[position] = int(label)
    spike_counts[position] = int(spikes.sum())

    if (position + 1) % 100 == 0:
        print(f"Encoded {position + 1}/{sample_count}", flush=True)

assert np.array_equal(
    np.bincount(labels_array.astype(np.int64), minlength=10),
    np.full(10, samples_per_class),
)

np.savez_compressed(
    output_path,
    words=words_array,
    labels=labels_array,
    indices=indices,
    spike_counts=spike_counts,
    num_steps=np.asarray(num_steps),
    gain=np.asarray(gain),
    seed=np.asarray(seed),
    split=np.asarray("train"),
    bitorder=np.asarray("little"),
)

with np.load(output_path, allow_pickle=False) as saved:
    assert saved["words"].shape == (1000, 100, 25)
    assert saved["labels"].shape == (1000,)
    assert saved["split"].item() == "train"

file_hash = hashlib.sha256(output_path.read_bytes()).hexdigest()

print("Spiker loader:", loader_path)
print("Saved file:", output_path)
print("File size:", output_path.stat().st_size, "bytes")
print("Words shape:", words_array.shape)
print("Class counts:", np.bincount(labels_array, minlength=10).tolist())
print("Total input spikes:", int(spike_counts.sum()))
print("SHA256:", file_hash)
print("Training data preparation passed")