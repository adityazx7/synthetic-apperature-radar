%% SAR Mission Control & Interactive Simulation Suite
function sar_mission_control_gui1()
close all;

f = figure('Name', 'SAR Tactical Mission Control System', 'NumberTitle', 'off', ...
    'Position', [100, 100, 1200, 700], 'Color', [0.12 0.12 0.14], 'MenuBar', 'none');

uicontrol('Style', 'text', 'String', 'SAR ADVANCED MULTI-MODAL INTELLIGENCE PLATFORM', ...
    'Position', [50, 650, 1100, 35], 'FontSize', 14, 'FontWeight', 'bold', ...
    'ForegroundColor', [0.2 0.9 1.0], 'BackgroundColor', [0.12 0.12 0.14]);

ax1 = axes('Parent', f, 'Position', [0.32, 0.52, 0.31, 0.38], 'Color', [0.05 0.05 0.05]);
ax2 = axes('Parent', f, 'Position', [0.66, 0.52, 0.31, 0.38], 'Color', [0.05 0.05 0.05]);
ax3 = axes('Parent', f, 'Position', [0.32, 0.08, 0.31, 0.38], 'Color', [0.05 0.05 0.05]);
ax4 = axes('Parent', f, 'Position', [0.66, 0.08, 0.31, 0.38], 'Color', [0.05 0.05 0.05]);

p_ctrl = uipanel('Parent', f, 'Title', 'Radar Parameters & Controls', 'FontSize', 11, ...
    'ForegroundColor', 'w', 'BackgroundColor', [0.18 0.18 0.22], ...
    'Position', [0.02, 0.05, 0.27, 0.85]);

uicontrol('Parent', p_ctrl, 'Style', 'text', 'String', 'Chirp Bandwidth (MHz):', ...
    'Position', [15, 480, 200, 20], 'ForegroundColor', 'w', 'BackgroundColor', [0.18 0.18 0.22], 'HorizontalAlignment', 'left');
sld_bw = uicontrol('Parent', p_ctrl, 'Style', 'slider', 'Min', 20, 'Max', 100, 'Value', 60, ...
    'Position', [15, 455, 230, 20]);
lbl_bw = uicontrol('Parent', p_ctrl, 'Style', 'text', 'String', '60 MHz', ...
    'Position', [200, 480, 50, 20], 'ForegroundColor', [0.2 0.9 1.0], 'BackgroundColor', [0.18 0.18 0.22]);

uicontrol('Parent', p_ctrl, 'Style', 'text', 'String', 'Moving Target Velocity (m/s):', ...
    'Position', [15, 410, 200, 20], 'ForegroundColor', 'w', 'BackgroundColor', [0.18 0.18 0.22], 'HorizontalAlignment', 'left');
sld_vel = uicontrol('Parent', p_ctrl, 'Style', 'slider', 'Min', 0, 'Max', 30, 'Value', 10, ...
    'Position', [15, 385, 230, 20]);
lbl_vel = uicontrol('Parent', p_ctrl, 'Style', 'text', 'String', '10 m/s', ...
    'Position', [200, 410, 50, 20], 'ForegroundColor', [0.2 0.9 1.0], 'BackgroundColor', [0.18 0.18 0.22]);

uicontrol('Parent', p_ctrl, 'Style', 'text', 'String', 'Clutter SCNR Level (dB):', ...
    'Position', [15, 340, 200, 20], 'ForegroundColor', 'w', 'BackgroundColor', [0.18 0.18 0.22], 'HorizontalAlignment', 'left');
sld_snr = uicontrol('Parent', p_ctrl, 'Style', 'slider', 'Min', -10, 'Max', 25, 'Value', 15, ...
    'Position', [15, 315, 230, 20]);
lbl_snr = uicontrol('Parent', p_ctrl, 'Style', 'text', 'String', '15 dB', ...
    'Position', [200, 340, 50, 20], 'ForegroundColor', [0.2 0.9 1.0], 'BackgroundColor', [0.18 0.18 0.22]);

btn_run = uicontrol('Parent', p_ctrl, 'Style', 'pushbutton', 'String', 'RUN RECONSTRUCTION', ...
    'Position', [15, 230, 230, 45], 'FontSize', 10, 'FontWeight', 'bold', ...
    'BackgroundColor', [0.1 0.6 0.3], 'ForegroundColor', 'w', ...
    'Callback', @(src, event) update_sar_display());

sld_bw.Callback = @(src, e) set(lbl_bw, 'String', sprintf('%.0f MHz', sld_bw.Value));
sld_vel.Callback = @(src, e) set(lbl_vel, 'String', sprintf('%.0f m/s', sld_vel.Value));
sld_snr.Callback = @(src, e) set(lbl_snr, 'String', sprintf('%.0f dB', sld_snr.Value));

update_sar_display();

    function update_sar_display()
        B_val = sld_bw.Value * 1e6;
        v_target = sld_vel.Value;
        snr_val = sld_snr.Value;

        c = 3e8;
        N = 128;
        [X, Y] = meshgrid(linspace(-30, 30, N), linspace(-30, 30, N));
        res_r = c / (2 * B_val);
        psf = abs(sinc_n(X / 1.0) .* sinc_n(Y / res_r));
        noise = (10^(-snr_val/20)) * randn(N, N);
        img1 = 20*log10(psf + abs(noise) + 1e-4);

        imagesc(ax1, linspace(-30,30,N), linspace(-30,30,N), img1, [-30 0]);
        colormap(ax1, 'turbo'); title(ax1, '1. Focused RDA Reconstruction (dB)', 'Color', 'w');
        xlabel(ax1, 'Azimuth (m)', 'Color', 'w'); ylabel(ax1, 'Range (m)', 'Color', 'w');
        set(ax1, 'XColor', 'w', 'YColor', 'w');

        dem = 80 * exp(-(X.^2 + Y.^2) / 300);
        surf(ax2, X, Y, dem, 'EdgeColor', 'none');
        colormap(ax2, 'jet'); title(ax2, '2. InSAR Inverted Topography (DEM)', 'Color', 'w');
        set(ax2, 'XColor', 'w', 'YColor', 'w', 'ZColor', 'w'); view(ax2, -30, 45);

        imagesc(ax3, linspace(-30,30,N), linspace(-30,30,N), img1 > -12);
        colormap(ax3, 'gray'); hold(ax3, 'on');
        plot(ax3, 0, v_target*0.8, 'ro', 'MarkerSize', 12, 'LineWidth', 2);
        title(ax3, sprintf('3. GMTI Target Tracking (v_r = %.1f m/s)', v_target), 'Color', 'w');
        xlabel(ax3, 'Azimuth (m)', 'Color', 'w'); ylabel(ax3, 'Range (m)', 'Color', 'w');
        set(ax3, 'XColor', 'w', 'YColor', 'w'); hold(ax3, 'off');

        rgb_map = zeros(N, N, 3);
        rgb_map(:,:,1) = (dem > 30);
        rgb_map(:,:,2) = (abs(noise) > 0.08);
        rgb_map(:,:,3) = (psf > 0.3);
        image(ax4, rgb_map); axis(ax4, 'image');
        title(ax4, '4. Pauli RGB Target Classification', 'Color', 'w');
    end
end

function y = sinc_n(x)
    y = ones(size(x));
    i = (x ~= 0);
    y(i) = sin(pi * x(i)) ./ (pi * x(i));
end