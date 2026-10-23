%% Synthetic Aperture Radar (SAR) Time-Domain Backprojection Processor (BPA)
% Self-contained script (requires no external toolboxes)
clear; close all; clc;

%% 1. Radar & System Setup
c = 3e8;                    % Speed of light (m/s)
fc = 5.3e9;                 % Carrier frequency (Hz)
lambda = c / fc;            % Wavelength (m)
k0 = 2 * pi / lambda;       % Wavenumber
B = 40e6;                   % Chirp Bandwidth (Hz)
Tp = 4e-6;                  % Pulse Width (s)
Kr = B / Tp;                % FM rate (Hz/s)
fs = 2 * B;                 % Fast-time sampling rate (Hz)

v = 100;                    % Flight speed (m/s)
H = 2000;                   % Flight Altitude (m)
R0 = 3000;                  % Range to ground scene center (m)
PRF = 250;                  % PRF (Hz)
PRT = 1 / PRF;

%% 2. Point Scatterer Ground Scene
targets = [
      0, sqrt(R0^2 - H^2),      1.0;
    -20, sqrt(R0^2 - H^2) - 20, 0.8;
     20, sqrt(R0^2 - H^2) + 20, 0.8
];
N_targets = size(targets, 1);

%% 3. Slow-Time Trajectory & Fast-Time Vector
Ta = 1.0;                           % Synthetic aperture integration time (s)
t_eta = -Ta/2 : PRT : Ta/2;          % Slow-time samples
Na = length(t_eta);

% Radar flight coordinates: Along-track flight path
radar_x = v * t_eta;
radar_y = zeros(1, Na);
radar_z = H * ones(1, Na);

R_min = sqrt(min(targets(:,2))^2 + H^2) - 80;
R_max = sqrt(max(targets(:,2))^2 + H^2) + 80;
t_tau = (2*R_min/c - Tp/2) : 1/fs : (2*R_max/c + Tp/2);
Nr = length(t_tau);

%% 4. Raw Echo Collection
raw_echo = zeros(Na, Nr);
for p = 1:Na
    pulse = zeros(1, Nr);
    for k = 1:N_targets
        R_inst = sqrt((radar_x(p) - targets(k,1))^2 + (radar_y(p) - targets(k,2))^2 + radar_z(p)^2);
        tau_delay = 2 * R_inst / c;
        tau_diff = t_tau - tau_delay;
        rect_pulse = abs(tau_diff) <= (Tp/2);
        phase = -2*pi*fc*tau_delay + pi*Kr*(tau_diff.^2);
        pulse = pulse + targets(k,3) * rect_pulse .* exp(1j * phase);
    end
    raw_echo(p, :) = pulse;
end

%% 5. Fast-Time Range Compression
tau_ref = -Tp/2 : 1/fs : Tp/2;
s_ref = exp(1j * pi * Kr * tau_ref.^2);
sh = round((length(tau_ref) - 1) / 2);
N_fft_r = 2^nextpow2(Nr + length(tau_ref) - 1);
H_range = fft(conj(s_ref), N_fft_r);

rc_data = zeros(Na, Nr);
for p = 1:Na
    S_pulse = fft(raw_echo(p, :), N_fft_r);
    comp = ifft(S_pulse .* H_range);
    rc_data(p, :) = comp(1+sh : Nr+sh);
end

%% 6. Time-Domain Backprojection Algorithm (Vectorized Mesh Integration)
% Define 2D Ground Reconstruction Grid
grid_x = linspace(-40, 40, 150);                     % Azimuth grid (m)
grid_y = linspace(sqrt(R0^2-H^2)-40, sqrt(R0^2-H^2)+40, 150); % Ground range grid (m)
[X_mesh, Y_mesh] = meshgrid(grid_x, grid_y);
bpa_image = zeros(size(X_mesh));

dt = 1 / fs;
t_start = t_tau(1);

disp('Executing Time-Domain Backprojection Integration...');
for p = 1:Na
    R_pix = sqrt((v*t_eta(p) - X_mesh).^2 + Y_mesh.^2 + H^2);
    bin = (2*R_pix/c - t_start)/dt + 1;
    lo = floor(bin);  fr = bin - lo;
    ok = (lo >= 1) & (lo+1 <= Nr);
    lo(~ok) = 1;
    pulse_rc = rc_data(p, :);
    val = (1-fr).*pulse_rc(lo) + fr.*pulse_rc(lo+1);
    bpa_image = bpa_image + ok .* val .* exp(1j*2*k0*R_pix);
end

%% 7. Visualization
figure('Color', 'w', 'Position', [150, 150, 650, 550]);
bpa_image_db = 20 * log10(abs(bpa_image) / max(abs(bpa_image(:))));
imagesc(grid_x, grid_y, bpa_image_db, [-35, 0]);
colormap(gca, 'hot'); colorbar;
title('Time-Domain Backprojection SAR Image (dB)');
xlabel('Azimuth (m)'); ylabel('Ground Range (m)');
axis xy; axis tight;

disp('Backprojection reconstruction complete!');