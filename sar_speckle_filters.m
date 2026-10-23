%% SAR Speckle Filtering & Contrast Enhancement Suite
% Self-contained script: Implements Boxcar, Lee, and Frost filters
clear; close all; clc;

%% 1. Generate Synthetic Speckled SAR Scene
N = 256;
scene_clean = ones(N, N) * 0.2; % Homogeneous background

% Add distinct geometric features
scene_clean(40:100, 40:100) = 1.0;          % Bright urban block
scene_clean(150:210, 150:210) = 0.6;        % Agricultural field
scene_clean(120:136, 30:226) = 0.05;        % Dark river channel

% Add point targets (strong discrete corner reflectors)
scene_clean(70, 180) = 3.5;
scene_clean(180, 70) = 4.0;

% Multiplicative Rayleigh / Gamma Speckle Noise (L-look SAR model)
L = 1; % 1-Look SAR (Single look complex intensity)
rng(42);
speckle_noise = sum(-log(rand(N, N, L)), 3) / L;
img_speckled = scene_clean .* speckle_noise;

%% 2. Spatial Boxcar / Mean Filter
win = 5;
pad = floor(win / 2);
kernel_mean = ones(win, win) / (win^2);

% Toolbox-free symmetric padding
img_padded = pad_symmetric_native(img_speckled, pad);
img_boxcar = conv2(img_padded, kernel_mean, 'valid');

%% 3. Adaptive Lee Filter (Standard Intensity LMMSE)
% Local statistics computation
local_mean     = conv2(img_padded, kernel_mean, 'valid');
local_sqr_mean = conv2(pad_symmetric_native(img_speckled.^2, pad), kernel_mean, 'valid');
local_var = max(0, local_sqr_mean - local_mean.^2);

% Theoretical noise variance for L-look intensity speckle: sigma_n^2 = 1 / L
noise_var = 1 / L;

% Standard Intensity Lee weighting factor: W = max(0, (var - mean^2 * noise_var) / var)
weight_lee = max(0, (local_var - (local_mean.^2 * noise_var)) ./ (local_var + eps));
weight_lee = min(1, weight_lee); % Constrain bound: 0 <= W <= 1
img_lee = local_mean + weight_lee .* (img_speckled - local_mean);

%% 4. Adaptive Frost Filter (Exponential Distance-Decay Kernel)
a = 2.0; % Damping factor
img_frost = zeros(N, N);
[x_k, y_k] = meshgrid(-pad:pad, -pad:pad);
dist_matrix = sqrt(x_k.^2 + y_k.^2);

for r = 1:N
    for c = 1:N
        % Extract local neighborhood window
        sub_win = img_padded(r : r + win - 1, c : c + win - 1);
        
        m_val = mean(sub_win(:));
        s_val = std(sub_win(:));
        Ci = s_val / (m_val + eps); % Local coefficient of variation
        
        % Frost exponential weight kernel
        W_frost = exp(-a * (Ci^2) * dist_matrix);
        W_frost = W_frost / sum(W_frost(:));
        
        img_frost(r, c) = sum(sum(sub_win .* W_frost));
    end
end

%% 5. Quantitative Metric Evaluation (Equivalent Number of Looks)
roi_mask = false(N, N);
roi_mask(160:200, 160:200) = true;
calc_enl = @(x) (mean(x(roi_mask))^2) / var(x(roi_mask));

enl_raw    = calc_enl(img_speckled);
enl_boxcar = calc_enl(img_boxcar);
enl_lee    = calc_enl(img_lee);
enl_frost  = calc_enl(img_frost);

fprintf('\n================ SPECKLE FILTERING PERFORMANCE REPORT ================\n');
fprintf(' Image State          | Equivalent Number of Looks (ENL) | Smoothing Gain\n');
fprintf('----------------------+-----------------------------------+----------------\n');
fprintf(' Raw Speckled Image   | %32.2f | Baseline (1.0x)\n', enl_raw);
fprintf(' Boxcar Filter (5x5)  | %32.2f | %11.1fx\n', enl_boxcar, enl_boxcar / enl_raw);
fprintf(' Adaptive Lee Filter  | %32.2f | %11.1fx\n', enl_lee, enl_lee / enl_raw);
fprintf(' Adaptive Frost Filter| %32.2f | %11.1fx\n', enl_frost, enl_frost / enl_raw);
fprintf('======================================================================\n\n');

%% 6. Visualization
figure('Color', 'w', 'Position', [80, 80, 1200, 750]);
subplot(2, 2, 1);
imagesc(img_speckled, [0 2]); colormap(gca, 'gray'); colorbar;
title(sprintf('1. Raw Speckled Image (ENL = %.2f)', enl_raw));
axis image off;

subplot(2, 2, 2);
imagesc(img_boxcar, [0 2]); colormap(gca, 'gray'); colorbar;
title(sprintf('2. Boxcar 5x5 Mean Filter (ENL = %.2f)', enl_boxcar));
axis image off;

subplot(2, 2, 3);
imagesc(img_lee, [0 2]); colormap(gca, 'gray'); colorbar;
title(sprintf('3. Adaptive Lee Filter (ENL = %.2f)', enl_lee));
axis image off;

subplot(2, 2, 4);
imagesc(img_frost, [0 2]); colormap(gca, 'gray'); colorbar;
title(sprintf('4. Adaptive Frost Filter (ENL = %.2f)', enl_frost));
axis image off;

disp('Speckle filtering suite execution complete.');

%% Local Helper Function: Symmetric Padding (Toolbox-Free)
function out = pad_symmetric_native(img, pad)
    [rows, cols] = size(img);
    out = zeros(rows + 2*pad, cols + 2*pad);
    
    % Inner content
    out(pad+1:pad+rows, pad+1:pad+cols) = img;
    
    % Top and bottom borders
    out(1:pad, pad+1:pad+cols) = flipud(img(1:pad, :));
    out(pad+rows+1:end, pad+1:pad+cols) = flipud(img(end-pad+1:end, :));
    
    % Left and right borders (including corners)
    out(:, 1:pad) = fliplr(out(:, pad+1:2*pad));
    out(:, pad+cols+1:end) = fliplr(out(:, pad+cols-pad+1:pad+cols));
end