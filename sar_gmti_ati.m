%% SAR Ground Moving Target Indication (GMTI) & Along-Track Interferometry (ATI)
% Self-contained script (requires no external toolboxes)
clear; close all; clc;
rng(42);

%% 1. Radar & System Setup
c = 3e8;                    % Speed of light (m/s)
fc = 5.3e9;                 % Carrier frequency (Hz)
lambda = c / fc;            % Wavelength (m)
k0 = 2 * pi / lambda;       % Wavenumber
B = 30e6;                   % Chirp Bandwidth (Hz)
Tp = 5e-6;                  % Pulse duration (s)
Kr = B / Tp;                % FM rate (Hz/s)
fs = 2.4 * B;               % Fast-time sampling rate (Hz)

v = 150;                    % Platform along-track velocity (m/s)
H = 3000;                   % Flight Altitude (m)
R0_center = 4000;           % Slant range center (m)
PRF = 300;                  % Pulse Repetition Frequency (Hz)
PRT = 1 / PRF;

% Along-track baseline between Receiver 1 and Receiver 2
B_at = 0.2;                 % Baseline distance (0.2 m for unambiguous speed ~ 21 m/s)
tau_lag = B_at / v;         % Time delay between physical apertures (s)

%% 2. Target Scene (Stationary Points + Moving Vehicles)
% Format: [x0, y0, reflectivity, vx (azimuth vel), vy (radial vel)]
scene_targets = [
    % Stationary Reference Scatterers
       0,    sqrt(R0_center^2 - H^2),        1.0,  0.0,   0.0;
     -40,    sqrt(R0_center^2 - H^2) - 30,   0.8,  0.0,   0.0;
      40,    sqrt(R0_center^2 - H^2) + 30,   0.8,  0.0,   0.0;
    % Moving Ground Target (Radial velocity vr = -12.0 m/s)
       0,    sqrt(R0_center^2 - H^2) + 10,   1.2,  0.0, -12.0
];
N_targets = size(scene_targets, 1);

%% 3. Time Axes
Ta = 1.2;                           
t_eta = -Ta/2 : PRT : Ta/2;          
Na = length(t_eta);

R_min = sqrt(min(scene_targets(:,2)).^2 + H^2) - 100;
R_max = sqrt(max(scene_targets(:,2)).^2 + H^2) + 100;
t_tau = (2*R_min/c - Tp/2) : 1/fs : (2*R_max/c + Tp/2);
Nr = length(t_tau);
range_axis = (c * t_tau) / 2;
azimuth_axis = v * t_eta;

%% 4. Two-Channel (ATI) Raw Echo Generation
raw_ch1 = zeros(Na, Nr);
raw_ch2 = zeros(Na, Nr);

for p = 1:Na
    eta = t_eta(p);
    x_plat1 = v * eta;
    x_plat2 = v * (eta - tau_lag); % Receiver 2 delayed along flight track
    
    pulse1 = zeros(1, Nr);
    pulse2 = zeros(1, Nr);
    
    for k = 1:N_targets
        % Update target position based on velocity
        x_tgt = scene_targets(k, 1) + scene_targets(k, 4) * eta;
        y_tgt = scene_targets(k, 2) + scene_targets(k, 5) * eta;
        sigma = scene_targets(k, 3);
        
        % Channel 1 Two-Way Range
        R1 = sqrt((x_plat1 - x_tgt)^2 + y_tgt^2 + H^2);
        tau1 = 2 * R1 / c;
        t_diff1 = t_tau - tau1;
        rect1 = abs(t_diff1) <= (Tp/2);
        pulse1 = pulse1 + sigma * rect1 .* exp(1j * (-2*pi*fc*tau1 + pi*Kr*(t_diff1.^2)));
        
        % Channel 2 Two-Way Range
        R2 = sqrt((x_plat2 - x_tgt)^2 + y_tgt^2 + H^2);
        tau2 = 2 * R2 / c;
        t_diff2 = t_tau - tau2;
        rect2 = abs(t_diff2) <= (Tp/2);
        pulse2 = pulse2 + sigma * rect2 .* exp(1j * (-2*pi*fc*tau2 + pi*Kr*(t_diff2.^2)));
    end
    raw_ch1(p, :) = pulse1;
    raw_ch2(p, :) = pulse2;
end

% Add AWGN Noise (SNR = 25 dB)
snr_db = 25;
add_noise = @(S) S + sqrt((mean(abs(S(:)).^2)/(10^(snr_db/10)))/2) * (randn(size(S)) + 1j*randn(size(S)));
raw_ch1 = add_noise(raw_ch1);
raw_ch2 = add_noise(raw_ch2);

