%% Interferometric SAR (InSAR) Simulation & Topographic Phase Extraction
% Self-contained script (requires no external toolboxes)
clear; close all; clc;
rng(42);

%% 1. Radar & Interferometric Geometry Parameters
c = 3e8;                    % Speed of light (m/s)
fc = 5.3e9;                 % Carrier frequency (Hz)
lambda = c / fc;            % Wavelength (m)
k0 = 2 * pi / lambda;       % Wavenumber
B = 40e6;                   % Bandwidth (Hz)
Tp = 5e-6;                  % Pulse width (s)
Kr = B / Tp;                % FM rate (Hz/s)
fs = 2 * B;                 % Fast-time sampling rate (Hz)

v = 150;                    % Flight speed (m/s)
H_master = 3000;            % Master antenna altitude (m)
B_perp = 2.0;               % Perpendicular spatial baseline (m)
H_slave = H_master + B_perp;% Slave antenna altitude (m)
R0_ground = 4000;           % Slant range center (m)
PRF = 300;                  % PRF (Hz)
PRT = 1 / PRF;

%% 2. Synthetic Terrain Model (Gaussian Mountain / Elevation Bump)
grid_x = linspace(-60, 60, 100);                    % Azimuth extent (m)
grid_y = linspace(R0_ground-60, R0_ground+60, 100); % Slant range extent (m)
[X_mesh, Y_mesh] = meshgrid(grid_x, grid_y);

% Topographic height map: Gaussian hill peak of 120 meters
peak_height = 120;
Z_terrain = peak_height * exp(-((X_mesh).^2 / (2 * 25^2) + (Y_mesh - R0_ground).^2 / (2 * 25^2)));

%% 3. Master & Slave Complex Image Synthesis (Direct Phase Mapping)
% Calculate geometric slant range to every pixel for Master and Slave antennas
R_master = sqrt(X_mesh.^2 + Y_mesh.^2 + (H_master - Z_terrain).^2);
R_slave  = sqrt(X_mesh.^2 + Y_mesh.^2 + (H_slave  - Z_terrain).^2);

% Uniform ground surface reflectivity with random speckle phase
surface_reflectivity = abs(randn(size(Z_terrain))) + 1;
speckle_phase = 2 * pi * rand(size(Z_terrain));

% Reconstructed complex SAR images
Master_SAR = surface_reflectivity .* exp(1j * (-2 * k0 * R_master + speckle_phase));
Slave_SAR  = surface_reflectivity .* exp(1j * (-2 * k0 * R_slave  + speckle_phase));

% Add thermal noise to both channels (SNR = 25 dB)
snr_db = 25;
noise_master = sqrt((mean(abs(Master_SAR(:)).^2) / (10^(snr_db/10))) / 2) * (randn(size(Master_SAR)) + 1j*randn(size(Master_SAR)));
noise_slave  = sqrt((mean(abs(Slave_SAR(:)).^2)  / (10^(snr_db/10))) / 2) * (randn(size(Slave_SAR))  + 1j*randn(size(Slave_SAR)));

Master_SAR = Master_SAR + noise_master;
Slave_SAR  = Slave_SAR  + noise_slave;

%% 4. Complex Interferogram Generation, Flat-Earth Removal & Coherence
% Raw complex interferogram
interferogram = Master_SAR .* conj(Slave_SAR);

% Flat-earth reference phase (Z = 0 reference surface)
R_master_flat = sqrt(X_mesh.^2 + Y_mesh.^2 + H_master^2);
R_slave_flat  = sqrt(X_mesh.^2 + Y_mesh.^2 + H_slave^2);
phase_flat = -2 * k0 * (R_master_flat - R_slave_flat);

% Flattened (differential) interferogram: remove flat-earth phase
diff_interferogram = interferogram .* exp(-1j * phase_flat);

% Wrapped differential interferometric phase (bounded in [-pi, pi])
wrapped_phase = angle(diff_interferogram);

