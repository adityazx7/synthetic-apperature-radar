%% Polarimetric SAR (PolSAR) Simulation & Pauli Decomposition
% Self-contained script (requires no external toolboxes)
clear; close all; clc;
rng(42);

%% 1. Scene & Grid Initialization
grid_size = 120;
[X, Y] = meshgrid(linspace(-50, 50, grid_size), linspace(-50, 50, grid_size));

% Initialize the 4 complex polarization scattering channels
S_HH = complex(zeros(grid_size, grid_size));
S_VV = complex(zeros(grid_size, grid_size));
S_HV = complex(zeros(grid_size, grid_size));
S_VH = complex(zeros(grid_size, grid_size));

%% 2. Populate Target Zones with Distinct Scattering Physics
% Zone A: Flat Ground / Soil (Surface / Odd Bounce dominant)
% S_HH ≈ S_VV, S_HV ≈ 0
surface_mask = Y < -15;
S_HH(surface_mask) = (0.8 + 0.1*randn(sum(surface_mask(:)), 1)) .* exp(1j*2*pi*rand(sum(surface_mask(:)), 1));
S_VV(surface_mask) = S_HH(surface_mask) .* (0.9 + 0.05*randn(sum(surface_mask(:)), 1));
S_HV(surface_mask) = 0.05 * (randn(sum(surface_mask(:)), 1) + 1j*randn(sum(surface_mask(:)), 1));

% Zone B: Forest / Vegetation Canopy (Volume / Cross-Pol dominant)
% Strong depolarization: High S_HV, S_HH uncorrelated with S_VV
forest_mask = Y >= -15 & Y < 15;
S_HH(forest_mask) = 0.4 * (randn(sum(forest_mask(:)), 1) + 1j*randn(sum(forest_mask(:)), 1));
S_VV(forest_mask) = 0.4 * (randn(sum(forest_mask(:)), 1) + 1j*randn(sum(forest_mask(:)), 1));
S_HV(forest_mask) = 0.6 * (randn(sum(forest_mask(:)), 1) + 1j*randn(sum(forest_mask(:)), 1));

% Zone C: Urban Buildings / Dihedral Corner Reflectors (Double Bounce dominant)
% 180° phase flip between HH and VV: S_HH ≈ -S_VV
urban_mask = Y >= 15;
S_HH(urban_mask) = (1.2 + 0.1*randn(sum(urban_mask(:)), 1)) .* exp(1j*2*pi*rand(sum(urban_mask(:)), 1));
S_VV(urban_mask) = -S_HH(urban_mask) .* (0.95 + 0.05*randn(sum(urban_mask(:)), 1));
S_HV(urban_mask) = 0.1 * (randn(sum(urban_mask(:)), 1) + 1j*randn(sum(urban_mask(:)), 1));

% Reciprocity theorem enforcement for monostatic radar: S_VH = S_HV
S_VH = S_HV;

% Add Receiver Noise (SNR = 22 dB)
snr_db = 22;
add_noise = @(S) S + sqrt((mean(abs(S(:)).^2)/(10^(snr_db/10)))/2) * (randn(size(S)) + 1j*randn(size(S)));
S_HH = add_noise(S_HH);
S_VV = add_noise(S_VV);
S_HV = add_noise(S_HV);

%% 3. Pauli Target Decomposition Basis
% Pauli Vector Components:
% k1 = (S_HH + S_VV) / sqrt(2) -> Single/Odd Bounce (Blue)
% k2 = (S_HH - S_VV) / sqrt(2) -> Double/Even Bounce (Red)
% k3 = sqrt(2) * S_HV          -> Volume/Random Scattering (Green)
alpha = (S_HH + S_VV) / sqrt(2);
beta  = (S_HH - S_VV) / sqrt(2);
gamma = sqrt(2) * S_HV;

% Calculate Intensity Powers
power_odd    = abs(alpha).^2;
power_double = abs(beta).^2;
power_volume = abs(gamma).^2;
span_total   = abs(S_HH).^2 + abs(S_VV).^2 + 2*abs(S_HV).^2;

% Construct Pauli RGB Composite Map with 98th-percentile clipping
R = power_double; % Red: Double Bounce
G = power_volume; % Green: Volume
B = power_odd;    % Blue: Surface

pc = @(x) min(1, x / subsref(sort(x(:)), struct('type','()','subs',{{round(0.98*numel(x))}})));
R_norm = pc(R);
G_norm = pc(G);
B_norm = pc(B);
pauli_rgb = cat(3, R_norm, G_norm, B_norm);

%% 4. Visualization
figure('Color', 'w', 'Position', [100, 100, 1100, 700]);

subplot(2, 2, 1);
imagesc(20*log10(abs(S_HH)), [-25, 5]); colormap(gca, 'gray'); colorbar;
title('|S_{HH}| Intensity (dB)'); xlabel('Cross-Track'); ylabel('Along-Track'); axis square;

subplot(2, 2, 2);
imagesc(20*log10(abs(S_HV)), [-25, 5]); colormap(gca, 'gray'); colorbar;
title('|S_{HV}| Cross-Pol Intensity (dB)'); xlabel('Cross-Track'); ylabel('Along-Track'); axis square;

subplot(2, 2, 3);
imagesc(10*log10(span_total), [-20, 10]); colormap(gca, 'turbo'); colorbar;
title('Total PolSAR SPAN Power (dB)'); xlabel('Cross-Track'); ylabel('Along-Track'); axis square;

subplot(2, 2, 4);
image(pauli_rgb); axis image; axis square;
title('Pauli RGB Composite (Red: Dbl, Green: Vol, Blue: Surf)');
xlabel('Cross-Track'); ylabel('Along-Track');

disp('PolSAR simulation and Pauli decomposition complete!');