function [CB_noise, CB_size] = Codebook(Frame_size)
%_________________________________________________________________
% Codebook That generate codebook of white noise

% inputs :
    % TX_frame
    % Frame_size

% outputs :
    % CB_noise : it is coodbook noises
%_________________________________________________________________

CB_size = 1024;
CB_noise=zeros(Frame_size,CB_size);

for i=1:CB_size
    noise=wgn(10000,1,2e-5);
    CB_noise(:,i)= noise(length(noise)/2:length(noise)/2+Frame_size-1);
end

end

