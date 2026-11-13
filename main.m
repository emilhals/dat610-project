%% 5G NR PDSCH simulation
% Based on the MathWorks NR PDSCH Throughput example:
% https://se.mathworks.com/help/5g/ug/nr-pdsch-throughput.html

clearvars;
close all;
clc;

%% Parameters
cfg.fcHz          = 3.5e9;
cfg.scsKHz        = [15 30 60];
cfg.nRB           = [106 51 24];
cfg.delaySpreadS  = 300e-9;
cfg.delayProfile  = 'TDL-C';
cfg.modulation    = '64QAM';
cfg.codeRate      = 0.5;
cfg.nLayers       = 1;
cfg.nFrames       = 100;
cfg.maxLDPCIter   = 12;
cfg.seed          = 2026;
cfg.channelSeed   = 73;
cfg.snrEval1      = 20;
cfg.speedsEval1   = [0 3 50 120 300 500];
cfg.speedsEval2   = [3 300];
cfg.snrEval2      = 0:2:30;
cfg.blerTarget    = 0.10;
cfg.plotsOnly     = true; % Set false to run the simulation again

outputDir = fullfile(fileparts(mfilename('fullpath')), 'scs_results');
if ~isfolder(outputDir)
    mkdir(outputDir);
end

resultNames = {'SCS_kHz','Speed_kmh','SNR_dB','Doppler_Hz', ...
    'Throughput_Mbps','BLER','FailedBlocks','TotalBlocks'};

%% Evaluations
if cfg.plotsOnly
    file1 = fullfile(outputDir, 'evaluation1_mobility.csv');
    file2 = fullfile(outputDir, 'evaluation2_snr.csv');
    if ~isfile(file1) || ~isfile(file2)
        error('Plots-only mode requires both CSV result files in %s', outputDir);
    end
    eval1 = readtable(file1);
    eval2 = readtable(file2);
    fprintf('Plots-only mode: using saved CSV data. No radio simulation run.\n');
else
    % Evaluation 1: mobility at 20 dB
    nPoints1 = numel(cfg.scsKHz) * numel(cfg.speedsEval1);
    data1 = zeros(nPoints1, numel(resultNames));
    k = 0;

    for i = 1:numel(cfg.scsKHz)
        for j = 1:numel(cfg.speedsEval1)
            scs = cfg.scsKHz(i);
            nrb = cfg.nRB(i);
            speed = cfg.speedsEval1(j);
            fprintf('Eval 1: SCS=%d kHz, speed=%g km/h, SNR=%g dB\n', ...
                scs, speed, cfg.snrEval1);
            r = simulatePoint(cfg, scs, nrb, speed, cfg.snrEval1);
            k = k + 1;
            data1(k,:) = packResult(scs, speed, cfg.snrEval1, r);
        end
    end

    eval1 = array2table(data1, 'VariableNames', resultNames);
    writetable(eval1, fullfile(outputDir, 'evaluation1_mobility.csv'));
    disp(eval1);


    % Evaluation 2: SNR at 3 and 300 km/h
    nPoints2 = numel(cfg.scsKHz) * numel(cfg.speedsEval2) * numel(cfg.snrEval2);
    data2 = zeros(nPoints2, numel(resultNames));
    k = 0;

    for i = 1:numel(cfg.scsKHz)
        for j = 1:numel(cfg.speedsEval2)
            for t = 1:numel(cfg.snrEval2)
                scs = cfg.scsKHz(i);
                nrb = cfg.nRB(i);
                speed = cfg.speedsEval2(j);
                snrDb = cfg.snrEval2(t);
                fprintf('Eval 2: SCS=%d kHz, speed=%g km/h, SNR=%g dB\n', ...
                    scs, speed, snrDb);
                r = simulatePoint(cfg, scs, nrb, speed, snrDb);
                k = k + 1;
                data2(k,:) = packResult(scs, speed, snrDb, r);
            end
        end
    end

    eval2 = array2table(data2, 'VariableNames', resultNames);
    writetable(eval2, fullfile(outputDir, 'evaluation2_snr.csv'));
    disp(eval2);