%% 5. Range & Azimuth Compression (Both Channels)
tau_ref = -Tp/2 : 1/fs : Tp/2;
s_ref = exp(1j * pi * Kr * tau_ref.^2);
sh = round((length(tau_ref) - 1) / 2);
N_fft_r = 2^nextpow2(Nr + length(tau_ref) - 1);
H_range = fft(conj(s_ref), N_fft_r);

N_fft_a = 2^nextpow2(Na);
f_eta = (-N_fft_a/2 : N_fft_a/2-1).' * PRF / N_fft_a;

% --- Channel 1 Processing ---
rc_ch1 = zeros(Na, Nr);
for p = 1:Na
    S1 = fft(raw_ch1(p, :), N_fft_r);
    c1 = ifft(S1 .* H_range);
    rc_ch1(p, :) = c1(1+sh : Nr+sh);
end

RD1 = fftshift(fft(rc_ch1, N_fft_a, 1), 1);
az_comp1 = zeros(N_fft_a, Nr);
for r_idx = 1:Nr
    Ka = 2 * v^2 / (lambda * range_axis(r_idx));
    H_az = exp(-1j * pi * (f_eta.^2) / Ka);
    az_comp1(:, r_idx) = ifft(ifftshift(RD1(:, r_idx) .* H_az));
end
img_ch1 = az_comp1(1:Na, :);

% --- Channel 2 Processing ---
rc_ch2 = zeros(Na, Nr);
for p = 1:Na
    S2 = fft(raw_ch2(p, :), N_fft_r);
    c2 = ifft(S2 .* H_range);
    rc_ch2(p, :) = c2(1+sh : Nr+sh);
end

RD2 = fftshift(fft(rc_ch2, N_fft_a, 1), 1);
az_comp2 = zeros(N_fft_a, Nr);
for r_idx = 1:Nr
    Ka = 2 * v^2 / (lambda * range_axis(r_idx));
    H_az = exp(-1j * pi * (f_eta.^2) / Ka);
    az_comp2(:, r_idx) = ifft(ifftshift(RD2(:, r_idx) .* H_az));
end
img_ch2 = az_comp2(1:Na, :);

%% 6. Along-Track Interferometric (ATI) Phase & Velocity Extraction
% Conjugate cross-multiplication
ATI_interferogram = img_ch1 .* conj(img_ch2);
ATI_phase = angle(ATI_interferogram);

% Stationary clutter cancellation threshold
ati_mag = abs(ATI_interferogram);
clutter_threshold = 0.25 * max(ati_mag(:));
moving_target_mask = (ati_mag > clutter_threshold) & (abs(ATI_phase) > 0.05);

% Estimated Radial Velocity from ATI phase:
% phi_ati = (4 * pi / lambda) * (B_at / (2 * v)) * v_r
% => v_r = phi_ati * lambda * v / (2 * pi * B_at)
estimated_vr = (ATI_phase * lambda * v) / (2 * pi * B_at);

%% 7. Visualization
figure('Color', 'w', 'Position', [100, 100, 1100, 700]);

subplot(2, 2, 1);
imagesc(range_axis, azimuth_axis, 20*log10(abs(img_ch1)/max(abs(img_ch1(:)))), [-30 0]);
colormap(gca, 'jet'); colorbar;
title('1. Channel 1 SAR Image (Moving Target Defocused/Shifted)');
xlabel('Slant Range (m)'); ylabel('Azimuth (m)'); axis tight;

subplot(2, 2, 2);
imagesc(range_axis, azimuth_axis, ATI_phase, [-pi pi]);
colormap(gca, 'hsv'); colorbar;
title('2. ATI Interferometric Phase Map (rad)');
xlabel('Slant Range (m)'); ylabel('Azimuth (m)'); axis tight;

subplot(2, 2, 3);
imagesc(range_axis, azimuth_axis, moving_target_mask);
colormap(gca, 'gray'); colorbar;
title('3. Clutter-Suppressed Moving Target Detection Mask');
xlabel('Slant Range (m)'); ylabel('Azimuth (m)'); axis tight;

subplot(2, 2, 4);
imagesc(range_axis, azimuth_axis, estimated_vr .* moving_target_mask, [-15 15]);
colormap(gca, 'jet'); colorbar;
title('4. Extracted Radial Velocity Map v_r (m/s)');
xlabel('Slant Range (m)'); ylabel('Azimuth (m)'); axis tight;

[~, peak_idx] = max(ati_mag(:) .* moving_target_mask(:));
extracted_vr = estimated_vr(peak_idx);
fprintf('Actual Moving Target v_r:    %.2f m/s\n', scene_targets(4, 5));
fprintf('Estimated ATI Peak v_r:      %.2f m/s\n', extracted_vr);