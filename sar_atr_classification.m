%% SAR Automatic Target Recognition (ATR) & CFAR Detection Pipeline
% Self-contained script: Implements 2D CA-CFAR detector & geometric feature extraction
% Requires no external toolboxes (Statistics / Image Processing / Signal)
clear; close all; clc;

%% 1. Synthesize Clutter Background with Embedded Targets
N = 200;
rng(101);

% Background clutter (Exponentially distributed power using base MATLAB: -mu * log(rand))
clutter_bg = -0.5 * log(rand(N, N));
scene = clutter_bg;

% Add three target signatures by adding to clutter rather than overwriting
scene(50:54, 60:64)   = scene(50:54, 60:64)   + 8.0;  % Target 1: Vehicle hull
scene(120, 140)       = scene(120, 140)       + 6.5;  % Target 2: Point reflector
scene(130:135, 70:75) = scene(130:135, 70:75) + 9.0;  % Target 3: Vehicle / cluster

%% 2. 2D Cell-Averaging CFAR (CA-CFAR) Detector
disp('Executing 2D CA-CFAR Target Detection...');

% CFAR Window Dimensions
T_guard = 5;           % Guard cells (half-width) around cell under test (CUT)
T_train = 6;           % Training/Reference cells (half-width)
Pfa = 1e-4;            % Desired Probability of False Alarm

win_train = 2 * (T_guard + T_train) + 1;
win_guard = 2 * T_guard + 1;

N_training = (win_train^2) - (win_guard^2);
% CFAR scaling threshold factor: alpha = N_t * (Pfa^(-1/N_t) - 1)
alpha_cfar = N_training * (Pfa^(-1 / N_training) - 1);

% 2D Convolution kernels for neighborhood clutter estimation
kernel_full = ones(win_train, win_train);
kernel_guard = zeros(win_train, win_train);
kernel_guard(T_train+1 : T_train+win_guard, T_train+1 : T_train+win_guard) = 1;
kernel_train = (kernel_full - kernel_guard) / N_training;

% Edge-replicated boundary clutter estimation via valid convolution
m = T_guard + T_train;
idx = [ones(1,m), 1:N, N*ones(1,m)];
clutter_level = conv2(scene(idx, idx), kernel_train, 'valid');
threshold_map = clutter_level * alpha_cfar;

% CFAR Decision Rule: Cell Under Test > Dynamic Clutter Threshold
cfar_detection_map = scene > threshold_map;

%% 3. Connected Component Segmentation & Feature Extraction
% Label isolated detected target clusters using custom flood-fill
[labeled_map, num_targets] = custom_bwlabel(cfar_detection_map);

fprintf('\n================== SAR TARGET DETECTION & ATR REPORT ==================\n');
fprintf(' Detected Target Clusters: %d\n', num_targets);
fprintf('-----------------------------------------------------------------------\n');
fprintf(' Target ID | Centroid (X,Y) | Area (Pixels) | Peak RCS | Classification\n');
fprintf('-----------+----------------+---------------+----------+---------------\n');

target_props = cell(num_targets, 5);

for obj = 1:num_targets
    [r, c] = find(labeled_map == obj);
    area = numel(r);
    cent_y = round(mean(r));
    cent_x = round(mean(c));
    peak_val = max(scene(labeled_map == obj));
    
    % ATR Classification Logic based on cluster pixel area
    if area <= 4
        cls = 'Point';
    elseif area <= 40
        cls = 'Vehicle';
    else
        cls = 'Cluster';
    end
    
    target_props{obj, 1} = obj;
    target_props{obj, 2} = sprintf('(%d, %d)', cent_x, cent_y);
    target_props{obj, 3} = area;
    target_props{obj, 4} = peak_val;
    target_props{obj, 5} = cls;
    
    fprintf(' %-9d | %-14s | %-13d | %-8.2f | %-20s\n', ...
        obj, target_props{obj,2}, area, peak_val, cls);
end
fprintf('=======================================================================\n\n');

%% 4. Visualization
figure('Color', 'w', 'Position', [80, 80, 1200, 700]);

subplot(2, 2, 1);
imagesc(10*log10(scene), [-5, 15]); colormap(gca, 'gray'); colorbar;
title('1. Input SAR Intensity Image (dB)');
xlabel('Range Pixels'); ylabel('Azimuth Pixels'); axis square;

subplot(2, 2, 2);
imagesc(10*log10(threshold_map), [-5, 15]); colormap(gca, 'jet'); colorbar;
title('2. Dynamic CA-CFAR Clutter Threshold (dB)');
xlabel('Range Pixels'); ylabel('Azimuth Pixels'); axis square;

subplot(2, 2, 3);
imagesc(cfar_detection_map); colormap(gca, 'gray'); colorbar;
title('3. Binary CFAR Detections');
xlabel('Range Pixels'); ylabel('Azimuth Pixels'); axis square;

subplot(2, 2, 4);
imagesc(10*log10(scene), [-5, 15]); colormap(gca, 'gray'); hold on;
% Overlay detection bounding boxes and centroids
for obj = 1:num_targets
    [r, c] = find(labeled_map == obj);
    if isempty(r), continue; end
    r_min = min(r); r_max = max(r);
    c_min = min(c); c_max = max(c);
    
    area = numel(r);
    if area <= 4
        cls = 'Point';
    elseif area <= 40
        cls = 'Vehicle';
    else
        cls = 'Cluster';
    end
    
    % Draw bounding box
    rectangle('Position', [c_min-1, r_min-1, (c_max-c_min)+2, (r_max-r_min)+2], ...
              'EdgeColor', 'r', 'LineWidth', 1.5);
    % Plot centroid marker
    plot(mean(c), mean(r), 'g+', 'MarkerSize', 8, 'LineWidth', 1.5);
    text(c_min, r_min-2, sprintf('T%d: %s', obj, cls), ...
        'Color', 'yellow', 'FontSize', 8, 'FontWeight', 'bold');
end
title('4. ATR Classified Targets with Overlays');
xlabel('Range Pixels'); ylabel('Azimuth Pixels'); axis square;

%% Local Helper Function: 8-Connected Component Labeling
function [labels, count] = custom_bwlabel(BW)
    [rows, cols] = size(BW);
    labels = zeros(rows, cols);
    count = 0;
    
    for r = 1:rows
        for c = 1:cols
            if BW(r, c) && labels(r, c) == 0
                count = count + 1;
                % Flood fill using a stack (8-connectivity)
                stack = [r, c];
                labels(r, c) = count;
                
                while ~isempty(stack)
                    curr = stack(end, :);
                    stack(end, :) = [];
                    cr = curr(1); cc = curr(2);
                    
                    for dr = -1:1
                        for dc = -1:1
                            nr = cr + dr; nc = cc + dc;
                            if nr >= 1 && nr <= rows && nc >= 1 && nc <= cols
                                if BW(nr, nc) && labels(nr, nc) == 0
                                    labels(nr, nc) = count;
                                    stack = [stack; nr, nc]; %#ok<AGROW>
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end