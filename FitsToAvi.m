function FitsToAvi
%This function makes avi movies out of the Fits fluorescence data
% for easier viewing of whole movie
% reduce filesize and playback speed by adjusting N_skip parameter.

%% startup
clc, clear all, close all
run('/nfs/matlabuser/matthiasschickinger/MATLAB/my_prefs.m')

%% choose colors
rgb={'red','green','blue'};
[colors]=listdlg('PromptString', 'Select the movie color(s)',...
                'ListString', rgb,...
                'OKString', 'Go');

channel = cell(length(colors),1);
for i = 1:size(channel,1)
	channel{i} = rgb{colors(i)};
end

%% enter movie parameters

pname=uigetdir(data_dir,'Choose the folder with all .fits files.');
files = cell(size(channel,1),1);
for ch = 1:size(channel,1)
    files{ch} = pickFirstFitsFiles(pname, channel{ch}); 
end

N_movie = length(files{1});

if size(channel,1) == 1
    input = {'First Frame:', 'Last Frame (-1=all):', ['Sequence ' channel{1} ':'],... % sample options
        'Framerate compression factor'};
    input_default = {'2', '-1', '1','10'};
elseif size(channel,1) == 2
    input = {'First Frame:', 'Last Frame (-1=all):', ['Sequence ' channel{1} ':'], ['Sequence ' channel{2} ':'],... % sample options
        'Framerate compression factor'};
    input_default = {'2', '-1', '01', '10','10'};
elseif size(channel,1) == 3
    input = {'First Frame:', 'Last Frame (-1=all):', ['Sequence ' channel{1} ':'], ['Sequence ' channel{2} ':'],... % sample options
        ['Sequence ' channel{3} ':'], 'Framerate compression factor'};
    input_default = {'2', '-1', '010', '100', '001', '10'};
end

tmp = inputdlg(input, 'Parameters', 1, input_default);
first = round(str2double(tmp(1))); % first image to read from file
last = round(str2double(tmp(2))); % last image to read from file
%determine sequences
sequences = cell(N_movie,size(channel,1));
for m = 1:N_movie
    for ch = 1:size(sequences,2)
    sequences{m,ch} = zeros(1, size(tmp{2+ch},2));
        for i=1:size(tmp{2+ch},2)
            if(tmp{2+ch}(i) == '1')
                sequences{m,ch}(1,i) = 1;
            end
        end
    end
end

N_skip = str2double(tmp(3+size(sequences,2))); % frame number compression factor
N_skip_string = ['_x' num2str(N_skip,'%02d')];

%% generate movie classes
movies = cell(N_movie,size(channel,1));

for m=1:N_movie
    for ch = 1:size(sequences,2)
        movies{m,ch} = movie(pname, files{ch}{m}, first, last, sequences{m,ch}); % pname, fname, first, last, sequence
    end
end

display('Data ready to go')
%{
 % Old code -- here the parameters are loaded from already existing movie
 % objects.
data_dir = '/nfs/matlabuser/matthiasschickinger/TIRFM_Data';
[DataFileName, DataPathName] = uigetfile('*.mat', 'Select the data file containing the movie objects', data_dir);
load([DataPathName DataFileName], 'ch1', 'ch2');
movies = [ch1 ch2];
display('data loaded and ready')
cd(DataPathName)
cd ..
%}
cd(pname)
path_out = uigetdir(cd, 'Select the directory the AVI movies will be written to');
cd(path_out)
%%
for m = 1:N_movie
    for ch = 1:size(sequences,2)
        N_frames = length(movies{m,ch}.frames);
        writerObj = VideoWriter([movies{m,ch}.fname{1}(1:end-5) N_skip_string '.avi']);
        open(writerObj)
        for i = 1:N_skip:N_frames
            tmp = movies{m,ch}.readFrame(movies{m,ch}.frames(i));
            tmp = scalematrix(tmp, 0, 1);
            tmp3 = zeros(512,512,3);
            for j = 1:3
            tmp3(:,:,j) = tmp;
            end
            writeVideo(writerObj, tmp3);
            %display(['Done writing ' num2str(i) ' of ' num2str(N_frames) ' frames in channel ' num2str(ch) ', movie #' num2str(m) ' of ' num2str(N_movies)])
        end
        close(writerObj)
        clear writerObj
        display([channel{ch} ' movie #' num2str(m) ' of ' num2str(N_movie) ' done.'])
    end
end
display('Done')
end