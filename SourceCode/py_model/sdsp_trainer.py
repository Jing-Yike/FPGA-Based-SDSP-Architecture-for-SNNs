import os
import time
import logging
import torch
import torch.nn.functional as F

from .sdsp import SDSP


class SDSPTrainer:
    """Online SDSP trainer for a single fully-connected SNN output layer.

    NetBuilder still creates the FC and IF/LIF modules. By default, this
    trainer overwrites only the FC layer's signed PyTorch initialization with
    an SDSP-compatible unsigned integer initialization. Calcium is reset for
    every independent input sample.
    """

    def __init__(
        self,
        net,
        sdsp: SDSP,
        leak_interval: int = 10,
        bist_interval=50,
        teacher_current: float = 0.0,
        fp_dec: int = 9,
        debug_samples: int = 5,
        initialize_weights: bool = True,
        weight_init_low: int = 14,
        weight_init_high: int = 22,
        weight_init_seed=None,
    ):
        self.net = net
        self.sdsp = sdsp
        self.leak_interval = leak_interval
        self.bist_interval = bist_interval
        self.teacher_current = float(teacher_current)
        self.fp_dec = fp_dec
        self.debug_samples = debug_samples
        self.debug_count = 0

        # SDSP-specific unsigned initialization configuration.
        # These values are integer weight-register codes, not float weights.
        self.initialize_weights = bool(initialize_weights)
        self.weight_init_low = int(weight_init_low)
        self.weight_init_high = int(weight_init_high)
        self.weight_init_seed = weight_init_seed
        self._sdsp_weights_initialized = False

        self.device = torch.device("cpu")
        self.net.to(self.device)

        self._neuron_layer = self._find_output_neuron_layer()
        self._fc_layer_name, self._fc_layer, self._neuron_module = (
            self._resolve_single_sdsp_layer()
        )

        logging.info(
            "SDSPTrainer ready | neuron layer: %s | leak_interval: %s | "
            "bist_interval: %s | teacher_current: %s | fp_dec: %s",
            self._neuron_layer,
            self.leak_interval,
            self.bist_interval,
            self.teacher_current,
            self.fp_dec,
        )

        if self.initialize_weights:
            self.initialize_sdsp_weights(
                low=self.weight_init_low,
                high=self.weight_init_high,
                seed=self.weight_init_seed,
            )
        else:
            logging.info(
                "SDSP unsigned weight initialization disabled; "
                "keeping the weights already stored in the NetBuilder model."
            )

    # ------------------------------------------------------------------
    # Network / weight helpers
    # ------------------------------------------------------------------

    def _find_output_neuron_layer(self):
        for name in reversed(list(self.net.layers.keys())):
            if "fc" not in name:
                return name
        raise RuntimeError("No neuron layer found in network.")

    def _resolve_single_sdsp_layer(self):
        """Resolve the single FC -> IF/LIF pair trained by this SDSPTrainer.

        The current SDSP implementation owns one weight matrix [n_post, n_pre]
        and one Ca counter per output neuron, so the online trainer deliberately
        requires exactly one feed-forward layer and one IF/LIF neuron layer.
        Failing loudly here is safer than silently updating the wrong FC layer.
        """
        fc_names = [name for name in self.net.layers if "fc" in name]
        neuron_names = [name for name in self.net.layers if "fc" not in name]

        if len(fc_names) != 1 or len(neuron_names) != 1:
            raise RuntimeError(
                "SDSPTrainer currently supports exactly one FC -> IF/LIF "
                "layer pair (e.g. 784 -> 10). Got layers: "
                f"{list(self.net.layers.keys())}"
            )

        fc_name = fc_names[0]
        neuron_name = neuron_names[0]

        if neuron_name != self._neuron_layer:
            raise RuntimeError(
                "Resolved neuron layer does not match the output neuron layer."
            )

        if not (neuron_name.startswith("if") or neuron_name.startswith("lif")):
            raise RuntimeError(
                "Online SDSP path currently supports IF/LIF output neurons; "
                f"got {neuron_name!r}."
            )

        fc_layer = self.net.layers[fc_name]
        neuron_module = self.net.layers[neuron_name]

        if fc_layer.out_features != int(self.sdsp.Ca.numel()):
            raise RuntimeError(
                "FC output size and SDSP post-neuron count do not match: "
                f"{fc_layer.out_features} vs {int(self.sdsp.Ca.numel())}."
            )

        return fc_name, fc_layer, neuron_module

    def _get_mem_spk(self):
        mem_seq = self.net.mem_rec[self._neuron_layer][:, 0, :]
        spk_seq = self.net.spk_rec[self._neuron_layer][:, 0, :]
        return mem_seq, spk_seq

    def initialize_sdsp_weights(self, low=14, high=22, seed=None):
        """Initialize the SDSP weight register once with unsigned integers.

        Parameters
        ----------
        low, high:
            Inclusive integer limits for the initial SDSP weight codes. For
            example, low=14 and high=22 generates W_reg in {14, ..., 22}.
            These are register values; the corresponding network weight is
            W_float = W_reg / (2 ** fp_dec).
        seed:
            Optional local random seed. Supplying a seed makes the initial
            weight register reproducible without changing PyTorch's global
            random-number state.

        This method overwrites only the values of the NetBuilder-created FC
        layer. It does not recreate the layer, neuron, topology, forward path,
        or VHDL-generation structure.
        """
        low = int(low)
        high = int(high)

        if low < 0:
            raise ValueError(f"weight_init_low must be >= 0; got {low}.")
        if high < low:
            raise ValueError(
                "weight_init_high must be >= weight_init_low; "
                f"got low={low}, high={high}."
            )
        if high > int(self.sdsp.w_max):
            raise ValueError(
                "Initial weight range exceeds the SDSP register limit: "
                f"high={high}, w_max={int(self.sdsp.w_max)}."
            )

        generator = None
        if seed is not None:
            generator = torch.Generator(device="cpu")
            generator.manual_seed(int(seed))

        W_reg = torch.randint(
            low=low,
            high=high + 1,  # torch.randint upper bound is exclusive
            size=self._fc_layer.weight.shape,
            dtype=torch.int64,
            device=self.device,
            generator=generator,
        )

        self._write_weight_register(W_reg)
        self._sdsp_weights_initialized = True

        scale = float(2 ** self.fp_dec)
        logging.info(
            "Initialized unsigned SDSP weights once | int range: [%d, %d] | "
            "actual min/max/mean: %d/%d/%.3f | float mean: %.8f | "
            "nonzero: %d/%d | seed: %s",
            low,
            high,
            int(W_reg.min().item()),
            int(W_reg.max().item()),
            float(W_reg.float().mean().item()),
            float(W_reg.float().mean().item() / scale),
            int((W_reg != 0).sum().item()),
            int(W_reg.numel()),
            str(seed),
        )

        return W_reg.detach().clone()

    def _read_weight_register(self):
        scale = 2 ** self.fp_dec
        W_int = (self._fc_layer.weight.detach() * scale).round().long()
        return W_int.clamp(0, self.sdsp.w_max)

    def _write_weight_register(self, W_reg):
        scale = 2 ** self.fp_dec
        W_float = W_reg.float() / scale
        with torch.no_grad():
            self._fc_layer.weight.copy_(W_float)

    def _reset_online_state(self):
        """Reset the SNN state and return the output-neuron membrane state."""
        self.net.reset()
        return self.net.mem[self._neuron_layer]

    def _online_forward_step(self, x_t, W_reg, mem, teacher):
        """Run one FC -> neuron timestep using the *current* SDSP weights.

        W_reg is intentionally used directly instead of writing it into the
        nn.Linear module at every timestep. This makes W(t+1) affect the next
        timestep while keeping the expensive module write-back to once/sample.
        """
        if x_t.shape[-1] != self._fc_layer.in_features:
            raise RuntimeError(
                "Input feature size does not match the SDSP FC layer: "
                f"{x_t.shape[-1]} vs {self._fc_layer.in_features}."
            )

        W_float = W_reg.to(dtype=x_t.dtype) / float(2 ** self.fp_dec)
        neuron_input = F.linear(x_t, W_float, bias=None)

        if teacher is not None:
            neuron_input = neuron_input + teacher.to(
                device=neuron_input.device, dtype=neuron_input.dtype
            )

        spk, mem = self._neuron_module(neuron_input, mem)
        return spk, mem

    def _make_teacher_current(self, label):
        """Create a positive current only for the target output neuron."""
        if self.teacher_current <= 0.0:
            return None

        teacher = torch.zeros(
            self.sdsp.Ca.numel(),
            device=self.device,
            dtype=torch.float32,
        )
        teacher[label] = self.teacher_current
        return teacher

    # ------------------------------------------------------------------
    # SDSP training
    # ------------------------------------------------------------------

    def _train_one_sample(self, single_data, label):
        """Train one sample with true timestep-level online SDSP.

        Ordering for each timestep t:
            current W(t) -> FC -> teacher current -> neuron dynamics
            -> SDSP update -> W(t+1)

        Therefore the weight update produced at timestep t is already used by
        the forward computation at timestep t+1. This removes the previous
        whole-image-forward-then-replay behaviour.
        """
        self.net.eval()
        teacher = self._make_teacher_current(label)

        W_reg = self._read_weight_register()
        W_before = W_reg.clone()
        self.sdsp.reset_ca()
        mem = self._reset_online_state()

        pre_seq = single_data[:, 0, :]
        spk_records = []
        mem_records = []

        n_post = int(self.sdsp.Ca.numel())
        debug = self.debug_count < self.debug_samples

        # Diagnostics. These masks mirror the CURRENT SDSP.step() timing:
        # the presynaptic event first reads the already-existing Ca state;
        # only after the SDSP decision does the current postsynaptic spike
        # update Ca for future events.
        ltp_requested = torch.zeros(n_post, dtype=torch.long)
        ltd_requested = torch.zeros(n_post, dtype=torch.long)
        ltp_effective_units = torch.zeros(n_post, dtype=torch.long)
        ltd_effective_units = torch.zeros(n_post, dtype=torch.long)
        pre_active_steps = 0
        vmem_high_pre_steps = torch.zeros(n_post, dtype=torch.long)
        vmem_low_pre_steps = torch.zeros(n_post, dtype=torch.long)

        # Target-neuron diagnostics.
        target_ca_hist = torch.zeros(self.sdsp.ca_max + 1, dtype=torch.long)
        target_vmem_pre_values = []
        target_vmem_eligible_values = []
        target_eligible_high_steps = 0
        target_eligible_low_steps = 0

        with torch.no_grad():
            for t in range(pre_seq.shape[0]):
                if t > 0 and t % self.leak_interval == 0:
                    self.sdsp.ca_leak()

                bist_event = (
                    self.bist_interval is not None
                    and t > 0
                    and t % self.bist_interval == 0
                )

                x_t = single_data[t]  # [1, n_pre]

                # Forward uses the current local integer weight register.
                spk_t, mem = self._online_forward_step(
                    x_t=x_t,
                    W_reg=W_reg,
                    mem=mem,
                    teacher=teacher,
                )

                spk_vec = spk_t[0]
                mem_vec = mem[0]
                pre_vec = pre_seq[t]

                spk_records.append(spk_vec.detach().clone())
                mem_records.append(mem_vec.detach().clone())

                # Diagnostic prediction of the masks inside the CURRENT
                # SDSP.step(). This does NOT alter the learning behaviour.
                #
                # IMPORTANT: use the OLD/current Ca state here. The current
                # postsynaptic spike has NOT updated Ca yet; sdsp.step() will
                # apply spk_post to Ca only after the current pre-triggered
                # learning decision.
                if debug and bool(pre_vec.any()):
                    pre_active_steps += 1
                    ca_for_rule = self.sdsp.Ca.detach().clone()

                    up = (ca_for_rule >= self.sdsp.theta1) & (
                        ca_for_rule < self.sdsp.theta3
                    )
                    down = (ca_for_rule >= self.sdsp.theta1) & (
                        ca_for_rule < self.sdsp.theta2
                    )
                    vmem_high = mem_vec >= self.sdsp.theta_m
                    vmem_low = ~vmem_high

                    dW_pos_req = torch.outer(
                        (up & vmem_high).float(), pre_vec.float()
                    )
                    dW_neg_req = torch.outer(
                        (down & vmem_low).float(), pre_vec.float()
                    )
                    ltp_requested += dW_pos_req.sum(dim=1).long().cpu()
                    ltd_requested += dW_neg_req.sum(dim=1).long().cpu()
                    vmem_high_pre_steps += vmem_high.long().cpu()
                    vmem_low_pre_steps += vmem_low.long().cpu()

                    # Record the target neuron's membrane distribution whenever
                    # at least one presynaptic spike is active.
                    target_vmem = float(mem_vec[label].item())
                    target_vmem_pre_values.append(target_vmem)

                    target_ca = int(ca_for_rule[label].item())
                    target_ca = max(0, min(target_ca, self.sdsp.ca_max))
                    target_ca_hist[target_ca] += 1

                    # Also record membrane statistics only when the target
                    # neuron's Ca state actually allows an SDSP update.
                    target_eligible = bool((up[label] | down[label]).item())
                    if target_eligible:
                        target_vmem_eligible_values.append(target_vmem)
                        if bool(vmem_high[label].item()):
                            target_eligible_high_steps += 1
                        else:
                            target_eligible_low_steps += 1

                W_prev = W_reg
                W_reg = self.sdsp.step(
                    spk_pre=pre_vec,
                    Vmem=mem_vec,
                    spk_post=spk_vec,
                    W=W_reg,
                    bist=bist_event,
                )

                if debug:
                    delta_step = W_reg.long() - W_prev.long()
                    ltp_effective_units += torch.clamp(
                        delta_step, min=0
                    ).sum(dim=1).long().cpu()
                    ltd_effective_units += torch.clamp(
                        -delta_step, min=0
                    ).sum(dim=1).long().cpu()

        spk_seq = torch.stack(spk_records, dim=0)
        mem_seq = torch.stack(mem_records, dim=0)

        # Publish the final W after this image so evaluation and the next
        # sample see exactly the same state reached by the online loop.
        self._write_weight_register(W_reg)

        if debug:
            self._print_debug(
                label=label,
                pre_seq=pre_seq,
                mem_seq=mem_seq,
                spk_seq=spk_seq,
                W_before=W_before,
                W_after=W_reg,
                ltp_requested=ltp_requested,
                ltd_requested=ltd_requested,
                ltp_effective_units=ltp_effective_units,
                ltd_effective_units=ltd_effective_units,
                pre_active_steps=pre_active_steps,
                vmem_high_pre_steps=vmem_high_pre_steps,
                vmem_low_pre_steps=vmem_low_pre_steps,
                target_ca_hist=target_ca_hist,
                target_vmem_pre_values=target_vmem_pre_values,
                target_vmem_eligible_values=target_vmem_eligible_values,
                target_eligible_high_steps=target_eligible_high_steps,
                target_eligible_low_steps=target_eligible_low_steps,
            )

        self.debug_count += 1
        return spk_seq

    @staticmethod
    def _summarize_values(values):
        """Return min/P10/P25/P50/P75/P90/max for a list of scalar values."""
        if not values:
            return None

        tensor = torch.tensor(values, dtype=torch.float32)
        q = torch.tensor([0.10, 0.25, 0.50, 0.75, 0.90], dtype=torch.float32)
        quantiles = torch.quantile(tensor, q)

        return {
            "count": int(tensor.numel()),
            "min": float(tensor.min().item()),
            "p10": float(quantiles[0].item()),
            "p25": float(quantiles[1].item()),
            "p50": float(quantiles[2].item()),
            "p75": float(quantiles[3].item()),
            "p90": float(quantiles[4].item()),
            "max": float(tensor.max().item()),
        }

    @staticmethod
    def _print_value_summary(name, summary):
        if summary is None:
            print(f"{name}: no samples")
            return

        print(
            f"{name}: "
            f"n={summary['count']} | "
            f"min={summary['min']:.4f} | "
            f"P10={summary['p10']:.4f} | "
            f"P25={summary['p25']:.4f} | "
            f"P50={summary['p50']:.4f} | "
            f"P75={summary['p75']:.4f} | "
            f"P90={summary['p90']:.4f} | "
            f"max={summary['max']:.4f}"
        )

    def _print_debug(
        self,
        label,
        pre_seq,
        mem_seq,
        spk_seq,
        W_before,
        W_after,
        ltp_requested,
        ltd_requested,
        ltp_effective_units,
        ltd_effective_units,
        pre_active_steps,
        vmem_high_pre_steps,
        vmem_low_pre_steps,
        target_ca_hist,
        target_vmem_pre_values,
        target_vmem_eligible_values,
        target_eligible_high_steps,
        target_eligible_low_steps,
    ):
        delta = W_after.float() - W_before.float()

        print(f"\n--- Debug sample {self.debug_count} ---")
        print("label             :", label)
        print("teacher current   :", self.teacher_current)
        print("pre spikes        :", pre_seq.sum().item())
        print("post spikes       :", spk_seq.sum().item())
        print("mem min/max       :", mem_seq.min().item(), mem_seq.max().item())
        print("spikes per output :", spk_seq.sum(dim=0).tolist())
        print(
            "W before min/max/nonzero:",
            W_before.min().item(),
            W_before.max().item(),
            (W_before != 0).sum().item(),
        )
        print("weight changed     :", (delta != 0).sum().item())
        print("net positive count :", (delta > 0).sum().item())
        print("net negative count :", (delta < 0).sum().item())
        print("weight delta sum   :", delta.sum().item())
        print("row delta sums     :", delta.sum(dim=1).tolist())
        print("weight row sums    :", W_after.sum(dim=1).tolist())
        print(
            "W after min/max/nonzero:",
            W_after.min().item(),
            W_after.max().item(),
            (W_after != 0).sum().item(),
        )
        print("Ca final           :", self.sdsp.Ca.tolist())

        print("--- SDSP event diagnostics ---")
        print("pre-active steps   :", pre_active_steps)
        print("LTP requested/post :", ltp_requested.tolist())
        print("LTD requested/post :", ltd_requested.tolist())
        print("effective +units   :", ltp_effective_units.tolist())
        print("effective -units   :", ltd_effective_units.tolist())
        print(
            f"target neuron {label} requested LTP/LTD :",
            int(ltp_requested[label].item()),
            "/",
            int(ltd_requested[label].item()),
        )
        print(
            f"target neuron {label} effective +/− units:",
            int(ltp_effective_units[label].item()),
            "/",
            int(ltd_effective_units[label].item()),
        )
        print(
            f"target neuron {label} Vmem high/low @ pre-active steps:",
            int(vmem_high_pre_steps[label].item()),
            "/",
            int(vmem_low_pre_steps[label].item()),
        )
        print(
            f"target neuron {label} Ca histogram @ pre-active steps:",
            target_ca_hist.tolist(),
        )

        print(
            f"target neuron {label} Vmem high/low @ Ca-eligible pre-active steps:",
            target_eligible_high_steps,
            "/",
            target_eligible_low_steps,
        )

        pre_summary = self._summarize_values(target_vmem_pre_values)
        eligible_summary = self._summarize_values(target_vmem_eligible_values)

        self._print_value_summary(
            f"target neuron {label} Vmem distribution @ all pre-active steps",
            pre_summary,
        )
        self._print_value_summary(
            f"target neuron {label} Vmem distribution @ Ca-eligible pre-active steps",
            eligible_summary,
        )
        print(f"theta_m           : {self.sdsp.theta_m}")

    def _train_one_epoch(self, dataloader):
        correct = 0
        total = 0

        for data, labels in dataloader:
            data = data.permute(1, 0, 2).to(self.device)
            labels = labels.to(self.device)

            for i in range(data.shape[1]):
                label = int(labels[i].item())
                spk_seq = self._train_one_sample(
                    data[:, i:i + 1, :],
                    label,
                )

                pred = int(spk_seq.sum(dim=0).argmax().item())
                correct += int(pred == label)
                total += 1

        return correct / total if total else 0.0

    # ------------------------------------------------------------------
    # Evaluation
    # ------------------------------------------------------------------

    def _predict_winner(self, single_data):
        """Inference without teacher current or weight updates."""
        self.net.eval()
        with torch.no_grad():
            self.net(single_data)

        _, spk_seq = self._get_mem_spk()
        spike_counts = spk_seq.sum(dim=0)
        winner = int(spike_counts.argmax().item())
        return winner, spike_counts

    def _evaluate_raw(self, dataloader):
        correct = 0
        total = 0

        for data, labels in dataloader:
            data = data.permute(1, 0, 2).to(self.device)
            labels = labels.to(self.device)

            for i in range(data.shape[1]):
                label = int(labels[i].item())
                winner, _ = self._predict_winner(data[:, i:i + 1, :])
                correct += int(winner == label)
                total += 1

        return correct / total if total else 0.0

    def _build_neuron_label_mapping(self, dataloader, max_samples=5000):
        n_classes = int(self.sdsp.Ca.numel())
        confusion = torch.zeros(n_classes, n_classes, dtype=torch.long)
        samples_seen = 0

        for data, labels in dataloader:
            data = data.permute(1, 0, 2).to(self.device)
            labels = labels.to(self.device)

            for i in range(data.shape[1]):
                if samples_seen >= max_samples:
                    break

                label = int(labels[i].item())
                winner, _ = self._predict_winner(data[:, i:i + 1, :])
                confusion[label, winner] += 1
                samples_seen += 1

            if samples_seen >= max_samples:
                break

        neuron_to_label = confusion.argmax(dim=0)

        print("\n=== Calibration mapping ===")
        print("Samples used:", samples_seen)
        print("Calibration confusion matrix (rows=true, columns=winning neuron):")
        print(confusion)
        print("Fixed neuron-to-label mapping:", neuron_to_label.tolist())
        print("===========================\n")

        return neuron_to_label

    def _evaluate_with_mapping(self, dataloader, neuron_to_label):
        n_classes = int(self.sdsp.Ca.numel())

        raw_correct = 0
        mapped_correct = 0
        total = 0

        winner_hist = torch.zeros(n_classes, dtype=torch.long)
        mapped_hist = torch.zeros(n_classes, dtype=torch.long)
        label_hist = torch.zeros(n_classes, dtype=torch.long)
        raw_confusion = torch.zeros(n_classes, n_classes, dtype=torch.long)
        mapped_confusion = torch.zeros(n_classes, n_classes, dtype=torch.long)

        silent_count = 0
        tie_count = 0
        total_post_spikes = 0.0

        for data, labels in dataloader:
            data = data.permute(1, 0, 2).to(self.device)
            labels = labels.to(self.device)

            for i in range(data.shape[1]):
                label = int(labels[i].item())
                winner, spike_counts = self._predict_winner(
                    data[:, i:i + 1, :]
                )
                mapped_pred = int(neuron_to_label[winner].item())

                sample_spikes = float(spike_counts.sum().item())
                total_post_spikes += sample_spikes
                silent_count += int(sample_spikes == 0.0)
                tie_count += int(
                    (spike_counts == spike_counts.max()).sum().item() > 1
                )

                winner_hist[winner] += 1
                mapped_hist[mapped_pred] += 1
                label_hist[label] += 1
                raw_confusion[label, winner] += 1
                mapped_confusion[label, mapped_pred] += 1

                raw_correct += int(winner == label)
                mapped_correct += int(mapped_pred == label)
                total += 1

        raw_accuracy = raw_correct / total if total else 0.0
        mapped_accuracy = mapped_correct / total if total else 0.0

        print("\n=== Independent mapped evaluation ===")
        print("Fixed neuron-to-label mapping:", neuron_to_label.tolist())
        print("Winning-neuron histogram:", winner_hist.tolist())
        print("Mapped prediction histogram:", mapped_hist.tolist())
        print("Label histogram:", label_hist.tolist())
        print(f"Silent samples: {silent_count}/{total}")
        print(f"Tied predictions: {tie_count}/{total}")
        if total:
            print(f"Mean post spikes/sample: {total_post_spikes / total:.4f}")
        print("Raw confusion matrix (rows=true, columns=winning neuron):")
        print(raw_confusion)
        print("Mapped confusion matrix (rows=true, columns=mapped label):")
        print(mapped_confusion)
        print(f"Raw accuracy   : {raw_accuracy * 100:.2f}%")
        print(f"Mapped accuracy: {mapped_accuracy * 100:.2f}%")
        print("=====================================\n")

        return raw_accuracy, mapped_accuracy

    # ------------------------------------------------------------------
    # Public interface
    # ------------------------------------------------------------------

    def train(
        self,
        train_loader,
        val_loader,
        n_epochs=20,
        store=False,
        output_dir="Trained",
        calibration_samples=5000,
    ):
        start_time = time.time()
        mapped_history = []

        print("\n==================================================")
        print("Mapped evaluation BEFORE training")
        print("==================================================")

        mapping = self._build_neuron_label_mapping(
            train_loader,
            max_samples=calibration_samples,
        )
        raw_acc, mapped_acc = self._evaluate_with_mapping(val_loader, mapping)
        mapped_history.append(mapped_acc)

        print(
            f"Before training | Raw accuracy: {raw_acc * 100:.2f}% | "
            f"Mapped accuracy: {mapped_acc * 100:.2f}%"
        )

        for epoch in range(n_epochs):
            train_acc = self._train_one_epoch(train_loader)
            val_acc = self._evaluate_raw(val_loader)
            self._log(epoch, train_acc, val_acc, start_time)

            print("\n==================================================")
            print(f"Mapped evaluation AFTER epoch {epoch}")
            print("==================================================")

            mapping = self._build_neuron_label_mapping(
                train_loader,
                max_samples=calibration_samples,
            )
            raw_acc, mapped_acc = self._evaluate_with_mapping(
                val_loader,
                mapping,
            )
            mapped_history.append(mapped_acc)

            print(
                f"Epoch {epoch} | Raw accuracy: {raw_acc * 100:.2f}% | "
                f"Mapped accuracy: {mapped_acc * 100:.2f}%"
            )

        print("\n==================================================")
        print("Mapped accuracy history")
        print("==================================================")
        print(f"Before training : {mapped_history[0] * 100:.2f}%")
        for epoch, acc in enumerate(mapped_history[1:]):
            print(f"After epoch {epoch:2d}: {acc * 100:.2f}%")
        print("==================================================")

        if store:
            self._store(output_dir)

    def _log(self, epoch, train_acc, val_acc, start_time):
        train_label = (
            "Train accuracy (teacher-assisted)"
            if self.teacher_current > 0.0
            else "Train accuracy"
        )
        logging.info(
            "\nEpoch %d\nElapsed time : %.2fs\n"
            "%s: %.2f%%\nVal   accuracy: %.2f%%\n",
            epoch,
            time.time() - start_time,
            train_label,
            train_acc * 100,
            val_acc * 100,
        )

    def _store(self, out_dir, out_file="sdsp_weights.pt"):
        os.makedirs(out_dir, exist_ok=True)
        out_path = os.path.join(out_dir, out_file)
        torch.save(self.net.state_dict(), out_path)
        logging.info("Weights saved to %s", out_path)
