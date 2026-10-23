%% Synthetic Aperture Radar (SAR) Simulation and Processing Pipeline
% Model: Stripmap SAR Airborne / Satellite Geometry
% Algorithm: Range-Doppler Algorithm (RDA) with Matched Filtering
clear; close all; clc;

%% 1. Radar System & Platform Parameters
c = 3e8;                    % Speed of light (m/s)
fc = 5.3e9;                 % Carrier frequency (C-band, Hz)
lambda = c / fc;            % Wavelength (m)
B = 30e6;                   % Chirp bandwidth (Hz)
Tp = 5e-6;                  % Pulse duration (s)
K_r = B / Tp;               % Chirp rate (Hz/s)
fs = 2.4 * B;               % Fast-time (range) sampling frequency (Hz)

v = 150;                    % Platform velocity (m/s)
H = 3000;                   % Platform altitude (m)
R0_center = 4000;           % Slant range to scene center (m)
PRF = 300;                  % Pulse Repetition Frequency (Hz)
PRT = 1 / PRF;              % Pulse Repetition Interval (s)

%% 2. Target Scene Definition (Point Scatterers)
% [x (azimuth/along-track), y (ground range/cross-track), reflectivity]
targets = [
       0,    sqrt(R0_center^2 - H^2),        1.0;
     -40,    sqrt(R0_center^2 - H^2) - 30,   0.8;
      40,    sqrt(R0_center^2 - H^2) + 30,   0.9;
     -30,    sqrt(R0_center^2 - H^2) + 50,   0.7;
      30,    sqrt(R0_center^2 - H^2) - 50,   0.6
];
N_targets = size(targets, 1);

%% 3. Time Axes & Grid Initialization
% Slow-time (Azimuth)
Ta = 1.2;                           % Total synthetic aperture duration (s)
t_eta = -Ta/2 : PRT : Ta/2;          % Slow-time vector
Na = length(t_eta);                 % Number of azimuth pulses

% Fast-time (Range)
R_min = sqrt(min(targets(:,2)).^2 + H^2) - 100;
R_max = sqrt(max(targets(:,2)).^2 + H^2) + 100;
t_tau_min = 2 * R_min / c - Tp/2;
t_tau_max = 2 * R_max / c + Tp/2;
t_tau = t_tau_min : 1/fs : t_tau_max; % Fast-time vector
Nr = length(t_tau);                  % Number of range samples

fprintf('Grid Size: %d Azimuth Pulses x %d Range Samples\n', Na, Nr);

%% 4. Raw Baseband Echo Generation (Fast-Time / Slow-Time Matrix)
raw_data = zeros(Na, Nr);
for p = 1:Na
    eta = t_eta(p);
    x_plat = v * eta;
    y_plat = 0;
    z_plat = H;
    
    pulse = zeros(1, Nr);
    for k = 1:N_targets
        x_tgt = targets(k, 1);
        y_tgt = targets(k, 2);
        sigma = targets(k, 3);
        
        % Instantaneous slant range
        R_inst = sqrt((x_plat - x_tgt)^2 + y_tgt^2 + z_plat^2);
        tau_delay = 2 * R_inst / c;
        
        % Fast-time window
        tau_diff = t_tau - tau_delay;
        rect_pulse = abs(tau_diff) <= (Tp / 2);
        
        % Phase modulation: Range chirp + Azimuth Doppler phase
        phase = -2*pi*fc*tau_delay + pi*K_r*(tau_diff.^2);
        pulse = pulse + sigma * rect_pulse .* exp(1j * phase);
    end
    % Diffuse ground clutter / backscatter term
    pulse = pulse + 0.05 * (randn(1, Nr) + 1j * randn(1, Nr)) / sqrt(2);
    raw_data(p, :) = pulse;
end

% Add additive white Gaussian noise manually (SNR = 20 dB, no toolbox needed)
target_snr_db = 20;
signal_pwr = mean(abs(raw_data(:)).^2);
noise_pwr = signal_pwr / (10^(target_snr_db / 10));
noise = sqrt(noise_pwr / 2) * (randn(size(raw_data)) + 1j * randn(size(raw_data)));
raw_data = raw_data + noise;

