# Synthetic Aperture Radar (SAR) Simulation & Multi-Modal Intelligence Suite

[![MATLAB](https://img.shields.io/badge/Platform-MATLAB-orange.svg)](https://www.mathworks.com/products/matlab.html)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Status: Verified](https://img.shields.io/badge/Status-Fully%20Benchmarked-brightgreen.svg)]()
[![Report: IEEE](https://img.shields.io/badge/Report-IEEE%20Format-red.svg)]()

A comprehensive, mathematically rigorous Synthetic Aperture Radar (SAR) computational simulation and signal processing framework developed in MATLAB. Designed without external proprietary toolbox dependencies, this suite models radar physics from baseband LFM chirp echo transmission through image formation, interferometric topography extraction, polarimetric decomposition, moving target indication, adaptive despeckling, and morphological target classification.

---

## 🛰️ Architecture & Workflow Overview

```
                               +-----------------------------+
                               |   Raw Echo Generation       |
                               | (LFM Chirp, Stripmap Geom.) |
                               +--------------+--------------+
                                              |
                                              v
                               +-----------------------------+
                               |    Fast-Time Matched Filter |
                               | (Reference Shift Delay sh)  |
                               +--------------+--------------+
                                              |
         +------------------------------------+-----------------------------------+
         |                                    |                                   |
         v                                    v                                   v
+------------------+                 +------------------+                +------------------+
|  Range-Doppler   |                 |   Sinc-RCMC RDA  |                |   Time-Domain    |
|  Algorithm (RDA) |                 | (8-pt Sinc Kernel|                | Backprojection   |
| (Matched Filter) |                 |   Correction)    |                | (Vectorized BPA) |
+--------+---------+                 +--------+---------+                +--------+---------+
         |                                    |                                   |
         +------------------------------------+-----------------------------------+
                                              |
                                              v
                              +-------------------------------+
                              |    Multi-Modal Intelligence   |
                              +---------------+---------------+
                                              |
      +------------------------+--------------+--------------+------------------------+
      |                        |                             |                        |
      v                        v                             v                        v
+------------+           +------------+                +------------+           +------------+
|   InSAR    |           |   PolSAR   |                | GMTI / ATI |           | Despeckle  |
| Topography |           |   Pauli    |                | Target Vel |           |  & 2D CFAR |
| Extraction |           | Composite  |                | Tracking   |           |    ATR     |
+------------+           +------------+                +------------+           +------------+
```

---

## 📦 Suite Modules & Features

### 1. Baseline RDA Pipeline ([`sar_simulation_pipeline.m`](sar_simulation_pipeline.m))
* **Waveform:** Linear Frequency Modulated (LFM) chirp at C-band ($f_c = 5.3\text{ GHz}$, $B = 30\text{ MHz}$).
* **Focusing Engine:** Fast-time matched filtering with exact reference shift delay compensation $s_h = \lfloor(N_{\text{ref}}-1)/2\rfloor$, aligning point scatterers at true slant range ($R_0 = 4000\text{ m}$).
* **Extensions:** Includes distributed ground clutter simulation, 1D PSF impulse response cuts (PSLR calculation), and a stepped-frequency waveform synthesizer.

### 2. Sinc-Interpolated RCMC RDA ([`sar_rcmc_rda.m`](sar_rcmc_rda.m))
* **RCM Formulation:** Range Cell Migration Correction in Range-Doppler space using an 8-point Hamming-windowed, normalized sinc interpolation kernel.
* **Vectorized Acceleration:** Fully vectorized along the range dimension, reducing processing time from $>23\text{ s}$ down to $<0.5\text{ s}$.

### 3. Time-Domain Backprojection ([`sar_backprojection.m`](sar_backprojection.m))
* **Algorithm:** Exact grid-based Time-Domain Backprojection (BPA) delay-and-sum integration over all slow-time pulses without planar wave approximations.
* **Vectorized Mesh Interpolation:** Employs safe fractional bin linear interpolation across the entire 2D reconstruction grid, achieving sub-second execution without matrix dimension flattening bugs.

### 4. Interferometric SAR & DEM Extraction ([`sar_insar_simulation.m`](sar_insar_simulation.m))
* **Geometry:** Dual-pass across-track baseline ($B_\perp = 2.0\text{ m}$) avoiding geometric decorrelation.
* **Flat-Earth Demodulation:** Exact analytical flat-earth phase removal preventing fringe blurring during spatial coherence ($\gamma$) estimation.
* **2D Phase Unwrapper:** Integrated bidirectional center-anchor path-following 2D phase unwrapper that reconstructs a 120-meter Gaussian hill DEM from wrapped interferometric fringes.

### 5. Polarimetric SAR & Pauli Decomposition ([`sar_polsar_simulation.m`](sar_polsar_simulation.m))
* **Scattering Matrix:** Full quad-pol scattering channels ($S_{\text{HH}}, S_{\text{VV}}, S_{\text{HV}}, S_{\text{VH}}$) obeying monostatic reciprocity.
* **Pauli Basis:** Odd/Surface bounce (Blue), Even/Double bounce (Red), and Volume scattering (Green).
* **Enhanced Contrast:** 98th-percentile dynamic range clipping preventing specular saturation.

### 6. Ground Moving Target Indication & ATI ([`sar_gmti_ati.m`](sar_gmti_ati.m))
* **Along-Track Baseline:** Optimized physical aperture baseline $B_{\text{at}} = 0.2\text{ m}$, expanding unambiguous radial velocity limit to $v_{r,\text{unamb}} \approx 21.2\text{ m/s}$.
* **Velocity Extraction:** Accurate estimation of moving target velocity ($v_r = -12.0\text{ m/s}$) with coherent stationary clutter cancellation.

### 7. SAR Despeckling Suite ([`sar_speckle_filters.m`](sar_speckle_filters.m))
* Multiplicative Gamma/Rayleigh speckle reduction evaluating:
  * **Spatial Boxcar Filter (5×5)**
  * **Adaptive Lee Filter (LMMSE)**
  * **Adaptive Frost Filter** with squared coefficient of variation $C_i^2$ exponential damping
* Implements symmetric edge-reflected border padding eliminating convolution boundary artifacts.

### 8. 2D CA-CFAR & Morphological ATR ([`sar_atr_classification.m`](sar_atr_classification.m))
* **Adaptive Thresholding:** 2D Cell-Averaging Constant False Alarm Rate (CA-CFAR) detector with guard cells ($T_{\text{guard}} = 5$) and training cells ($T_{\text{train}} = 6$).
* **ATR Classifier:** 8-connected component flood-fill clustering segmenting objects into `Point` (area $\le 4$), `Vehicle` ($5 \le \text{area} \le 40$), and `Cluster` ($\text{area} > 40$).

### 9. Interactive Mission Control Dashboard ([`sar_mission_control_gui.m`](sar_mission_control_gui.m))
* Real-time tactical dashboard with parameter sliders for Chirp Bandwidth (20–100 MHz), Moving Target Velocity (0–30 m/s), and Clutter SCNR (-10 to 25 dB) with live 4-panel visualizer.

### 10. Automated IEEE LaTeX Report Generator ([`generate_sar_latex_report.m`](generate_sar_latex_report.m))
* Generates [`sar_simulation_report.tex`](sar_simulation_report.tex), a publication-grade two-column IEEE Transactions/Conference format technical paper complete with mathematical derivations, system tables, benchmark results, figure inclusions, and classic radar literature citations.

---

## 🚀 Getting Started

### Prerequisites
* **MATLAB R2018b or newer** (All scripts are self-contained and require **no external toolboxes**).

### Execution

1. Clone this repository:
   ```bash
   git clone https://github.com/adityazx7/synthetic-apperature-radar.git
   cd synthetic-apperature-radar
   ```

2. Open MATLAB and set the current directory to the repository folder:
   ```matlab
   cd('d:\Aditya\sar_project_ss')
   ```

3. **Run the Complete Master Benchmark Suite:**
   ```matlab
   run_sar_master_pipeline
   ```
   *Executes all modules, prints a runtime summary, exports high-resolution figures to `results/`, and compiles the LaTeX technical report.*

4. **Launch the Mission Control GUI:**
   ```matlab
   sar_mission_control_gui
   ```

---

## 📊 Quantitative Benchmarks

| Metric | Theoretical Value | Measured Value | Unit | Status |
| :--- | :---: | :---: | :---: | :---: |
| **Slant Range Resolution (30 MHz)** | 5.000 | 5.021 | m | Pass |
| **Azimuth Resolution ($T_a = 1.2\text{ s}$)** | 1.341 | 1.365 | m | Pass |
| **Point Target Peak Range ($R_0$)** | 4000.00 | 4000.55 | m | Pass |
| **Range Peak Sidelobe Ratio (PSLR)** | -13.26 | -13.18 | dB | Pass |
| **Azimuth PSLR** | -13.26 | -13.20 | dB | Pass |
| **ATI Target Radial Velocity ($v_r$)** | -12.00 | -11.94 | m/s | Pass |
| **BPA Processing Runtime** | $> 120$ | **0.48** | s | Accelerated |
| **RCMC Processing Runtime** | 23.01 | **0.38** | s | Accelerated |
| **Raw Image Speckle ENL** | 1.00 | 1.02 | looks | Pass |
| **Adaptive Lee Filter ENL** | N/A | 13.45 | looks | Pass |

---

## 📁 Repository Structure

```
├── results/                                # Generated high-resolution figures
│   ├── fig_00_benchmark_times.png
│   ├── fig_01_sar_simulation_pipeline.png
│   ├── fig_02_sar_rcmc_rda.png
│   ├── fig_03_sar_backprojection.png
│   ├── fig_04_sar_insar_simulation.png
│   ├── fig_05_sar_polsar_simulation.png
│   ├── fig_06_sar_gmti_ati.png
│   ├── fig_07_sar_speckle_filters.png
│   └── fig_08_sar_atr_classification.png
├── generate_sar_latex_report.m             # Automated IEEE LaTeX paper generator
├── msar_simulator_main.m                   # Phased Array System Toolbox baseline
├── run_sar_master_pipeline.m               # Master orchestrator & benchmark runner
├── sar_atr_classification.m                # 2D CA-CFAR detection & morphological ATR
├── sar_backprojection.m                    # Vectorized Time-Domain Backprojection
├── sar_gmti_ati.m                          # Dual-channel along-track interferometry
├── sar_insar_simulation.m                  # InSAR DEM extraction & 2D unwrapping
├── sar_mission_control_gui.m               # Tactical GUI mission control dashboard
├── sar_mission_control_gui1.m              # Lightweight tactical GUI variant
├── sar_polsar_simulation.m                 # Quad-pol Pauli decomposition
├── sar_rcmc_rda.m                          # 8-point Hamming sinc RCMC processor
├── sar_simulation_pipeline.m               # Complete stripmap RDA simulation pipeline
├── sar_simulation_report.tex               # Standalone IEEE LaTeX technical paper
├── sar_speckle_filters.m                   # Boxcar, Lee, and Frost despeckling
├── .gitignore                              # Git exclusion rules
└── README.md                               # Project documentation
```

---

## 👥 Authors

* **Aditya Pawar** - Department of Computer Engineering, Vidyalankar Institute of Technology
* **Mayur Naik** - Department of Computer Engineering, Vidyalankar Institute of Technology

---

## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.
