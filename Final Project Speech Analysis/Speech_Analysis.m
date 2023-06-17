%% 1.Get the data ready for analysis
close all ; clear ; clc

% get a record from user
recobj=audiorecorder;
recDuration= 3;
disp('start recording..')
recordblocking(recobj,recDuration);
disp('stop recording')
% play the record
play(recobj);
pause(recDuration);
%%
% get the data form the record
data = getaudiodata(recobj);
% % % % % % % % % % % % % % % % % % d = data==0;
% % % % % % % % % % % % % % % % % % data(d)=0.01;
%plot the data
fs=8000;
plot(data)
title('original speech')
%apply low pass filter
% %% low pass filter

%
% time=recDuration;
% % Convert input sample to double and window it

% startfilter=round((-3000-(-fs/2))*time+1);
% endfilter=round((3000-(-fs/2))*time);
% dataf=fftshift(fft(data));
% dataf_lpf =dataf(startfilter:endfilter);
% fs=length(dataf_lpf)/time;

%
% % Calculate DFT of of the audio file
% data_lp=real(ifft(ifftshift(dataf_lpf)));
% sound(data_lp,fs);
% plot(data_lp)

% Define the frame parameters

frame_time=20e-3;
Frame_size=(frame_time/recDuration)*length(data);
TX_frame=zeros(Frame_size,1);
N_frames=length(data)/Frame_size;
overlapRatio = 0.5;
% Split the speech signal into frames with overlap
hopSize = round(Frame_size * (1 - overlapRatio));
N_frames = floor((length(data) - N_frames) / hopSize) + 1;


%% 2.Generate codebooks

% generate coodbook
[CB_noise, CB_size] = Codebook(Frame_size);


%% 3.Start Analysis (TX)


PWR = zeros(1,N_frames);
LPC_taps = 12;
L_initial = zeros(LPC_taps,1);
S_initial = zeros(LPC_taps,1);
L_lar = zeros(LPC_taps,1);
S_lar = zeros(LPC_taps,1);
Lx_initial = zeros(LPC_taps,1);
Sx_initial = zeros(LPC_taps,1);

Received = "Unvoiced";

% Preallocate RX_data
RX_data = zeros(length(data), 1);
% RX_data = 0;