end

%% BLER threshold
thresholdRows = zeros(numel(cfg.scsKHz) * numel(cfg.speedsEval2), 3);
k = 0;
for i = 1:numel(cfg.scsKHz)
    for j = 1:numel(cfg.speedsEval2)
        scs = cfg.scsKHz(i);
        speed = cfg.speedsEval2(j);
        rows = eval2(eval2.SCS_kHz == scs & eval2.Speed_kmh == speed, :);
        goodIdx = find(rows.BLER <= cfg.blerTarget, 1, 'first');
        minSNR = NaN;
        if ~isempty(goodIdx)
            minSNR = rows.SNR_dB(goodIdx);
        end
        k = k + 1;
        thresholdRows(k,:) = [scs speed minSNR];
    end
end

thresholds = array2table(thresholdRows, 'VariableNames', ...
    {'SCS_kHz','Speed_kmh','MinimumSNR_dB'});
writetable(thresholds, fullfile(outputDir, 'snr_threshold_10pct_bler.csv'));
disp('Minimum sampled SNR for BLER <= 10% (NaN = not reached):');
disp(thresholds);

%% Figures
plotMobility(eval1, cfg, 'BLER', 'Transport block error rate (BLER)', ...
    'evaluation1_bler.png', outputDir);
plotMobility(eval1, cfg, 'Throughput_Mbps', 'Decoded payload goodput (Mbit/s)', ...
    'evaluation1_throughput.png', outputDir);

plotSNR(eval2, cfg, 'BLER', 'Transport block error rate (BLER)', ...
    'evaluation2_bler.png', outputDir);
plotSNR(eval2, cfg, 'Throughput_Mbps', 'Decoded payload goodput (Mbit/s)', ...
    'evaluation2_throughput.png', outputDir);

save(fullfile(outputDir, 'all_results.mat'), 'cfg', 'eval1', 'eval2', 'thresholds');
fprintf('\nResults saved to: %s\n', outputDir);

%% Simulation

