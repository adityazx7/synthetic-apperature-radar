%% SAR Imaging with Sinc-Interpolated Range Cell Migration Correction (RCMC)
% Self-contained script (requires no external toolboxes)
clear; close all; clc;

%% 1. Radar & Geometry Parameters
c = 3e8;                    % Speed of light (m/s)
fc = 5.3e9;                 % Carrier frequency (Hz)
lambda = c / fc;            % Wavelength (m)
B = 60e6;                   % Expanded bandwidth for pronounced RCM (Hz)
Tp = 5e-6;                  % Pulse width (s)
Kr = B / Tp;                % FM rate (Hz/s)
fs = 2.4 * B;               % Fast-time sampling rate (Hz)
v = 150;                    % Platform velocity (m/s)
H = 3000;                   % Altitude (m)
R0_center = 4000;           % Reference slant range (m)
PRF = 800;                  % PRF (Hz)
PRT = 1 / PRF;

%% 2. Target Scene (Widely Spaced Point Targets)
targets = [
      0, sqrt(R0_center^2 - H^2),      1.0;
    -40, sqrt(R0_center^2 - H^2) - 40, 0.8;
     40, sqrt(R0_center^2 - H^2) + 40, 0.9
];
N_targets = size(targets, 1);

%% 3. Time Grid Initialization
Ta = 2.5;                           % Extended synthetic aperture duration (s)
t_eta = -Ta/2 : PRT : Ta/2;          % Slow-time axis
Na = length(t_eta);
R_min = sqrt(min(targets(:,2)).^2 + H^2) - 150;
R_max = sqrt(max(targets(:,2)).^2 + H^2) + 150;
t_tau = (2*R_min/c - Tp/2) : 1/fs : (2*R_max/c + Tp/2);
Nr = length(t_tau);
range_axis = (c * t_tau) / 2;
delta_r = c / (2 * fs);             % Range sample spacing (m)

%% 4. Raw Signal Generation
raw_data = zeros(Na, Nr);
for p = 1:Na
    eta = t_eta(p);
    x_plat = v * eta;
    pulse_echo = zeros(1, Nr);
    for k = 1:N_targets
        R_inst = sqrt((x_plat - targets(k,1))^2 + targets(k,2)^2 + H^2);
        tau_delay = 2 * R_inst / c;
        tau_diff = t_tau - tau_delay;
        rect_pulse = abs(tau_diff) <= (Tp/2);
        phase = -2*pi*fc*tau_delay + pi*Kr*(tau_diff.^2);
        pulse_echo = pulse_echo + targets(k,3) * rect_pulse .* exp(1j * phase);
    end
    raw_data(p, :) = pulse_echo;
end

%% 5. Fast-Time Range Compression
tau_ref = -Tp/2 : 1/fs : Tp/2;
s_ref = exp(1j * pi * Kr * tau_ref.^2);
sh = round((length(tau_ref) - 1) / 2);
N_fft_r = 2^nextpow2(Nr + length(tau_ref) - 1);
H_range = fft(conj(s_ref), N_fft_r);
range_compressed = zeros(Na, Nr);
for p = 1:Na
    S_range = fft(raw_data(p, :), N_fft_r);
    comp = ifft(S_range .* H_range);
    range_compressed(p, :) = comp(1+sh : Nr+sh);
end

%% 6. Range-Doppler Domain Transformation (Azimuth FFT)
N_fft_a = 2^nextpow2(Na);
RD_data = fftshift(fft(range_compressed, N_fft_a, 1), 1);
f_eta = (-N_fft_a/2 : N_fft_a/2-1).' * PRF / N_fft_a;

%% 7. Sinc-Interpolation Range Cell Migration Correction (RCMC)
rcmc_data = zeros(N_fft_a, Nr);
P_sinc = 8; % 8-point sinc interpolation kernel length
disp('Executing 8-Point Sinc Interpolation RCMC...');

r_indices = 1:Nr;
for a_idx = 1:N_fft_a
    f_curr = f_eta(a_idx);
    
    % Doppler migration factor D(f_eta)
    arg_val = lambda * f_curr / (2 * v);
    if abs(arg_val) >= 1
        continue;
    end
    D_factor = sqrt(1 - arg_val^2);
    
    % Exact range migration shift to correct (meters)
    delta_R_rcmc = range_axis * (1 / D_factor - 1);
    r_mig_pos = r_indices + (delta_R_rcmc / delta_r);
    
    % Vectorized 8-Point Hamming-Windowed Sinc Interpolation
    idx_base = floor(r_mig_pos);
    frac = r_mig_pos - idx_base;
    row_in = RD_data(a_idx, :);
    
    interp_row = zeros(1, Nr);
    wsum = zeros(1, Nr);
    for n = -P_sinc/2 : (P_sinc/2 - 1)
        k_idx = idx_base + n;
        valid = (k_idx >= 1) & (k_idx <= Nr);
        k_safe = max(1, min(Nr, k_idx));
        xw = frac - n;
        sinc_weight = custom_sinc(xw) .* (0.54 + 0.46 * cos(pi * xw / (P_sinc / 2)));
        interp_row = interp_row + valid .* row_in(k_safe) .* sinc_weight;
        wsum = wsum + valid .* sinc_weight;
    end
    nz_mask = (wsum ~= 0);
    interp_row(nz_mask) = interp_row(nz_mask) ./ wsum(nz_mask);
    rcmc_data(a_idx, :) = interp_row;
end

%% 8. Azimuth Matched Filtering & IFFT
azimuth_compressed = zeros(N_fft_a, Nr);
for r_idx = 1:Nr
    R_current = range_axis(r_idx);
    Ka = 2 * v^2 / (lambda * R_current);
    H_az = exp(-1j * pi * (f_eta.^2) / Ka);
    azimuth_compressed(:, r_idx) = ifft(ifftshift(rcmc_data(:, r_idx) .* H_az));
end
final_rcmc_image = azimuth_compressed(1:Na, :);

%% 9. Visualization of RCMC Results
figure('Color', 'w', 'Position', [100, 100, 1500, 450]);
subplot(1, 3, 1);
imagesc(range_axis, f_eta, abs(RD_data));
colormap(gca, 'turbo'); colorbar; axis tight;
title('1. Range-Doppler (Before RCMC)'); xlabel('Slant Range (m)'); ylabel('Doppler (Hz)');

subplot(1, 3, 2);
imagesc(range_axis, f_eta, abs(rcmc_data));
colormap(gca, 'turbo'); colorbar; axis tight;
title('2. After Sinc RCMC'); xlabel('Slant Range (m)'); ylabel('Doppler (Hz)');

subplot(1, 3, 3);
imagesc(range_axis, t_eta * v, 20 * log10(abs(final_rcmc_image) / max(abs(final_rcmc_image(:))) + 1e-6), [-40 0]);
colormap(gca, 'turbo'); colorbar; axis tight;
title('3. Focused Image (dB)'); xlabel('Slant Range (m)'); ylabel('Azimuth (m)');

%% Local Helper Function: Custom Sinc (No Toolboxes Required)
function y = custom_sinc(x)
    y = ones(size(x));
    idx = (x ~= 0);
    y(idx) = sin(pi * x(idx)) ./ (pi * x(idx));
end