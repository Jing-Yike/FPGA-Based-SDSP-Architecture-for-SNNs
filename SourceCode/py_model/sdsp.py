import torch

class SDSP:
    """
    Vectorized SDSP learning rule for a single fully-connected layer.

    Design notes
    ------------
    - Ca  : internal state, shape [n_post], one counter per post-synaptic neuron
    - W   : NOT stored internally; passed in as an explicit argument to step()
            and returned as W_new.  The caller (SDSPTrainer) owns the weight
            register and is responsible for read / write-back to the network.

    External scheduling signals (called by SDSPTrainer):
        ca_leak()  — corresponds to the time_ref signal in hardware
        step(..., bist=True) — corresponds to the bist signal in hardware
    """

    def __init__(self, n_pre, n_post,
                 theta1, theta2, theta3, theta_m,
                 weight_bits=3, ca_bits=3,
                 device='cpu'):

        assert 0 <= theta1 < theta2 < theta3 < 2**ca_bits

        self.theta1      = theta1
        self.theta2      = theta2
        self.theta3      = theta3
        self.theta_m     = theta_m
        self.ca_bits     = ca_bits
        self.weight_bits = weight_bits
        self.w_max       = 2**weight_bits - 1   # 7 for 3-bit
        self.ca_max      = 2**ca_bits - 1       # 7 for 3-bit
        self.device      = device

        # Ca: one calcium counter per post-synaptic neuron
        # W is no longer stored here; it is passed in per step() call
        self.Ca = torch.zeros(n_post, device=device)   # [n_post]

    # ── State management ───────────────────────────────────────────────

    def reset_ca(self):
        """Reset Ca to zero. Called at the start of each training sample."""
        self.Ca.zero_()

    def ca_leak(self):
        """
        Decrement Ca by 1 with floor at 0.
        Called periodically by SDSPTrainer to simulate the time_ref signal.
        """
        self.Ca = torch.clamp(self.Ca - 1, min=0)

    # ── Core SDSP step ────────────────────────────────────────────────

    def step(self, spk_pre, Vmem, spk_post, W, bist=False):
        """
        Execute one SDSP update step.

        Parameters
        ----------
        spk_pre  : Tensor [n_pre]        pre-synaptic spike vector  (0/1)
        Vmem     : Tensor [n_post]       post-synaptic membrane potential
        spk_post : Tensor [n_post]       post-synaptic spike vector (0/1)
        W        : Tensor [n_post,n_pre] current integer weight matrix
                   read from the weight register before calling this method
        bist     : bool                  bistability trigger flag,
                   corresponds to the external bist signal in hardware

        Returns
        -------
        W_new : Tensor [n_post, n_pre]  updated integer weight matrix
                the caller must write this back to the weight register
        """

        # ── 1. Compute learning flags from the CURRENT Ca state ──────
        # SDSP is triggered by the current presynaptic spike(s), so the
        # calcium value used for this synaptic update is the state that
        # already exists when the presynaptic event arrives.
        #
        # The current timestep's postsynaptic spike is applied to Ca only
        # AFTER the SDSP decision below; therefore it affects future
        # presynaptic events, not the current one.
        #
        #    up   : theta1 <= Ca < theta3  →  LTP eligible
        #    down : theta1 <= Ca < theta2  →  LTD eligible
        up   = (self.Ca >= self.theta1) & (self.Ca < self.theta3)  # [n_post]
        down = (self.Ca >= self.theta1) & (self.Ca < self.theta2)  # [n_post]

        # ── 2. Vmem threshold comparison ──────────────────────────────
        vmem_high = (Vmem >= self.theta_m)   # [n_post]  True → LTP direction
        vmem_low  = ~vmem_high               # [n_post]  True → LTD direction

        # ── 3. spk_pre triggered weight update ────────────────────────
        #    For every (post j, pre i) pair:
        #      Δw = +1  if spk_pre[i]=1 AND vmem_high[j]=1 AND up[j]=1
        #      Δw = -1  if spk_pre[i]=1 AND vmem_low[j]=1  AND down[j]=1
        #      Δw =  0  otherwise  (stop-learning region)
        W_new = W.clone()
        if spk_pre.any():
            dW_pos = torch.outer((up   & vmem_high).float(),
                                 spk_pre.float())   # [n_post, n_pre]
            dW_neg = torch.outer((down & vmem_low ).float(),
                                 spk_pre.float())   # [n_post, n_pre]
            W_new = torch.clamp(W_new + dW_pos - dW_neg,
                                min=0, max=self.w_max)

        # ── 4. Update Ca for FUTURE synaptic events ───────────────────
        # The current postsynaptic spike changes the calcium state only
        # after the current pre-triggered SDSP decision has completed.
        self.Ca = torch.clamp(self.Ca + spk_post.float(), max=self.ca_max)

        # ── 5. Bistability triggered weight update ────────────────────
        #    Corresponds to the external bist signal in hardware.
        #    Read MSB of each weight: push toward w_max if MSB=1, toward 0 if MSB=0
        if bist:
            msb     = (W_new >= 2**(self.weight_bits - 1)).float()
            dW_bist = 2 * msb - 1          # +1 where msb=1, -1 where msb=0

            pre_active = spk_pre.bool().unsqueeze(0).expand_as(dW_bist)  # [n_post, n_pre]
            dW_bist = torch.where(pre_active, torch.zeros_like(dW_bist), dW_bist)

            W_new = torch.clamp(W_new + dW_bist, min=0, max=self.w_max)

        return W_new