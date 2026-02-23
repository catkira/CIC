#!/usr/bin/env python3
"""Spectral analysis of the CIC interpolator model.

Feeds a 5 kHz sine wave (sampled at 20 kHz) into the CIC interpolator
model with R=4, producing 80 kHz output. Plots input and output spectra
for different values of N (CIC order), showing the spectral shaping
effect of the interpolation filter.
"""

import sys
import os
import math
import numpy as np
import matplotlib.pyplot as plt

# add project root so we can import the model
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from model.cic_i_model import Model

# parameters
R = 4
M = 1
INP_DW = 16
fs_in = 20_000       # 20 kHz input sample rate
fs_out = fs_in * R   # 80 kHz output sample rate
f_sig = 5_000        # 5 kHz sine wave
num_input_samples = 2048
amplitude = 2 ** (INP_DW - 1) - 1

N_values = [1, 2, 3, 4, 5]


def compute_spectrum(sig, fs):
    """Compute one-sided amplitude spectrum in dB using a Hann window."""
    N = len(sig)
    win = np.hanning(N)
    sig_w = sig * win
    # normalize for window energy loss
    sig_w /= np.sum(win) / N
    S = np.fft.rfft(sig_w)
    freq = np.fft.rfftfreq(N, d=1.0 / fs)
    mag = np.abs(S) / N
    # double non-DC/Nyquist bins for one-sided
    mag[1:-1] *= 2
    with np.errstate(divide='ignore'):
        mag_db = 20 * np.log10(mag)
    return freq, mag_db


def compute_out_dw(R, N, INP_DW):
    """Compute output width matching RTL: dw + clog2((r^m)/r)."""
    interp_gain = (R ** N) // R
    if interp_gain > 1:
        return INP_DW + math.ceil(math.log2(interp_gain))
    else:
        return INP_DW


# generate input signal
t_in = np.arange(num_input_samples) / fs_in
input_signal = np.round(amplitude * np.sin(2 * np.pi * f_sig * t_in)).astype(int)

# compute input spectrum
freq_in, spec_in = compute_spectrum(input_signal / amplitude, fs_in)

# run model for each N value
results = []
for N in N_values:
    OUT_DW = compute_out_dw(R, N, INP_DW)
    model = Model(R, N, M, INP_DW, OUT_DW)

    warmup_cycles = 3 * R + 2 * N
    total_fast_cycles = warmup_cycles + num_input_samples * R

    output = []
    cycle_count = 0
    input_idx = 0

    for _ in range(total_fast_cycles):
        model.tick()

        # collect output after warmup
        if cycle_count >= warmup_cycles and model.data_valid():
            output.append(model.get_scaled_data())

        # drive new input every R-th cycle
        if cycle_count % R == 0 and input_idx < num_input_samples:
            model.set_data(int(input_signal[input_idx]))
            input_idx += 1

        cycle_count += 1

    output = np.array(output, dtype=float)
    out_max = 2 ** (OUT_DW - 1) - 1
    freq_out, spec_out = compute_spectrum(output / out_max, fs_out)
    results.append((N, freq_out, spec_out))
    print(f"N={N}: OUT_DW={OUT_DW}, collected {len(output)} output samples")

# plot
num_plots = 1 + len(N_values)
fig, axes = plt.subplots(num_plots, 1, figsize=(10, 3 * num_plots), sharex=False)

# input spectrum
ax = axes[0]
ax.plot(freq_in / 1e3, spec_in, alpha=0.8)
ax.set_title("Input spectrum (fs = 20 kHz)")
ax.set_xlabel("Frequency [kHz]")
ax.set_ylabel("Magnitude [dB]")
ax.set_xlim(0, fs_in / 2e3)
ax.set_ylim(max(-160, np.min(spec_in)), 5)
ax.grid(True, alpha=0.3)

# output spectra
for i, (N, freq_out, spec_out) in enumerate(results):
    ax = axes[i + 1]
    ax.plot(freq_out / 1e3, spec_out, alpha=0.8)
    ax.set_title(f"Output spectrum N={N} (R={R}, M={M}, fs_out = {fs_out // 1000} kHz)")
    ax.set_xlabel("Frequency [kHz]")
    ax.set_ylabel("Magnitude [dB]")
    ax.set_xlim(0, fs_out / 2e3)
    ax.set_ylim(max(-160, np.min(spec_out)), 5)
    ax.grid(True, alpha=0.3)

plt.tight_layout()
plt.show()