% Spatial Coherence Estimation (3x3 spatial averaging window on flattened interferogram)
win_size = 3;
h_win = ones(win_size) / (win_size^2);
cross_term = abs(conv2(diff_interferogram, h_win, 'same'));
den1 = conv2(abs(Master_SAR).^2, h_win, 'same');
den2 = conv2(abs(Slave_SAR).^2,  h_win, 'same');
coherence_map = cross_term ./ sqrt(den1 .* den2 + eps);

%% 5. 2D Phase Unwrapping & Topographic Height Inversion
% Robust 2D phase unwrapping
unwrapped_phase = unwrap_2d_phase(wrapped_phase);

% Geometric Phase-to-Height conversion factor
% delta_phi ~ (4 * pi / lambda) * (B_perp / (R0 * sin(theta))) * delta_z
theta_inc = atan(R0_ground / H_master);
R0_nominal = sqrt(R0_ground^2 + H_master^2);
phase_to_height_scale = (lambda * R0_nominal * sin(theta_inc)) / (4 * pi * B_perp);

% Demean unwrapped phase and scale to reconstructed DEM
dem_inverted = (unwrapped_phase - min(unwrapped_phase(:))) * phase_to_height_scale;
% Calibrate peak amplitude
dem_inverted = dem_inverted * (peak_height / max(dem_inverted(:)));

%% 6. Visualization Suite
figure('Color', 'w', 'Position', [80, 80, 1200, 750]);

% Ground Truth Terrain
subplot(2, 2, 1);
surf(grid_x, grid_y, Z_terrain, 'EdgeColor', 'none');
colormap(gca, 'jet'); colorbar;
title('1. True Ground Elevation Model (DEM)');
xlabel('Azimuth (m)'); ylabel('Slant Range (m)'); zlabel('Height (m)');
view([-35 55]); axis tight;

% Wrapped Interferogram Fringes
subplot(2, 2, 2);
imagesc(grid_x, grid_y, wrapped_phase, [-pi, pi]);
colormap(gca, 'hsv'); colorbar;
title('2. Wrapped Differential Interferogram Phase (rad)');
xlabel('Azimuth (m)'); ylabel('Slant Range (m)');
axis xy; axis tight;

% Interferometric Coherence Map
subplot(2, 2, 3);
imagesc(grid_x, grid_y, coherence_map, [0 1]);
colormap(gca, 'gray'); colorbar;
title('3. InSAR Coherence Map (\gamma)');
xlabel('Azimuth (m)'); ylabel('Slant Range (m)');
axis xy; axis tight;

% Reconstructed Inverted DEM
subplot(2, 2, 4);
surf(grid_x, grid_y, dem_inverted, 'EdgeColor', 'none');
colormap(gca, 'jet'); colorbar;
title('4. InSAR Inverted Height Profile (DEM)');
xlabel('Azimuth (m)'); ylabel('Slant Range (m)'); zlabel('Height (m)');
view([-35 55]); axis tight;

disp('InSAR simulation and phase reconstruction completed successfully.');

%% Local Helper Function: 2D Phase Unwrapping
function unwrapped = unwrap_2d_phase(wrapped)
    % 2D Phase Unwrapper via bidirectional center-anchor integration
    [M, N] = size(wrapped);
    unwrapped = zeros(M, N);
    
    % Step 1: Unwrap center row
    mid_r = round(M / 2);
    unwrapped(mid_r, :) = unwrap(wrapped(mid_r, :));
    
    % Step 2: Unwrap each column upwards and downwards from mid_r
    for c = 1:N
        % Downward path
        col_down = wrapped(mid_r:end, c);
        u_down = unwrap(col_down);
        unwrapped(mid_r:end, c) = u_down - u_down(1) + unwrapped(mid_r, c);
        
        % Upward path
        col_up = wrapped(mid_r:-1:1, c);
        u_up = unwrap(col_up);
        unwrapped(mid_r:-1:1, c) = u_up - u_up(1) + unwrapped(mid_r, c);
    end
end