function r = simulatePoint(cfg, scsKHz, nRB, speedKmh, snrDb)

    rng(cfg.seed, 'twister');

    carrier = nrCarrierConfig;
    carrier.NCellID = 1;
    carrier.SubcarrierSpacing = scsKHz;
    carrier.NSizeGrid = nRB;
    carrier.CyclicPrefix = 'Normal';

    pdsch = nrPDSCHConfig;
    pdsch.PRBSet = 0:nRB-1;
    pdsch.SymbolAllocation = [0 carrier.SymbolsPerSlot];
    pdsch.MappingType = 'A';
    pdsch.Modulation = cfg.modulation;
    pdsch.NumLayers = cfg.nLayers;
    pdsch.NID = carrier.NCellID;
    pdsch.RNTI = 1;
    pdsch.EnablePTRS = 0;

    pdsch.DMRS.DMRSTypeAPosition = 2;
    pdsch.DMRS.DMRSLength = 1;
    pdsch.DMRS.DMRSAdditionalPosition = 2;
    pdsch.DMRS.DMRSConfigurationType = 2;
    pdsch.DMRS.NumCDMGroupsWithoutData = 1;
    pdsch.DMRS.NIDNSCID = 1;
    pdsch.DMRS.NSCID = 0;

    maxDopplerHz = (speedKmh / 3.6) * cfg.fcHz / 299792458;
    waveInfo = nrOFDMInfo(carrier);
    channel = nrTDLChannel;
    channel.DelayProfile = cfg.delayProfile;
    channel.DelaySpread = cfg.delaySpreadS;
    channel.MaximumDopplerShift = maxDopplerHz;
    channel.SampleRate = waveInfo.SampleRate;
    if isprop(channel, 'PathGainSampleRate')
        channel.PathGainSampleRate = 'auto';
    end
    channel.NumTransmitAntennas = 1;
    channel.NumReceiveAntennas = 1;
    channel.RandomStream = 'mt19937ar with seed';
    channel.Seed = cfg.channelSeed;

    channelInfo = info(channel); % R2022a does not provide MaximumChannelDelay
    if isfield(channelInfo, 'MaximumChannelDelay')
        maxChDelay = channelInfo.MaximumChannelDelay;
    else
        maxChDelay = ceil(max(channelInfo.PathDelays) * channel.SampleRate) ...
            + channelInfo.ChannelFilterDelay;
    end

    encDL = nrDLSCH;
    encDL.TargetCodeRate = cfg.codeRate;
    decDL = nrDLSCHDecoder;
    decDL.TargetCodeRate = cfg.codeRate;
    decDL.LDPCDecodingAlgorithm = 'Normalized min-sum';
    decDL.MaximumLDPCIterationCount = cfg.maxLDPCIter;

    nSlots = cfg.nFrames * carrier.SlotsPerFrame;
    durationS = cfg.nFrames * 0.010;
    rv = 0; % No HARQ retransmissions
    nCorrectBits = 0;
    nFailed = 0;
    lastValidOffset = 0;

    noiseAmplitude = 1 / sqrt(waveInfo.Nfft * 10^(snrDb/10));

    for slot = 0:nSlots-1
        carrier.NSlot = slot;

        [dataInd, indInfo] = nrPDSCHIndices(carrier, pdsch);
        tbSize = nrTBS(pdsch.Modulation, pdsch.NumLayers, ...
            numel(pdsch.PRBSet), indInfo.NREPerPRB, cfg.codeRate, 0);

        trBlk = randi([0 1], tbSize, 1, 'int8');
        setTransportBlock(encDL, trBlk);
        codedBits = encDL(pdsch.Modulation, pdsch.NumLayers, indInfo.G, rv);

        txGrid = nrResourceGrid(carrier);
        txGrid(dataInd) = nrPDSCH(carrier, pdsch, codedBits);
        dmrsInd = nrPDSCHDMRSIndices(carrier, pdsch);
        dmrsSym = nrPDSCHDMRS(carrier, pdsch);
        txGrid(dmrsInd) = dmrsSym;

        txWave = nrOFDMModulate(carrier, txGrid);
        txWave = [txWave; zeros(maxChDelay,1,'like',txWave)]; %#ok<AGROW>
        rxWave = channel(txWave);
        rxNoise = noiseAmplitude * randn(size(rxWave), 'like', rxWave);
        rxWave = rxWave + rxNoise;

        estimatedOffset = nrTimingEstimate(carrier, rxWave, dmrsInd, dmrsSym);
        if estimatedOffset <= maxChDelay
            lastValidOffset = estimatedOffset;
        end
        rxWave = rxWave(lastValidOffset+1:end,:);

        rxGrid = nrOFDMDemodulate(carrier, rxWave);
        [K,L,R] = size(rxGrid);
        if L < carrier.SymbolsPerSlot
            rxGrid = cat(2, rxGrid, ...
                zeros(K, carrier.SymbolsPerSlot-L, R, 'like', rxGrid));
        elseif L > carrier.SymbolsPerSlot
            rxGrid = rxGrid(:, 1:carrier.SymbolsPerSlot, :);
        end

        [hEst, noiseEst] = nrChannelEstimate(carrier, rxGrid, ...
            dmrsInd, dmrsSym, 'CDMLengths', pdsch.DMRS.CDMLengths);
        noiseEst = max(double(mean(noiseEst(:))), 1e-10);
        [rxData, hData] = nrExtractResources(dataInd, rxGrid, hEst);

        [eqData, csi] = nrEqualizeMMSE(rxData, hData, noiseEst);
        [codewordLLRs, rxSymbols] = nrPDSCHDecode(carrier, pdsch, eqData, noiseEst);
        csiCW = nrLayerDemap(csi);
        bitsPerSymbol = numel(codewordLLRs{1}) / numel(rxSymbols{1});
        llrs = codewordLLRs{1} .* repelem(csiCW{1}(:), bitsPerSymbol);

        reset(decDL); % Do not combine transport blocks across slots
        decDL.TransportBlockLength = tbSize;
        [~, blockError] = decDL(llrs, pdsch.Modulation, pdsch.NumLayers, rv);

        nFailed = nFailed + double(blockError);
        if ~blockError
            nCorrectBits = nCorrectBits + tbSize;
        end
    end

    r.maxDopplerHz = maxDopplerHz;
    r.throughputMbps = nCorrectBits / durationS / 1e6;
    r.bler = nFailed / nSlots;
    r.failedBlocks = nFailed;
    r.totalBlocks = nSlots;
