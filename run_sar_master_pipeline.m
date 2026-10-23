function run_sar_master_pipeline()
    %% Master Orchestrator & Benchmark Runner for SAR Simulator Suite
    close all; clc;

    results_dir = fullfile(pwd, 'results');
    if ~exist(results_dir, 'dir')
        mkdir(results_dir); 
    end

    fprintf('========================================================================\n');
    fprintf('       STARTING COMPLETE SAR SIMULATION & PROCESSING SUITE BATCH       \n');
    fprintf('========================================================================\n\n');

    modules = {
        'sar_simulation_pipeline', 'Baseline RDA, Clutter, Stepped-Frequency & Quality Metrics';
        'sar_rcmc_rda',           '8-Point Sinc Range Cell Migration Correction (RCMC)';
        'sar_backprojection',     'Time-Domain Backprojection Algorithm (BPA)';
        'sar_insar_simulation',   'Interferometric SAR (InSAR) & Topographic Phase Extraction';
        'sar_polsar_simulation',  'Polarimetric SAR (PolSAR) & Pauli Target Decomposition';
        'sar_gmti_ati',           'Ground Moving Target Indication & Along-Track InSAR';
        'sar_speckle_filters',    'Despeckling Suite (Boxcar, Adaptive Lee, Frost)';
        'sar_atr_classification', '2D CA-CFAR Target Detection & Morphological ATR'
    };

    num_mods = size(modules, 1);
    execution_times = zeros(num_mods, 1);
    execution_status = strings(num_mods, 1);

    for m_idx = 1:num_mods
        current_script = modules{m_idx, 1};
        fprintf('--> [%d/%d] Running Module: %-25s ... ', m_idx, num_mods, current_script);
        
        try
            t_start = tic;
            run_one(current_script);
            t_elapsed = toc(t_start);
            
            execution_times(m_idx) = t_elapsed;
            execution_status(m_idx) = "SUCCESS";
            fprintf('DONE (%.2f s)\n', t_elapsed);
            
            if ~isempty(get(groot, 'Children'))
                save_path = fullfile(results_dir, sprintf('fig_%02d_%s.png', m_idx, current_script));
                saveas(gcf, save_path);
            end
        catch ME
            execution_times(m_idx) = NaN;
            execution_status(m_idx) = "FAILED";
            fprintf('ERROR: %s\n', ME.message);
        end
    end

    %% Summary Report
    fprintf('\n========================================================================\n');
    fprintf('                    MASTER SUITE EXECUTION SUMMARY                      \n');
    fprintf('========================================================================\n');
    fprintf(' # | Module Name              | Status   | Runtime (s) | Description\n');
    fprintf('---+--------------------------+----------+-------------+----------------\n');
    for m = 1:num_mods
        fprintf(' %d | %-24s | %-8s | %11.2f | %s\n', ...
            m, modules{m,1}, execution_status(m), execution_times(m), modules{m,2});
    end
    fprintf('========================================================================\n');
    fprintf(' Total Pipeline Time: %.2f seconds\n', sum(execution_times(~isnan(execution_times))));
    fprintf(' Figures saved to: %s\n\n', results_dir);

    %% Bar Chart Visualization (with LaTeX interpreter disabled for clean labels)
    figure('Color', 'w', 'Position', [150, 150, 900, 480]);
    bar(execution_times, 'FaceColor', [0.15 0.45 0.75]);
    grid on;
    set(gca, 'XTick', 1:num_mods, 'XTickLabel', modules(:, 1), ...
             'TickLabelInterpreter', 'none', 'XTickLabelRotation', 30);
    ylabel('Execution Time (seconds)');
    title('Computational Complexity Profile per SAR Module', 'Interpreter', 'none');

    valid_times = execution_times(~isnan(execution_times));
    if isempty(valid_times) || max(valid_times) == 0
        max_t = 1;
    else
        max_t = max(valid_times);
    end

    for i = 1:num_mods
        if ~isnan(execution_times(i))
            text(i, execution_times(i) + 0.04 * max_t, ...
                sprintf('%.2fs', execution_times(i)), ...
                'HorizontalAlignment', 'center', 'FontWeight', 'bold');
        else
            text(i, 0.05 * max_t, 'FAIL', ...
                'HorizontalAlignment', 'center', 'Color', 'red', 'FontWeight', 'bold');
        end
    end
    axis tight;
    saveas(gcf, fullfile(results_dir, 'fig_00_benchmark_times.png'));

    %% Generate Automated LaTeX Technical Report
    try
        generate_sar_latex_report();
    catch ME_rep
        fprintf('Report generation skipped: %s\n', ME_rep.message);
    end
end

function run_one(name)
    eval(name);
end