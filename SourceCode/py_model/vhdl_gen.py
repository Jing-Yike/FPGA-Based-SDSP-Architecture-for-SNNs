import logging
from spikerplus import NetBuilder, VhdlGenerator
from spikerplus.vhdl import write_vhdl

# Set the logging level to allow spiker to log information
logging.basicConfig(level = logging.INFO)

# Configure the network
net_dict = {
    "n_cycles"                  : 100,
    "n_inputs"                  : 784,
    "layer_0"   :{

        "neuron_model"          : "lif",
        "n_neurons"             : 10,
        "beta"                  : 0.9375,
        "threshold"             : 1.0,
        "reset_mechanism"       : "subtract"
    }
}

bitwidth_config = {
    "weights_bw"        : 3,
    "neurons_bw"        : 16,    # membrane potential of the neuron
    "fp_dec"            : 9     # number of decimal bites to use in the representation
}

# Instantiate network builder providing net configuration
net_builder = NetBuilder(net_dict)

snn = net_builder.build()

# Instantiate the VHDL generator
vhdl_generator = VhdlGenerator(snn, bitwidth_config)

# Automatically generate VHDL code
vhdl_snn = vhdl_generator.generate(functional = False, interface = True)

write_vhdl(vhdl_snn)