%% 5. Range Compression (Fast-Time Matched Filtering)
% Reference chirp in fast-time
tau_ref = -Tp/2 : 1/fs : Tp/2;
s_ref = exp(1j * pi * K_r * tau_ref.^2);
sh = round((length(tau_ref) - 1) / 2);   % reference-length shift
N_fft_r = 2^nextpow2(Nr + length(tau_ref) - 1);

H_range = fft(conj(s_ref), N_fft_r);
range_compressed = zeros(Na, Nr);

for p = 1:Na
    S_range = fft(raw_data(p, :), N_fft_r);
    comp = ifft(S_range .* H_range);
    range_compressed(p, :) = comp(1+sh : Nr+sh);
end

%% 6. Azimuth Compression (Range-Doppler Algorithm)
% Transform to Range-Doppler domain (Azimuth FFT)
N_fft_a = 2^nextpow2(Na);
RD_data = fftshift(fft(range_compressed, N_fft_a, 1), 1);

% Doppler Frequency Axis
f_eta = (-N_fft_a/2 : N_fft_a/2-1).' * PRF / N_fft_a;

% Azimuth Matched Filter for each range bin
azimuth_compressed = zeros(N_fft_a, Nr);
for r_idx = 1:Nr
    R_current = (c * t_tau(r_idx)) / 2;
    % Azimuth FM rate (Ka)
    Ka = 2 * v^2 / (lambda * R_current);
    
    % Azimuth reference frequency response
    H_az = exp(-1j * pi * (f_eta.^2) / Ka);
    
    % Matched filtering in Doppler domain
    azimuth_compressed(:, r_idx) = ifft(ifftshift(RD_data(:, r_idx) .* H_az));
end

% Truncate to original aperture size
final_image = azimuth_compressed(1:Na, :);

%% 7. Visualization
figure('Color', 'w', 'Position', [100, 100, 1200, 700]);

subplot(2, 2, 1);
imagesc(t_tau * 1e6, t_eta, abs(raw_data));
colormap(gca, 'parula'); colorbar;
title('1. Raw Demodulated Baseband Data');
xlabel('Fast-time \tau (\mus)'); ylabel('Slow-time \eta (s)');
axis tight;

subplot(2, 2, 2);
imagesc(t_tau * 1e6, t_eta, abs(range_compressed));
colormap(gca, 'jet'); colorbar;
title('2. Range Compressed Data (Fast-Time Matched)');
xlabel('Fast-time \tau (\mus)'); ylabel('Slow-time \eta (s)');
axis tight;

subplot(2, 2, 3);
imagesc(t_tau * 1e6, f_eta(1:Na), abs(RD_data(1:Na, :)));
colormap(gca, 'turbo'); colorbar;
title('3. Range-Doppler Domain Spectrum');
xlabel('Fast-time \tau (\mus)'); ylabel('Doppler Frequency (Hz)');
axis tight;

subplot(2, 2, 4);
range_axis = (c * t_tau) / 2;
azimuth_axis = (v * t_eta);
img_mag_db = 20 * log10(abs(final_image) / max(abs(final_image(:))));
imagesc(range_axis, azimuth_axis, img_mag_db, [-35, 0]);
colormap(gca, 'hot'); colorbar;
title('4. Final Reconstructed SAR Image: Point/Diffuse (dB)');
xlabel('Slant Range (m)'); ylabel('Azimuth (m)');
%% --- 1D Point Spread Function (PSF) Profile Extraction ---
% Find the peak target pixel coordinates
[~, max_idx] = max(abs(final_image(:)));
[target_az_idx, target_rg_idx] = ind2sub(size(final_image), max_idx);