end

function row = packResult(scsKHz, speedKmh, snrDb, r)
    row = [scsKHz, speedKmh, snrDb, r.maxDopplerHz, ...
        r.throughputMbps, r.bler, r.failedBlocks, r.totalBlocks];
end

function plotMobility(tbl, cfg, metric, yLabel, fileName, outputDir)
    fig = figure('Color', 'w', 'Position', [100 100 780 490]);
    hold on;
    for i = 1:numel(cfg.scsKHz)
        scs = cfg.scsKHz(i);
        rows = sortrows(tbl(tbl.SCS_kHz == scs, :), 'Speed_kmh');
        plot(rows.Speed_kmh, rows.(metric), '-o', 'LineWidth', 2, ...
            'MarkerSize', 7, ...
            'DisplayName', sprintf('%d kHz (%d PRBs)', scs, cfg.nRB(i)));
    end
    xlabel('UE speed (km/h)', 'FontSize', 17);
    ylabel(yLabel, 'FontSize', 17);
    set(gca, 'FontSize', 15);
    grid on;
    legend('Location', 'best', 'FontSize', 13);
    if strcmp(metric, 'BLER')
        ylim([0 1]);
    end
    text(0.02, 0.04, sprintf('SNR = %g dB', cfg.snrEval1), ...
        'Units', 'normalized', 'FontSize', 13, 'BackgroundColor', 'w');
    exportFigure(fig, fullfile(outputDir, fileName));
end

function plotSNR(tbl, cfg, metric, yLabel, fileName, outputDir)
    fig = figure('Color', 'w', 'Position', [100 100 850 950]);

    for j = 1:numel(cfg.speedsEval2)
        speed = cfg.speedsEval2(j);
        ax = subplot(2, 1, j);
        hold(ax, 'on');

        for i = 1:numel(cfg.scsKHz)
            scs = cfg.scsKHz(i);
            rows = tbl(tbl.SCS_kHz == scs & tbl.Speed_kmh == speed, :);
            rows = sortrows(rows, 'SNR_dB');
            if isempty(rows)
                warning('No data for SCS %d kHz at %d km/h', scs, speed);
                continue;
            end
            plot(ax, rows.SNR_dB, rows.(metric), '-o', ...
                'LineWidth', 2, 'MarkerSize', 6, ...
                'DisplayName', sprintf('%d kHz (%d PRBs)', scs, cfg.nRB(i)));
        end

        if strcmp(metric, 'BLER')
            plot(ax, [min(cfg.snrEval2), max(cfg.snrEval2)], ...
                [cfg.blerTarget, cfg.blerTarget], 'k--', ...
                'LineWidth', 1, 'HandleVisibility', 'off');
            ylim(ax, [0 1]);
        end

        xlabel(ax, 'Configured SNR (dB)', 'FontSize', 18);
        ylabel(ax, yLabel, 'FontSize', 18);
        set(ax, 'FontSize', 15);
        grid(ax, 'on');
        legend(ax, 'Location', 'best', 'FontSize', 14);

        if speed == 3
            scenario = 'Pedestrian';
        else
            scenario = 'High-speed train';
        end
        text(ax, 0.03, 0.05, sprintf('%s (%g km/h)', scenario, speed), ...
            'Units', 'normalized', 'FontSize', 14, 'BackgroundColor', 'w');
    end

    exportFigure(fig, fullfile(outputDir, fileName));
end

function exportFigure(fig, fileName)
    exportgraphics(fig, fileName, 'Resolution', 300);
    if ~isfile(fileName)
        error('Figure was not saved: %s', fileName);
    end
    fprintf('Saved figure: %s\n', fileName);
end
