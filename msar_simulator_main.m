%% Step 1: Define Radar System Parameters
% Fundamental physical and operational parameters

% 1. Wave and Frequency Parameters
fc = 5.3e9;                  % Operating center frequency in Hz (C-band)
c = physconst('LightSpeed'); % Speed of light in vacuum (m/s)
lambda = c / fc;             % Wavelength in meters

% 2. Resolution Requirements
rangeResolution = 1.5;       % Desired range resolution in meters
azimuthResolution = 1.5;     % Desired azimuth resolution in meters

% 3. Waveform Parameters
B = c / (2 * rangeResolution); % Signal Bandwidth in Hz
pulseWidth = 10e-6;            % Pulse duration in seconds
chirpRate = B / pulseWidth;    % Linear FM chirp rate (Hz/s)

% 4. Antenna Dimensions
antennaLength = 2 * azimuthResolution; % Antenna length in azimuth (meters)
antennaWidth = 0.5;                    % Antenna width in elevation (meters)

% 5. Timing and Sampling
PRF = 1000;         % Pulse Repetition Frequency in Hz
Fs = 1.2 * B;       % Sampling frequency (Hz)

% 6. Power Parameter
peakPower = 5000;   % Peak transmit power in Watts
%% Step 2: Initialize Waveform & Antenna Objects
waveform = phased.LinearFMWaveform(...
    'SampleRate', Fs, ...
    'PulseWidth', pulseWidth, ...
    'PRF', PRF, ...
    'SweepBandwidth', B);

antenna = phased.CosineAntennaElement(...
    'FrequencyRange', [fc-B, fc+B], ...
    'CosinePower', [1.5, 1.5]);

%% Step 3: Setup Transmitter, Radiator, Collector, and Receiver Objects
transmitter = phased.Transmitter(...
    'PeakPower', peakPower, ...
    'Gain', 35, ...
    'InUseOutputPort', true);

radiator = phased.Radiator(...
    'Sensor', antenna, ...
    'OperatingFrequency', fc);

collector = phased.Collector(...
    'Sensor', antenna, ...
    'OperatingFrequency', fc);

receiver = phased.ReceiverPreamp(...
    'SampleRate', Fs, ...
    'NoiseFigure', 3);
%% Step 4: Define Platform Motion & Point Target Geometry
% 1. Radar Platform Parameters (Stripmap SAR Mode)
platformAltitude = 5000;            % Flight altitude in meters (5 km)
platformVelocity = 150;             % Forward platform velocity along Y-axis in m/s
platformInitPos = [0; -300; platformAltitude]; % [X (cross-track); Y (along-track); Z (height)]

radarPlatform = phased.Platform(...
    'InitialPosition', platformInitPos, ...
    'Velocity', [0; platformVelocity; 0]);

% 2. Stationary Point Target Position
% Positioned at ground range X = 3000 m, Y = 0 m, Z = 0 m
targetPos = [3000; 0; 0];
targetVelocity = [0; 0; 0];

targetPlatform = phased.Platform(...
    'InitialPosition', targetPos, ...
    'Velocity', targetVelocity);

%% Step 5: Define Radar Target (RCS Modeling)
% A single isotropic point scatterer with an RCS of 1 square meter (0 dBsm)
targetRCS = 1.0; 

target = phased.RadarTarget(...
    'MeanRCS', targetRCS, ...
    'OperatingFrequency', fc);

%% Step 6: Model Propagation Channel & Environmental Physics
% 1. Atmospheric and Free-Space Loss Channel
% Incorporates two-way path loss and atmospheric attenuation
channel = phased.FreeSpace(...
    'SampleRate', Fs, ...
    'OperatingFrequency', fc, ...
    'TwoWayPropagation', false); % Set to false so we pass signal forward and back explicitly

% 2. Geometric Calculations: Grazing & Depression Angles
slantRange = norm(platformInitPos - targetPos);
groundRange = targetPos(1) - platformInitPos(1);
elevationHeight = platformAltitude - targetPos(3);

% Depression angle (alpha) and Grazing angle (psi) over flat ground reference
depressionAngle = atan2d(elevationHeight, groundRange);
grazingAngle = depressionAngle; % For flat earth approximation
%% Phase 3: Raw IQ Data Generation (The Simulation Loop)
% Step 7: Define Observation Time and Preallocate Matrix
% To keep the simulation fast, we will simulate 0.5 seconds of flight time.
T_obs = 0.5;                     
N_pulses = round(T_obs * PRF);     % Number of pulses (slow-time samples)
fastTimeSamples = round(Fs / PRF); % Number of fast-time samples per pulse

% Preallocate the 2D complex matrix to store the raw radar echoes
% Rows = Fast-time (range) samples, Columns = Slow-time (azimuth) pulses
rawIQData = complex(zeros(fastTimeSamples, N_pulses)); 

% Update the channel for monostatic round-trip propagation
release(channel); 
channel.TwoWayPropagation = true; 

% Generate the baseband pulse (only needs to be generated once for Linear FM)
sig = waveform();

%% Step 8: The Slow-Time Loop (Pulse-by-Pulse Simulation)
disp('Simulating SAR raw data. Please wait...');

for i = 1:N_pulses
    % a. Update platform positions for the current pulse interval (1/PRF)
    [radarPos, radarVel] = radarPlatform(1/PRF);
    [tgtPos, tgtVel]     = targetPlatform(1/PRF);

    % b. Calculate the angle from the radar to the target
    [~, tgtAngle] = rangeangle(tgtPos, radarPos);

    % c. Transmit: Amplify the waveform
    txSig = transmitter(sig);

    % d. Radiate: Apply antenna gain and directivity
    radSig = radiator(txSig, tgtAngle);

    % e. Propagate: Send the signal through space (round-trip)
    propSig = channel(radSig, radarPos, tgtPos, radarVel, tgtVel);

    % f. Reflect: Bounce the signal off the target's RCS
    reflectSig = target(propSig);

    % g. Collect: Receive the signal at the antenna
    colSig = collector(reflectSig, tgtAngle);

    % h. Receive: Apply preamp noise and store the echo in the matrix
    rawIQData(:, i) = receiver(colSig);
end

disp('Simulation Complete!');

% Optional: View the magnitude of the raw 2D echo matrix
figure;
imagesc(abs(rawIQData));
colormap('gray');
title('Raw SAR 2D Data (Unfocused)');
xlabel('Slow-Time (Pulses)');
ylabel('Fast-Time (Samples)');