% Extract 1D cuts through the target peak
range_cut = abs(final_image(target_az_idx, :));
azimuth_cut = abs(final_image(:, target_rg_idx).');

% Convert to normalized dB
range_profile_db = 20 * log10(range_cut / max(range_cut));
azimuth_profile_db = 20 * log10(azimuth_cut / max(azimuth_cut));

% Toolbox-free peak detection logic (Lines 161+)
rg_diff = sign(diff(range_profile_db));
rg_peaks = find(rg_diff(1:end-1) > 0 & rg_diff(2:end) < 0) + 1;
rg_locs = find(rg_diff(1:end-1) > 0 & rg_diff(2:end) < 0) + 1;
rg_pks = range_profile_db(rg_locs);

% Sort peaks descending to find the mainlobe (1st) and highest sidelobe (2nd)
sorted_rg_pks = sort(rg_pks, 'descend');
if length(sorted_rg_pks) >= 2
    rg_pslr = sorted_rg_pks(2); 
else
    rg_pslr = NaN;
end

% -- Azimuth PSLR --
az_diff = sign(diff(azimuth_profile_db));
az_locs = find(az_diff(1:end-1) > 0 & az_diff(2:end) < 0) + 1;
az_pks = azimuth_profile_db(az_locs);

sorted_az_pks = sort(az_pks, 'descend');
if length(sorted_az_pks) >= 2
    az_pslr = sorted_az_pks(2);
else
    az_pslr = NaN;
end
%% Phase 6: Extended Target & Distributed Ground Clutter Simulation
disp('Running Phase 6: Extended Target & Ground Clutter Simulation...');

% 1. Define an Extended Distributed Target (Array of Scatterers)
% Models a vehicle hull with strong corner reflectors and turret
x_center = 0;
y_center = sqrt(R0_center^2 - H^2);

extended_targets = [
    % [x_offset, y_offset, reflectivity]
    x_center - 15, y_center - 5,  1.2;  % Front Left
    x_center + 15, y_center - 5,  1.2;  % Front Right
    x_center - 15, y_center + 5,  1.0;  % Rear Left
    x_center + 15, y_center + 5,  1.0;  % Rear Right
    x_center,      y_center,      2.0;  % Turret (Strong Reflector)
    x_center,      y_center + 8,  0.8;  % Hull body
    x_center,      y_center - 8,  0.8   % Barrel
    ];

% 2. Generate Random Distributed Ground Clutter (Grass/Soil Model)
N_clutter = 80;                         % Number of clutter scatterers
clutter_x_span = 120;                   % Clutter azimuth span (m)
clutter_y_span = 120;                   % Clutter ground range span (m)

rng(42); % Set seed for repeatable random clutter pattern
clutter_x = x_center + (rand(N_clutter, 1) - 0.5) * clutter_x_span;
clutter_y = y_center + (rand(N_clutter, 1) - 0.5) * clutter_y_span;
clutter_rcs = 0.05 + 0.1 * rand(N_clutter, 1); % Weak diffuse backscatter

all_scatterers = [extended_targets; [clutter_x, clutter_y, clutter_rcs]];
N_all = size(all_scatterers, 1);

% 3. Echo Generation for Extended Scene
raw_clutter_data = zeros(Na, Nr);
for p = 1:Na
    eta = t_eta(p);
    x_plat = v * eta;
    pulse_echo = zeros(1, Nr);

    for k = 1:N_all
        x_tgt = all_scatterers(k, 1);
        y_tgt = all_scatterers(k, 2);
        sigma = all_scatterers(k, 3);

        R_inst = sqrt((x_plat - x_tgt)^2 + y_tgt^2 + H^2);
        tau_delay = 2 * R_inst / c;

        tau_diff = t_tau - tau_delay;
        rect_pulse = abs(tau_diff) <= (Tp / 2);

        phase = -2*pi*fc*tau_delay + pi*K_r*(tau_diff.^2);
        pulse_echo = pulse_echo + sigma * rect_pulse .* exp(1j * phase);
    end
    raw_clutter_data(p, :) = pulse_echo;
end

% Add thermal noise
signal_pwr_clut = mean(abs(raw_clutter_data(:)).^2);
noise_pwr_clut = signal_pwr_clut / (10^(target_snr_db / 10));
raw_clutter_data = raw_clutter_data + sqrt(noise_pwr_clut/2) * (randn(size(raw_clutter_data)) + 1j*randn(size(raw_clutter_data)));

% 4. Focus with Range-Doppler Processor
% Range Compression
range_compressed_clutter = zeros(Na, Nr);
for p = 1:Na
    S_range = fft(raw_clutter_data(p, :), N_fft_r);
    compressed_pulse = ifft(S_range .* H_range);
    range_compressed_clutter(p, :) = compressed_pulse(1+sh : Nr+sh);
end

% Azimuth Compression
RD_clutter = fftshift(fft(range_compressed_clutter, N_fft_a, 1), 1);
azimuth_compressed_clutter = zeros(N_fft_a, Nr);
for r_idx = 1:Nr
    R_current = (c * t_tau(r_idx)) / 2;
    Ka = 2 * v^2 / (lambda * R_current);
    H_az = exp(-1j * pi * (f_eta.^2) / Ka);
    azimuth_compressed_clutter(:, r_idx) = ifft(ifftshift(RD_clutter(:, r_idx) .* H_az));
end
final_clutter_image = azimuth_compressed_clutter(1:Na, :);

% 5. Plot the Reconstructed Extended Target Scene
figure('Color', 'w', 'Position', [200, 200, 900, 600]);
img_clutter_db = 20 * log10(abs(final_clutter_image) / max(abs(final_clutter_image(:))));
imagesc(range_axis, azimuth_axis, img_clutter_db, [-30, 0]);
colormap(gca, 'hot'); colorbar;
title('Phase 6: Reconstructed Extended Target with Ground Clutter (dB)');
xlabel('Slant Range (m)'); ylabel('Azimuth (m)');
axis tight;

% Extract central range and azimuth profiles and convert to dB
center_az_idx = round(size(final_image,1)/2);
center_rg_idx = round(size(final_image,2)/2);

range_profile_db = 20*log10(abs(final_image(center_az_idx,:)) ./ max(abs(final_image(:))));
azimuth_profile_db = 20*log10(abs(final_image(:,center_rg_idx)) ./ max(abs(final_image(:))));
%% Phase 6 - Variation B: Stepped Frequency Waveform Refinement
disp('Running Phase 6 (Variation B): Stepped Frequency Waveform Simulation...');

% 1. Stepped Frequency Waveform Parameters
N_steps = 32;                       % Number of frequency steps in one sequence
delta_f = B / N_steps;              % Frequency step size (Hz)
subpulse_duration = Tp / N_steps;   % Duration of each subpulse (s)
f_steps = fc + (0:N_steps-1) * delta_f; % Stepped carrier frequencies

% 2. Stepped Frequency Echo Matrix Generation
% Matrix dimensions: [Number of Frequency Steps x Number of Azimuth Pulses]
sf_raw_data = zeros(N_steps, Na);

for p = 1:Na
    eta = t_eta(p);
    x_plat = v * eta;

    % Target at scene center
    x_tgt = targets(1, 1);
    y_tgt = targets(1, 2);

    % Range to target at current pulse
    R_inst = sqrt((x_plat - x_tgt)^2 + y_tgt^2 + H^2);

    % Baseband echo for each stepped frequency component
    for n = 1:N_steps
        % Two-way phase for each stepped frequency
        phase_sf = -4 * pi * f_steps(n) * R_inst / c;
        sf_raw_data(n, p) = exp(1j * phase_sf);
    end
end

% Add AWGN noise
sf_sig_pwr = mean(abs(sf_raw_data(:)).^2);
sf_noise_pwr = sf_sig_pwr / (10^(target_snr_db / 10));
sf_raw_data = sf_raw_data + sqrt(sf_noise_pwr/2) * (randn(size(sf_raw_data)) + 1j*randn(size(sf_raw_data)));

% 3. Stepped Frequency Range Compression via IDFT/IFFT
% Synthesizes bandwidth by taking IFFT across frequency steps
sf_range_compressed = ifft(sf_raw_data, N_steps, 1);

% 4. Azimuth Compression via Range-Doppler FFT
sf_RD_data = fftshift(fft(sf_range_compressed, N_fft_a, 2), 2);

sf_azimuth_compressed = zeros(N_steps, N_fft_a);
for step_idx = 1:N_steps
    % Reference range for this step
    Ka_sf = 2 * v^2 / (lambda * R0_center);
    H_az_sf = exp(-1j * pi * (f_eta.^2) / Ka_sf).';
    sf_azimuth_compressed(step_idx, :) = ifft(ifftshift(sf_RD_data(step_idx, :) .* H_az_sf));
end

sf_final_image = sf_azimuth_compressed(:, 1:Na);

% 5. Visualization: Stepped Frequency Focused Target
figure('Color', 'w', 'Position', [250, 250, 1000, 450]);

subplot(1, 2, 1);
imagesc(1:Na, 1:N_steps, abs(sf_raw_data));
colormap(gca, 'parula'); colorbar;
title('1. Stepped Frequency Raw Data (Frequency vs Azimuth)');
xlabel('Azimuth Pulse Index'); ylabel('Frequency Step Index');
axis tight;

subplot(1, 2, 2);
sf_img_db = 20 * log10(abs(sf_final_image) / max(abs(sf_final_image(:))));
imagesc(azimuth_axis, linspace(R_min, R_max, N_steps), sf_img_db, [-30, 0]);
colormap(gca, 'hot'); colorbar;
title('2. Reconstructed Target via Stepped Frequency (dB)');
xlabel('Azimuth (m)'); ylabel('Slant Range (m)');
axis tight;

disp('Project Execution Complete!');
%% Phase 7: Comprehensive Performance Comparison & Metric Benchmarking
disp('Running Phase 7: Performance Benchmarking and Metric Extraction...');

% =========================================================================
% 1. Signal-to-Clutter-plus-Noise Ratio (SCNR) for Extended Target
% =========================================================================
% Create 2D meshgrid to correctly match the 2D image matrix dimensions
[R_grid, Az_grid] = meshgrid(range_axis, azimuth_axis);

% 2D logical mask isolating the center target region vs background clutter
target_region_mask  = (abs(R_grid - R0_center) < 20) & (abs(Az_grid) < 25);
clutter_region_mask = ~target_region_mask;

pwr_target_region  = mean(abs(final_clutter_image(target_region_mask)).^2);
pwr_clutter_region = mean(abs(final_clutter_image(clutter_region_mask)).^2);
SCNR_measured_dB   = 10 * log10(pwr_target_region / pwr_clutter_region);

% =========================================================================
% 2. Stepped Frequency Dynamic Range & Resolution
% =========================================================================
sf_max_val = max(abs(sf_final_image(:)));
sf_noise_floor = mean(abs(sf_final_image(:)));
%% --- Theoretical Performance Calculations ---
c_light = 3e8; % Speed of light (m/s)
theo_range_res = c / (2 * B);
theo_azimuth_res = (c / fc) * R0_center / (2 * (v * abs(t_eta(end) - t_eta(1))));
fprintf(' Total Bandwidth              | %6.2f MHz         | %6.2f MHz (Synthesized)   \n', B/1e6, B/1e6);
fprintf(' Range Resolution (Theoret.)  | %6.3f m           | %6.3f m                   \n', theo_range_res, c/(2*B));
fprintf(' Azimuth Resolution (Theoret.)| %6.3f m           | %6.3f m                   \n', theo_azimuth_res, theo_azimuth_res);
fprintf(' SCNR (Target vs Clutter)     | %6.2f dB          | N/A (Single Point Target) \n', SCNR_measured_dB);
fprintf(' Peak Sidelobe Ratio (Range)  | %6.2f dB          | Sinc Synthesized          \n', rg_pslr);
fprintf(' Peak Sidelobe Ratio (Azimuth)| %6.2f dB          | %6.2f dB (RDA Focused)    \n', az_pslr, az_pslr);
fprintf(' Processing Mode              | Fast-Time Matched  | Inverse DFT / IFFT        \n');
fprintf('===============================================================================\n\n');

% =========================================================================
% 4. Comparative 3D Surface Visualizations
% =========================================================================
figure('Color', 'w', 'Position', [100, 100, 1200, 500]);

% Standard Multi-Point Target Surface
subplot(1, 2, 1);
surf(range_axis, azimuth_axis, img_mag_db, 'EdgeColor', 'none');
colormap(gca, 'jet'); colorbar;
caxis([-35 0]); view([-30 65]);
title('1. Point/Diffuse Scatterers (RDA Surface, dB)');
xlabel('Slant Range (m)'); ylabel('Azimuth (m)'); zlabel('Power (dB)');
axis tight; grid on;

% Extended Target with Clutter Surface
subplot(1, 2, 2);
surf(range_axis, azimuth_axis, img_clutter_db, 'EdgeColor', 'none');
colormap(gca, 'hot'); colorbar;
caxis([-30 0]); view([-30 65]);
title('2. Extended Target in Clutter (Surface, dB)');
xlabel('Slant Range (m)'); ylabel('Azimuth (m)'); zlabel('Power (dB)');
axis tight; grid on;

disp('All phases and benchmarks executed successfully.');