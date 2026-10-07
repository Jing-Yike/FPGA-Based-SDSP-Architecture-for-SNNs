import logging
from spikerplus import NetBuilder
from spikerplus.dataloaders import MnistDL

from spikerplus.sdsp import SDSP
from spikerplus.sdsp_trainer import SDSPTrainer

def main():

    # ── Set logging ──────────────────────────────────────────────────────────
    logging.basicConfig(
        level  = logging.INFO,
        format = "%(asctime)s [%(levelname)s] %(message)s"
    )

    # ── Configure the network ────────────────────────────────────────────────────────
    net_dict = {
        "n_cycles" : 100,
        "n_inputs" : 784,
        "layer_0"  : {
            "neuron_model"    : "lif",
            "n_neurons"       : 10,
            "beta"            : 0.9375,
            "threshold"       : 1.0,
            "reset_mechanism" : "subtract"
        }
    }

    snn = NetBuilder(net_dict).build()

    # ── Load data ────────────────────────────────────────────────────────
    mnist = MnistDL(
        data_dir  = "./data",  # On first run, it will automatically download to this directory
        num_steps = 100,
        gain      = 0.1
    )

    # SDSP is online learning，batch_size=1 ensures weights update per sample
    train_loader, val_loader = mnist.load(
        batch_size    = 1,
        train_shuffle = True,
        test_shuffle  = False,
    )

    # ── SDSP parameters ─────────────────────────────────────────────────────
    #
    # theta1 < theta2 < theta3 < 2^ca_bits
    #
    # Meaning：
    #   theta1 : Ca lower → stop-learning zone
    #   theta2 : Ca within [theta1, theta2) can trigger LTD（down interval）
    #   theta3 : Ca within [theta1, theta3) can trigger LTP（up  interval）
    #   theta_m: threshold of membrane potential，if Vmem >= theta_m then LTP，else LTD
    #
    sdsp = SDSP(
        n_pre       = 784,
        n_post      = 10,
        theta1      = 1,
        theta2      = 3,
        theta3      = 6,
        theta_m     = 0.5, 
        weight_bits = 3,
        ca_bits     = 3,
        device      = "cpu"
    )

    trainer = SDSPTrainer(
        net                 = snn,
        sdsp                = sdsp,
        leak_interval       = 10,   
        bist_interval       = None,
        teacher_current     = 0.25,
        fp_dec              = 9,
        debug_samples       = 5,

        # SDSP unsigned weight initialization
        initialize_weights  = True,
        weight_init_low     = 1, 
        weight_init_high    = 2, 
        weight_init_seed    = 0
    )

    # ── Train ───────────────────────────────────────────────────────────
    trainer.train(
        train_loader = train_loader,
        val_loader   = val_loader,
        n_epochs     = 2,
        store        = True,
        output_dir   = "./trained_sdsp"
    )

if __name__ == "__main__":
    main()