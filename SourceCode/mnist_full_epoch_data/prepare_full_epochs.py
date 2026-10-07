"""Encode complete MNIST training epochs with the original Spiker loader.

Each epoch is independently shuffled and re-encoded. The output is one ZIP
archive per epoch, containing 60 compressed NPZ shards and a JSON manifest.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import sys
import zipfile
from pathlib import Path

import numpy as np
import torch


HERE = Path(__file__).resolve().parent
SPIKER_ROOT = HERE.parents[2] / "Spiker" / "spiker"
DEFAULT_DATA_DIR = Path("D:/SourceCode/mnist_data")
NUM_STEPS = 100
NUM_INPUTS = 784
WORDS_PER_STEP = 25
GAIN = 0.1
SHARD_SIZE = 1000
EPOCH_SEEDS = {1: 2028, 2: 2029, 3: 2030}


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_mnist(data_dir: Path):
    if not (data_dir / "MNIST" / "raw").is_dir():
        raise FileNotFoundError(f"Cached MNIST data not found: {data_dir}")
    if not (SPIKER_ROOT / "spikerplus" / "dataloaders" / "mnist_dl.py").is_file():
        raise FileNotFoundError(f"Spiker MNIST loader not found: {SPIKER_ROOT}")

    sys.path.insert(0, str(SPIKER_ROOT))
    from spikerplus.dataloaders import MnistDL
    import spikerplus

    source = Path(spikerplus.__file__).resolve().parent
    if source != (SPIKER_ROOT / "spikerplus").resolve():
        raise RuntimeError(f"Wrong Spiker source imported: {source}")

    mnist = MnistDL(
        data_dir=str(data_dir),
        num_steps=NUM_STEPS,
        gain=GAIN,
        download=False,
    )
    if len(mnist.train_set) != 60000:
        raise ValueError(f"Expected 60000 training images, found {len(mnist.train_set)}")
    print("Spiker source:", source)
    print("Training images:", len(mnist.train_set))
    return mnist.train_set


def pack_spikes(spikes: np.ndarray) -> np.ndarray:
    if spikes.shape != (NUM_STEPS, NUM_INPUTS) or np.any(spikes > 1):
        raise ValueError(f"Expected binary spikes with shape (100, 784), got {spikes.shape}")
    padded = np.pad(spikes, ((0, 0), (0, 16)))
    packed_bytes = np.packbits(padded, axis=1, bitorder="little")
    words = np.ascontiguousarray(packed_bytes).view("<u4")
    if words.shape != (NUM_STEPS, WORDS_PER_STEP):
        raise ValueError(f"Unexpected packed shape: {words.shape}")
    if np.any(words[:, -1] & np.uint32(0xFFFF0000)):
        raise ValueError("Nonzero padding bits in final input word")
    return words


def encode_shard(dataset, indices: np.ndarray, epoch: int, shard_number: int, start: int):
    count = len(indices)
    words_array = np.empty((count, NUM_STEPS, WORDS_PER_STEP), dtype="<u4")
    labels_array = np.empty(count, dtype=np.uint8)
    spike_counts = np.empty(count, dtype=np.uint32)

    for position, index in enumerate(indices):
        spike_tensor, label = dataset[int(index)]
        spikes = spike_tensor.detach().cpu().numpy().astype(np.uint8, copy=False)
        words_array[position] = pack_spikes(spikes)
        labels_array[position] = int(label)
        spike_counts[position] = int(spikes.sum())

    buffer = io.BytesIO()
    np.savez_compressed(
        buffer,
        words=words_array,
        labels=labels_array,
        indices=indices.astype(np.int32, copy=False),
        spike_counts=spike_counts,
        epoch=np.asarray(epoch),
        shard=np.asarray(shard_number),
        start=np.asarray(start),
        num_steps=np.asarray(NUM_STEPS),
        gain=np.asarray(GAIN),
        seed=np.asarray(EPOCH_SEEDS[epoch]),
        split=np.asarray("train"),
        bitorder=np.asarray("little"),
    )
    return buffer.getvalue(), labels_array, spike_counts


def create_epoch(dataset, epoch: int, output_dir: Path) -> None:
    seed = EPOCH_SEEDS[epoch]
    final_path = output_dir / f"mnist_train_epoch{epoch:02d}.zip"
    partial_path = output_dir / f"mnist_train_epoch{epoch:02d}.zip.partial"
    if final_path.exists() or partial_path.exists():
        raise FileExistsError(
            f"Output or partial archive already exists: {final_path} / {partial_path}"
        )

    torch.manual_seed(seed)
    rng = np.random.default_rng(seed)
    order = rng.permutation(len(dataset)).astype(np.int32)
    if len(np.unique(order)) != len(dataset):
        raise ValueError("Epoch order must contain every training image exactly once")

    class_counts = np.zeros(10, dtype=np.int64)
    total_spikes = 0
    shard_metadata = []
    with zipfile.ZipFile(partial_path, mode="w", compression=zipfile.ZIP_STORED, allowZip64=True) as archive:
        for start in range(0, len(order), SHARD_SIZE):
            shard_number = start // SHARD_SIZE
            indices = order[start:start + SHARD_SIZE]
            payload, labels, spike_counts = encode_shard(
                dataset, indices, epoch, shard_number, start
            )
            member_name = f"shard_{shard_number:03d}.npz"
            archive.writestr(member_name, payload, compress_type=zipfile.ZIP_STORED)

            class_counts += np.bincount(labels.astype(np.int32), minlength=10)
            total_spikes += int(spike_counts.sum())
            shard_metadata.append({
                "name": member_name,
                "sha256": sha256_bytes(payload),
                "first_position": start,
                "count": len(indices),
                "input_spikes": int(spike_counts.sum()),
            })
            print(
                f"Epoch {epoch}: encoded {start + len(indices)}/{len(order)} images",
                flush=True,
            )

        manifest = {
            "format_version": 1,
            "split": "train",
            "epoch": epoch,
            "seed": seed,
            "num_steps": NUM_STEPS,
            "gain": GAIN,
            "bitorder": "little",
            "image_count": len(order),
            "shard_size": SHARD_SIZE,
            "class_counts": class_counts.tolist(),
            "total_input_spikes": total_spikes,
            "shards": shard_metadata,
        }
        archive.writestr(
            "manifest.json",
            json.dumps(manifest, indent=2, sort_keys=True).encode("utf-8"),
            compress_type=zipfile.ZIP_STORED,
        )

    with zipfile.ZipFile(partial_path, mode="r") as archive:
        bad_member = archive.testzip()
        if bad_member is not None:
            raise ValueError(f"ZIP integrity check failed at {bad_member}")
        saved_manifest = json.loads(archive.read("manifest.json"))
        if saved_manifest != manifest or len(saved_manifest["shards"]) != 60:
            raise ValueError("Saved manifest does not match the generated dataset")
        with np.load(io.BytesIO(archive.read("shard_000.npz")), allow_pickle=False) as first:
            if first["words"].shape != (SHARD_SIZE, NUM_STEPS, WORDS_PER_STEP):
                raise ValueError("Unexpected first-shard shape")

    partial_path.rename(final_path)
    print("Completed epoch:", epoch)
    print("Archive:", final_path.resolve())
    print("File size:", final_path.stat().st_size, "bytes")
    print("Class counts:", class_counts.tolist())
    print("Total input spikes:", total_spikes)
    print("SHA256:", sha256_file(final_path))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--epoch", choices=("1", "2", "3", "all"), default="all")
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    parser.add_argument("--output-dir", type=Path, default=HERE)
    args = parser.parse_args()

    epochs = (1, 2) if args.epoch == "all" else (int(args.epoch),)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for epoch in epochs:
        final_path = args.output_dir / f"mnist_train_epoch{epoch:02d}.zip"
        partial_path = args.output_dir / f"mnist_train_epoch{epoch:02d}.zip.partial"
        if final_path.exists() or partial_path.exists():
            raise FileExistsError(f"Archive or partial file already exists: {final_path}")

    dataset = load_mnist(args.data_dir)
    for epoch in epochs:
        create_epoch(dataset, epoch, args.output_dir)


if __name__ == "__main__":
    main()
