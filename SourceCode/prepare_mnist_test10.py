from pathlib import Path
import importlib.util

import numpy as np
import torch


data_dir = Path(r"D:\SourceCode\mnist_data")
output_path = Path(r"D:\SourceCode\mnist_test10_spikes.npz")

num_steps = 100
gain = 0.1
seed = 2026
indices = np.arange(10, dtype=np.int64)

data_dir.mkdir(parents=True, exist_ok=True)

package_spec = importlib.util.find_spec("spikerplus")
if package_spec is None or not package_spec.submodule_search_locations:
    raise RuntimeError("spikerplus is not installed in this Python environment")

package_dir = Path(next(iter(package_spec.submodule_search_locations)))
loader_path = package_dir / "dataloaders" / "mnist_dl.py"

if not loader_path.is_file():
    raise FileNotFoundError(loader_path)

module_spec = importlib.util.spec_from_file_location(
    "spiker_mnist_dl", loader_path
)
if module_spec is None or module_spec.loader is None:
    raise RuntimeError("Cannot load Spiker MNIST dataloader")

module = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(module)
MnistDL = module.MnistDL

print("Spiker loader:", loader_path)

torch.manual_seed(seed)

mnist = MnistDL(
    data_dir=str(data_dir),
    num_steps=num_steps,
    gain=gain,
    download=True,
)

all_spikes = []
all_words = []
all_labels = []
all_images = []

for index in indices:
    spike_tensor, label = mnist.test_set[int(index)]

    spikes = spike_tensor.detach().cpu().numpy().astype(np.uint8)
    assert spikes.shape == (num_steps, 784)
    assert np.all((spikes == 0) | (spikes == 1))

    padded = np.pad(spikes, ((0, 0), (0, 16)))
    packed_bytes = np.packbits(padded, axis=1, bitorder="little")
    words = np.ascontiguousarray(packed_bytes).view("<u4")
    assert words.shape == (num_steps, 25)
    assert np.all((words[:, 24] & 0xFFFF0000) == 0)

    recovered = np.unpackbits(
        np.ascontiguousarray(words).view(np.uint8).reshape(num_steps, 100),
        axis=1,
        bitorder="little",
    )[:, :784]
    assert np.array_equal(recovered, spikes)

    all_spikes.append(spikes)
    all_words.append(words)
    all_labels.append(int(label))
    all_images.append(mnist.test_set.data[int(index)].cpu().numpy())

spikes_array = np.stack(all_spikes)
words_array = np.stack(all_words)
labels_array = np.asarray(all_labels, dtype=np.uint8)
images_array = np.stack(all_images).astype(np.uint8)

assert spikes_array.shape == (10, 100, 784)
assert words_array.shape == (10, 100, 25)
assert labels_array.shape == (10,)
assert images_array.shape == (10, 28, 28)

np.savez(
    output_path,
    spikes=spikes_array,
    words=words_array,
    labels=labels_array,
    images=images_array,
    indices=indices,
    num_steps=np.asarray(num_steps),
    gain=np.asarray(gain),
    seed=np.asarray(seed),
)

with np.load(output_path, allow_pickle=False) as saved:
    assert saved["spikes"].shape == (10, 100, 784)
    assert saved["words"].shape == (10, 100, 25)
    assert saved["labels"].shape == (10,)

print("Saved file:", output_path)
print("File size:", output_path.stat().st_size, "bytes")
print("Labels:", labels_array.tolist())
print("Spike counts:", spikes_array.sum(axis=(1, 2)).tolist())
print("Words per image:", words_array.shape[1] * words_array.shape[2])