%loop to simulate the data come in stream (realtime)
for i=1:N_frames

    % Apply Hamming Window
    frame = Hamming_Window(data,hopSize,Frame_size,i);
    TX_frame = frame;

    % Auto_Corr for frame to detect have pitch period or not
    AC = xcorr(TX_frame);
    AC = AC(160:end);
    PWR(i) = sum(TX_frame.^2)/Frame_size;
    
    % Sorting pitch periods (peaks) in signal
    [~, idx] = sort(AC,'descend');
    %initlaize pitch sample
    pitch=1;
    % Detect pitch periods in frame
    for j=1:length(idx)-1
        if(idx(j+1)>idx(j)+1)
            pitch = idx(j+1);
            break;
        end
    end
    
    
    % check pitch period is within average range for being voiced
    PP = ((pitch/Frame_size)*frame_time)*1e3;
    if( (PP> 2.5) && ( PP<17.5 ) )
        disp("voiced");
        Received = "voiced";
        
        %Long-term LPC parameters for voiced & unvoiced
        frame_x = [TX_frame(1); TX_frame(pitch-5:end)];
        L_lpc = lpc(frame_x,LPC_taps);
        %         L_lpc = stabilizeLPC(L_lpc);  % Stabilize LPC coefficients
        [TX_frame ,L_final ]=filter(L_lpc,1,TX_frame,L_initial);
        L_initial=L_final;
        
    end
    
    %short term lpc for both voiced and unvoiced frame
    S_lpc = lpc(TX_frame,LPC_taps);
    [TX_frame , S_final ]=filter(S_lpc,1,TX_frame,S_initial);
    %     S_lpc = stabilizeLPC(S_lpc);  % Stabilize LPC coefficients
    S_initial=S_final;
    AC_frame = xcorr(TX_frame);
    
    %find the minimum euclidean distance in code book noise
    ED = zeros(CB_size,1);
    for ii=1:CB_size
        ED(ii)=sum((CB_noise(:,ii)-TX_frame).^2);
    end
    
    % Sorting all distances and get index of first one
    [~,idx1] = sort(ED);
    noise_idx = idx1(1);
    
    %    % Get log area ratio of coff LPC
    %     L_lar = rc2lar(L_lpc);
    %     S_lar = rc2lar(S_lpc);
    %
    if(i==100)
        tt=TX_frame;
        % Assuming 'lpcCoefficients' contains the LPC coefficients
     
        % Obtain the roots of the LPC polynomial
        [lpcZeros,lpcRoots] = tf2zpk(1,S_lpc);
        % Obtain the zeros of the system by reciprocating the roots
        figure;
        zplane(lpcZeros,lpcRoots);   
    end
    
    %T_frame= (T_frame-mean(T_frame))/(std(T_frame));
    %T_frame = 2 * (T_frame - min(T_frame)) / (max(T_frame) - min(T_frame)) - 1;
    
    % 4.Synthesis
    
    %Selected CodeBook
    RX_noise = CB_noise(:,noise_idx);
    %RX_noise = sqrt(var(TX_frame)) * (RX_noise - mean(RX_noise)) / std(RX_noise) + mean(TX_frame);
   
   
    % Calculate the mean of the white Gaussian noise and the filtered output
    mean_wgn = mean(RX_noise);
    power_wgn = mean(RX_noise.^2);

    mean_real_noise = mean(TX_frame);
    power_real_noise = mean(TX_frame.^2);


    % Calculate the scaling factor to match the means
    scaling_factor = sqrt(power_real_noise / power_wgn);

    % Adjust the white Gaussian noise to match the mean and scaling
    RX_noise = scaling_factor * (RX_noise - mean_wgn) + mean_real_noise;

    
    %inverse short lpc
    S_lpc = Filter_Stabilizer(S_lpc);
    [RX_frame,Sx_final] = filter(1,S_lpc,RX_noise,Sx_initial);
    Sx_initial = Sx_final;
    
    if(Received == "voiced")
        L_lpc = Filter_Stabilizer(L_lpc);
        [RX_frame,Lx_final] = filter(1,L_lpc,RX_noise,Lx_initial);
        Lx_initial = Lx_final;
    end
    
    % Reconstruct the signal by overlapping and adding the frames
    startIdx = (i - 1) * hopSize + 1;
    endIdx = startIdx + Frame_size - 1;
    RX_data(startIdx:endIdx) = RX_data(startIdx:endIdx) + RX_frame;
    
    
end
sound(RX_data);
%apply low pass filter
%% low pass filter

% Assuming 'reconstructedSignal' contains the concatenated frames
<<<<<<< HEAD
=======

% Define the filter parameters
cutoffFreq = 2500; % Cutoff frequency in Hz
fs = 8000; % Sampling frequency in Hz
filterOrder = 12; % Filter order (adjust as needed)

% Design the Butterworth low-pass filter
[b, a] = butter(filterOrder, cutoffFreq/(fs/2), 'low');

% Apply the Butterworth filter to the signal
filteredSignal = filter(b, a, RX_data);
sound(filteredSignal)
%%

>>>>>>> 50af58b91cd40877bd010953c34226b760d09787

% Define the filter parameters
cutoffFreq = 3000; % Cutoff frequency in Hz
fs = 8000; % Sampling frequency in Hz
filterOrder = 12; % Filter order (adjust as needed)

% Design the Butterworth low-pass filter
[b, a] = butter(filterOrder, cutoffFreq/(fs/2), 'low');

% Apply the Butterworth filter to the signal
filteredSignal = filter(b, a, RX_data);
sound(filteredSignal)
