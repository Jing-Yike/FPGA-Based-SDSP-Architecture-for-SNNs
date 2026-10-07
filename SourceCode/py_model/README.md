# Python Model and VHDL Generation

This directory contains the SDSP Python model, its training script, and a script
that describes the network to be generated as VHDL. Both workflows use Spiker.

## Set Up Spiker

Clone the Spiker repository and follow its installation instructions to install
the required Python dependencies. The instructions below assume the cloned
repository is named `Spiker` and contains the `Spiker/spiker` directory.

## Run the Python Model

Copy the following files from this directory into the Spiker checkout:

| File | Destination |
| --- | --- |
| `model_run.py` | `Spiker/spiker/model_run.py` |
| `sdsp.py` | `Spiker/spiker/spikerplus/sdsp.py` |
| `sdsp_trainer.py` | `Spiker/spiker/spikerplus/sdsp_trainer.py` |

The resulting directory structure should be:

```text
Spiker/
└── spiker/
    ├── model_run.py
    └── spikerplus/
        ├── sdsp.py
        └── sdsp_trainer.py
```

Open a terminal in `Spiker/spiker`, where `model_run.py` is located, and run:

```sh
python model_run.py
```

The script configures the network, loads the MNIST data, and runs SDSP training
and evaluation. Edit the parameters in `model_run.py` to configure an experiment.

## Generate the Network VHDL

`vhdl_gen.py` describes the network configuration and numeric representation
used by Spiker's VHDL generator.

When you need to generate the network's VHDL files, copy `vhdl_gen.py` into
`Spiker/spiker`:

```text
Spiker/
└── spiker/
    ├── vhdl_gen.py
    └── spikerplus/
```

Open a terminal in `Spiker/spiker`, where `vhdl_gen.py` is located, and run:

```sh
python vhdl_gen.py
```

Spiker will generate and write the VHDL files for the network described in the
script. Edit `net_dict` and `bitwidth_config` in `vhdl_gen.py` to change the
network configuration and numeric representation before generating the files.
