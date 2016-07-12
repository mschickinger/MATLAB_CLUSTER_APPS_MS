
% What's new in version 13c?

% improved work-flow. e.g. plots of accepted / discarded spots are done at the
% very end, after batch job submission.
% possibility to pre-process on cluster (drift and itraces)
%% startup
clc, clear all, close all
path0 = cd;
run('/nfs/matlabuser/matthiasschickinger/MATLAB/my_prefs.m')


%% choose colors
rgb={'red','green','blue'};
[colors,ok]=listdlg('PromptString', 'Select two colors to be analyzed',...
                'ListString', rgb,...
                'OKString', 'Engage');
while ne(length(colors),2) && ok>0
    [colors,ok]=listdlg('PromptString', 'Select _TWO_ colors to be analyzed',...
                'ListString', rgb,...
                'OKString', 'Engage');
end

channel = cell(2,1);
channel{1} = rgb{colors(1)};
channel{2} = rgb{colors(2)};

[chb,ok]=listdlg('PromptString', 'Which one is surface-bound?',...
                'ListString', channel, 'SelectionMode', 'single',...
                'OKString', 'Confirm');           
channel_bound=rgb{chb};
if chb == 1
    chm = 2;
else
    chm = 1;
end

%% LOAD STACK OF MOVIES
pname=uigetdir(data_dir,'Choose the folder with all .fits files.');
files_ch1 = pickFirstFitsFiles(pname, channel{1}); 
files_ch2 = pickFirstFitsFiles(pname, channel{2});

N_movie = length(files_ch1);
if length(files_ch1) ~= length(files_ch2)
    disp('WARNING: not same number of movie files!')
end

path_out = [pname filesep datestr(now, 'yyyy-mm-dd_HH-MM') '_analysis'];
mkdir(path_out)

%% SET PARAMETER
button = questdlg('Assign parameters individually for each movie?');
options.Resize = 'off';
input = {'First Frame:', 'Last Frame (-1=all):', ['Sequence ' channel{1} ':'], ['Sequence ' channel{2} ':'],... % sample options
    'Radius of peak [pixel]:', 'Integration radius [pixel]:', 'Time per frame (in ms):',...
    'Average over first N_frames:'};
input_default = {'1', '-1', '1', '1', '4', '3', '50', '100'};

if button(1) == 'N'
tmp = inputdlg(input, 'All movies', 1, input_default, options);
end

first = ones(N_movie,1).*str2double(input_default{1});
last = ones(N_movie,1).*str2double(input_default{2});
time_per_frame = ones(N_movie,1).*str2double(input_default{7});
sequences = cell(N_movie,size(channel,1));
for m = 1:N_movie
    if button(1) == 'Y'
        tmp = inputdlg(input, ['Movie #' num2str(m)], 1, input_default, options);
    end
    first(m) = round(str2double(tmp(1))); % first image to read from file
    last(m) = round(str2double(tmp(2))); % last image to read from file
    time_per_frame(m) = str2double(tmp(7)); % time per frame used during acquisition
    %determine sequences
    for ch = 1:size(sequences,2)
    sequences{m,ch} = zeros(1, size(tmp{2+ch},2));
        for i=1:size(tmp{2+ch},2)
            if(tmp{2+ch}(i) == '1')
                sequences{m,ch}(1,i) = 1;
            end
        end
    end
end

r_find = str2double(tmp(5)); % radius used to find spots
r_integrate = str2double(tmp(6)); % radius used for integration of intensities
N_frames = str2double(tmp(8)); % in get_h_min, average over first N_frames is used

%% generate movie classes
ch1 = cell(N_movie,1);
ch2 = cell(N_movie,1);

for i=1:N_movie
    ch1{i} = movie(pname, files_ch1{i}, first(i), last(i), sequences{i,1}); % pname, fname, first, last, sequence
    ch2{i} = movie(pname, files_ch2{i}, first(i), last(i), sequences{i,2}); % pname, fname, first, last, sequence
end

%%
button = questdlg(['Map positions ' channel{1} ' ON ' channel{2} ' and vice versa?'],'Mapping','Yes','No','No');
mapping = strcmp(button, 'Yes');

if mapping
    [mapping_file_1TO2, mapping_dir]=uigetfile(pname,['Choose the ' channel{1} '2' channel{2} ' mapping file:']);
    map1TO2 =load([mapping_dir mapping_file_1TO2], 'tform');
    tform_1TO2 = map1TO2.tform;
    display(['loaded ' channel{1} ' TO ' channel{2} ' mapping file: ' mapping_dir mapping_file_1TO2]);
    
    [mapping_file_2TO1]=uigetfile(mapping_dir,['Choose the ' channel{2} '2' channel{1} ' mapping file:']);
    map2TO1=load([mapping_dir mapping_file_2TO1]);
    tform_2TO1 = map2TO1.tform; %['tform_' channel{2} 'ON' channel{1}];
    display(['loaded ' channel{2} ' TO ' channel{1} ' mapping file: ' mapping_dir mapping_file_2TO1]);
    
    tform = {tform_2TO1, tform_1TO2};
else
    tform = cell(2,1);
end

drift_cor = strcmp(questdlg('Perform drift correction?','Drift correction','Yes','No','Yes'),'Yes');
ParPrePro = strcmp(questdlg('Pre-process on cluster? (drift, itraces)','Parallel Pre-Processing','Yes','No','Yes'), 'Yes');

%% compute average images
avg_img = cell(N_movie, 4);

for i=1:N_movie
    avg_img{i, 1} = ch1{i}.average_image(N_frames);
    avg_img{i, 2} = ch2{i}.average_image(N_frames);
    avg_img{i, 3} = ch1{i}.average_image_last(N_frames); % for fitting threshold assignment, drift correction
    avg_img{i, 4} = ch2{i}.average_image_last(N_frames); % for fitting threshold assignment, drift correction
end

%% Parallel drift batch job (if activated)
if drift_cor
    interval = 100;
    if ParPrePro
        driftstat = 0; % keep track of job status on cluster
        mycluster = parcluster('SharedCluster');
        drift_job = custom_batch('matthiasschickinger', mycluster, @par_drift_ch2, 1 ...
        , {ch2, avg_img(:,2), interval, path_out},'CaptureDiary',true, 'CurrentDirectory', '.' ...
        , 'Pool', 63, 'AdditionalPaths', {[matlab_dir filesep 'TOOLBOX_MOVIE']});
    end
end

%% get threshold and find peaks from first N_frames

peaks_raw = zeros(0,5);

for i=1:N_movie 
    [ ~ , pos_ch1] = ch1{i}.get_h_min(r_find, N_frames, avg_img{i,1});
    [ ~ , pos_ch2] = ch2{i}.get_h_min(r_find, N_frames, avg_img{i,2});

    % map peaks
    trace_map = map_traces(pos_ch1(:,1:2), pos_ch2(:,1:2), pos_ch2(:,1:2), r_find*2)+1; %map the traces from average positions

    tmp = zeros(size(trace_map,1),5);
    
    % combine pairs
    for j=1:size(trace_map,1)
        tmp(j,:) = [pos_ch1(trace_map(j,1), 1:2)+1 pos_ch2(trace_map(j,2), 1:2)+1 i]; %x_1 y_1 x_2 y_2 frame
    end
    
    peaks_raw = [peaks_raw; tmp];
end

N_peaks_raw = size(peaks_raw,1);
display(['You have ' num2str(N_peaks_raw) ' pairs'])
close all

%% Fit psf to spots
s_x = 2.5;
s_y = 2.5;
w_fit = 8;

ch1_fit_raw = zeros(N_peaks_raw, 7); 
ch1_fit_err_raw = zeros(N_peaks_raw, 7);
ch2_fit_raw = zeros(N_peaks_raw, 7); 
ch2_fit_err_raw = zeros(N_peaks_raw, 7);

h = waitbar(0,'Fitting spots.. please wait');

for i=1:N_peaks_raw 
    
    % channel 1
    x1 = round(peaks_raw(i,1));
    y1 = round(peaks_raw(i,2));
    [c, c_err, ~, ~] = fit_gauss2d_mainaxis_bg(x1, y1, s_x, w_fit, avg_img{peaks_raw(i, 5),1});
    ch1_fit_raw(i,:) = c;
    ch1_fit_err_raw(i,:) = c_err;

    % channel 2
    x2 = round(peaks_raw(i,3));
    y2 = round(peaks_raw(i,4));
    [c, c_err, ~, ~] = fit_gauss2d_mainaxis_bg(x2, y2, s_x, w_fit, avg_img{peaks_raw(i, 5),2});
    ch2_fit_raw(i,:) = c;
    ch2_fit_err_raw(i,:) = c_err;
    
    waitbar( i/N_peaks_raw , h, ['Fitting spot... ' num2str(i) ' of ' num2str(N_peaks_raw) ' done']) % update waitbar
end

close(h)

%% SORT OUT: remove spots where ratio of width is not close to 1 and which are too large

criteria = ones(N_peaks_raw,2);

borderline = inputdlg('Enter value for st.dev. ratio cutoff:', 'Width ratio cutoff', [1 38], {'0.9'});
borderline = str2double(borderline{1});

if borderline <= 1
    std_borders = [borderline 1/borderline];
else
    std_borders = [1/borderline borderline];
end

switch chb
    case 1
        criteria(:,1:2) = filter_spots(ch1_fit_raw(:,3:4), std_borders, 2);
    case 2
        criteria(:,1:2) = filter_spots(ch2_fit_raw(:,3:4), std_borders, 2);
end

accepted = (criteria(:,1) & criteria(:,2));

%remove not-accepted spots
ch1_fit = ch1_fit_raw(accepted==1, :);
ch1_fit_err = ch1_fit_err_raw(accepted==1, :);
ch2_fit = ch2_fit_raw(accepted==1, :);
ch2_fit_err = ch2_fit_err_raw(accepted==1, :);
peaks = peaks_raw(accepted==1, :);
peaks = [ch1_fit(:,1:2) ch2_fit(:,1:2) peaks(:,5)]; % use fitted poistions for further analysis

plot_discarded = 1;
%plot_discarded = strcmp(questdlg('Plot discarded spots?','Plot discarded','Yes','No','No'), 'Yes');
if plot_discarded
    path_out_discarded = [path_out filesep 'discarded'];
    mkdir(path_out_discarded)
end

plot_accepted = 1;
%plot_accepted = strcmp(questdlg('Plot accepted spots?','Plot accepted','Yes','No','No'), 'Yes');
if plot_accepted
    path_out_accepted = [path_out filesep 'accepted'];
    mkdir(path_out_accepted)
end

display(['Accepted ' num2str(sum(accepted)) ' spots.'])
display(['Discarded ' num2str(sum(~accepted)) ' spots.'])
close all
N_peaks = size(peaks,1);

%% retrieve or calculate drift correction
if drift_cor
    if ParPrePro
        n = 0;
        while driftstat == 0
            display(['Waiting for drift_job to finish, T: ' num2str(n*10) ' sec...'])
            pause(10)
            if exist([path_out filesep 'tmp_drift.mat'], 'file')
                job_result = load([path_out filesep 'tmp_drift.mat']);
                drift_by_int = job_result.drift_by_int;
                delete([path_out filesep 'tmp_drift.mat']);
                driftstat = 1;
            end
            n = n+1;
        end
    else
        interval = 100;
        p = 49;
        q = 464;
        drift_by_int = cell(N_movie,1);
        H = fspecial('average', [11 11]);
        display('Calculating drift displacements.. please wait');
        % Go by intervals
        for m= 1:N_movie
            drift_by_int{m} = zeros(ceil(length(ch2{m}.frames)/interval),2);
            img_meanfilt = imfilter(avg_img{m,chb},H);
            avg_img_masked = zeros(size(avg_img{m,chb}));
            avg_img_masked(:) = avg_img{m,chb}(:).* ...
                (img_meanfilt(:)>(mean(nonzeros(img_meanfilt(:)))+std(nonzeros(img_meanfilt(:)))));
            for i = 1:size(drift_by_int{m},1)
                ai = zeros(ch2{m}.sizeY,ch2{m}.sizeX);
                for j = 1:min([interval length(ch2{m}.frames)-(i-1)*interval])
                    ai = ai + ch2{m}.readFrame(ch2{m}.frames((i-1)*interval+j));
                end
                ai = ai./interval;
                tmp = normxcorr2(ai(p:q,p:q), avg_img_masked(p:q,p:q));
                [v, ind] = max(tmp(:));
                [a, b] = ind2sub(size(tmp),ind);
                drift_by_int{m}(i,1) = 416-b;
                drift_by_int{m}(i,2) = 416-a;
            end
            display(['Movie #' num2str(m) ': Drift calculation done.'])
        end
    end
end
%% Show drift paths and certify last frame assignment
if drift_cor
    for m = 1:N_movie
        close all
        %old
        %{
        figure('Position', [scrsz(1) scrsz(4)/4 scrsz(3) scrsz(4)/2])
        subplot(1,3,1)
        hold off 
        plot(drift_by_int{m}(:,1),drift_by_int{m}(:,2), 'k-')
        hold on
        plot(drift_by_int{m}(:,1),drift_by_int{m}(:,2), 'k.', 'MarkerSize', 8)
        xlim([min(drift_by_int{m}(:,1))-1 max(drift_by_int{m}(:,1))+1])
        ylim([min(drift_by_int{m}(:,2))-1 max(drift_by_int{m}(:,2))+1])
        axis equal
        title(['Drift path for movie #' num2str(m)])
        subplot(1,3,2)
        imagesc(avg_img{m,chb}), axis image, colormap gray, title(['First ' num2str(N_frames) ' frames'])
        subplot(1,3,3)
        imagesc(avg_img{m,chb+2}), axis image, colormap gray, title(['Last ' num2str(N_frames) ' frames'])
        %}
        %new
        refresh = 1;
        reassign = 0;
        disp_final_avg = 1;
        tmp = size(ch1{m}.drift,1);
        tmp_int = size(drift_by_int{m},1);
        while refresh
            figure('Position', [1 1 1920 1080])
            % drift path (bird's view)
            subplot('Position', [0.025 0.35 0.3 0.6])
            hold off 
            plot(drift_by_int{m}(1:tmp_int,1),drift_by_int{m}(1:tmp_int,2), 'k-')
            hold on
            plot(drift_by_int{m}(1,1),drift_by_int{m}(1,2), 'x', 'MarkerSize', 20)
            plot(drift_by_int{m}(2:tmp_int,1),drift_by_int{m}(2:tmp_int,2), 'k.', 'MarkerSize', 15)
            xlim([min(drift_by_int{m}(1:tmp_int,1))-1 max(drift_by_int{m}(1:tmp_int,1))+1])
            ylim([min(drift_by_int{m}(1:tmp_int,2))-1 max(drift_by_int{m}(1:tmp_int,2))+1])
            axis equal
            title(['Drift path for movie #' num2str(m)])
            % start average image
            subplot('Position', [0.35 0.35 0.3 0.6])
            imagesc(avg_img{m,chb}), axis image, colormap gray, title(['First ' num2str(N_frames) ' frames'])
            % final average image
            if disp_final_avg
                subplot('Position', [0.675 0.35 0.3 0.6])
                imagesc(avg_img{m,chb+2}), axis image, colormap gray, title(['Last ' num2str(N_frames) ' frames'])
            end
            % total drift displacement over time
            subplot('Position', [0.025 0.05 0.95 0.25])
            plot(interval*(1:size(drift_by_int{m},1)),sqrt(drift_by_int{m}(:,1).^2+drift_by_int{m}(:,2).^2), 'k-')
            hold on
            plot([tmp tmp], ylim, '-')
            xlim([1 size(ch1{m}.drift,1)])
            title('total drift displacement over course of movie')
            xlabel('Frames'), ylabel('Pixels')
            check = questdlg('All OK?', 'Check drift', 'OK', 'Re-assign last', 'OK');
            if strcmp(check, 'Re-assign last')
                reassign = 1;
                %disp_final_avg = 0;
                h = impoint(gca);
                if size(h,1) == 0
                    break
                end
                tmp = getPosition(h);
                tmp = tmp(1);
                tmp_int = ceil(tmp/interval);
            else
                refresh = 0;
                if reassign
                    last(m) = tmp(1); 
                    ch1{m}.last = tmp;
                    ch1{m}.frames = ch1{m}.getFrames(ch1{m}.sequence, ch1{m}.first, ch1{m}.last);
                    ch2{m}.last = tmp;
                    ch2{m}.frames = ch2{m}.getFrames(ch2{m}.sequence, ch2{m}.first, ch2{m}.last);
                    avg_img{m,3} = ch1{m}.average_image_last(N_frames); % for fitting threshold assignment
                    avg_img{m,4} = ch2{m}.average_image_last(N_frames); % for fitting threshold assignment
                end
            end
            close(gcf)
        end
    end
end
%% Write drift array
if drift_cor
    for m = 1:N_movie
    ch1{m}.drift = zeros(length(ch1{m}.frames),2);
    for i = 1:length(ch1{m}.frames)
        ch1{m}.drift(i,:) = drift_by_int{m}(ceil(i/interval),:);
    end
    ch2{m}.drift = zeros(length(ch2{m}.frames),2);
    for i = 1:length(ch2{m}.frames)
        ch2{m}.drift(i,:) = drift_by_int{m}(ceil(i/interval),:);
    end
    end
end

%% Preparation for itraces

% pre-allocate merged_itraces
merged_itraces = cell(N_movie,2);
for i=1:N_movie
    for ch = 1:2
        merged_itraces{i,ch} = cell(sum(peaks(:,5)==i),1);
        for s = 1:size(merged_itraces{i,ch},1)
            merged_itraces{i,ch}{s} = zeros((ch==1)*length(ch1{i}.frames) + (ch==2)*length(ch2{i}.frames),5);
        end
    end
end

%% fill allocated containers with itraces and get fit_cutoff, if cluster pre-processing is enabled

display('Getting intensity traces... please wait')
if ParPrePro
    mycluster = parcluster('SharedCluster');
    intstat = 0; % keep track of cluster job
    itrace_job = custom_batch('matthiasschickinger', mycluster, @par_merged_itraces, 1 ...
    , {[ch1 ch2], peaks, r_integrate, path_out},'CaptureDiary',true, 'CurrentDirectory', '.' ...
    , 'Pool', 63,'AdditionalPaths', {[matlab_dir filesep 'TOOLBOX_GENERAL'], [matlab_dir filesep 'TOOLBOX_MOVIE'],...
    [matlab_dir filesep 'FM_applications'], [matlab_dir filesep 'DEVELOPMENT']});
    tic
    while intstat == 0
        display(['Waiting for itrace job to finish, T: ' datestr(toc/86400, 'HH:MM:SS')])
        pause(30)
        if exist([path_out filesep 'merged_itraces.mat'], 'file')
            display('taking a minute to load file: merged_itraces.mat')
            pause(60)
            job_result = load([path_out filesep 'merged_itraces.mat']);
            merged_itraces = job_result.merged_itraces;
            delete([path_out filesep 'merged_itraces.mat'])
            intstat = 1;
        end
    end
    display('Tracing done')
else
    for i = 1:N_movie
        tmp_itraces = ch1{i}.int_spots_in_frames(1:length(ch1{i}.frames), peaks(peaks(:,5)==i,1:2), r_integrate);
        % add median filtered itraces
        for j=1:length(tmp_itraces)
            tmp_itraces{j} = [tmp_itraces{j} medfilt1(tmp_itraces{j}(:,4),20)];
        end
        % transfer to merged_itraces
        merged_itraces{i,1} = tmp_itraces;
        display(['Tracing ' channel{1} ' channel in movie #' num2str(i) ' done'])       
        tmp_itraces = ch2{i}.int_spots_in_frames(1:length(ch2{i}.frames), peaks(peaks(:,5)==i,3:4), r_integrate);
        % add median filtered itraces
        for j=1:length(tmp_itraces)
            tmp_itraces{j} = [tmp_itraces{j} medfilt1(tmp_itraces{j}(:,4),20)];
        end
        % transfer to merged_itraces
        merged_itraces{i,2} = tmp_itraces;
        display(['Tracing ' channel{2} ' channel in movie #' num2str(i) ' done'])
    end
end

%% Determine fitting parameters
cut = questdlg('Intensity threshold or maximum frame?','Cutoff method','Intensity','Frame','Frame');
cut = strcmp(cut, 'Frame') + 1;
fit_cutoff = cell(N_movie,2);
for i = 1:N_movie
    ch = 1;

    fit_cutoff{i,ch} = get_fit_cutoff(ch1{i}, cut, merged_itraces{i,ch}, avg_img(i,[ch ch+2]), ...
                                        channel{ch}, N_movie, i, r_integrate);                        
    ch = 2;
    fit_cutoff{i,ch} = get_fit_cutoff(ch2{i}, cut, merged_itraces{i,ch}, avg_img(i,[ch ch+2]), ...
                                        channel{ch}, N_movie, i, r_integrate);
end
close all

%% Pos in frame cell array 

%pos_in_frame: cell of arrays that for each frame gives starting fit
%coordinates for all spots in respective channel. If both parameters
%return zero, spot is not fitted in that frame.

pos_in_frame = cell(N_movie,2);
for m = 1:N_movie
    % channel 1
    pos_in_frame{m,1} = cell(size(ch1{m}.frames,2),1);
    for j = 1:size(pos_in_frame{m,1},1)
        pos_in_frame{m,1}{j} = zeros(size(merged_itraces{m,1},1),2);
        for s=1:size(pos_in_frame{m,1}{j},1)
            if cut(1) == 'I'
                pos_in_frame{m,1}{j}(s,1:2) = (merged_itraces{m,1}{s}(j,5)>=fit_cutoff{m,1}(s))*merged_itraces{m,1}{s}(j,2:3); % x_0, y_0 remain zero if intensity is below threshold
            else
                pos_in_frame{m,1}{j}(s,1:2) = (j<=fit_cutoff{m,1}(s))*merged_itraces{m,1}{s}(j,2:3); % x_0, y_0 remain zero if frame is above maximum frame
            end
        end
    end

    % channel 2
    pos_in_frame{m,2} = cell(size(ch2{m}.frames,2),1);
    for j = 1:size(pos_in_frame{m,2},1)
        pos_in_frame{m,2}{j} = zeros(size(merged_itraces{m,2},1),2);
        for s=1:size(pos_in_frame{m,2}{j},1)
            if cut(1) == 'I'
                pos_in_frame{m,2}{j}(s,1:2) = (merged_itraces{m,2}{s}(j,5)>=fit_cutoff{m,2}(s))*merged_itraces{m,2}{s}(j,2:3); % x_0, y_0 remain zero if intensity is below threshold
            else
                pos_in_frame{m,2}{j}(s,1:2) = (j<=fit_cutoff{m,2}(s))*merged_itraces{m,2}{s}(j,2:3); % x_0, y_0 remain zero if frame is above maximum frame
            end
        end
    end
end

%% Save all relevant data; prepare for batch job assignment
data = cell(N_movie,1);
cd(path_out)
for m=1:N_movie %loop through movies
    data{m} = cell(size(merged_itraces{m,1},1),2);
        for s=1:size(data{m},1)
            for ch = 1:2
                data{m}{s,ch}.pos0 = merged_itraces{m,ch}{s}(:,2:3);
                data{m}{s,ch}.itrace = merged_itraces{m,ch}{s}(:,4);
                data{m}{s,ch}.med_itrace = merged_itraces{m,ch}{s}(:,5);
            end
        end
end
% file that the position data from gF and vwcm estimators will be added to
save -v7.3 'data_spot_pairs.mat' 'data' 'path_out'

% data needed for processing (batch jobs and later)
save -v7.3 'data_proc.mat' 'pos_in_frame' 'time_per_frame' 'tform' 'mapping'

% movie objects
save -v7.3 'movie_objects.mat' 'ch1' 'ch2'

% stuff that might be useful for plotting figures
save 'data_plot.mat' 'channel' 'cut' 'fit_cutoff' 'chb' 'chm'

% for archiving purposes
save -v7.3 'data_archive.mat' 'avg_img' 'N_frames' 'r_find' 'r_integrate' 'peaks' 'peaks_raw' 'ch1_fit_raw' 'ch2_fit_raw'

%% start position estimator batch job
mycluster=parcluster('SharedCluster');
ask_pos = questdlg('Perform vwcm AND gF estimation?', 'To gauss or not to gauss?', 'yes, both', 'no, vwcm only', 'yes, both');
if strcmp(ask_pos, 'yes, both') 
    pos_job = custom_batch('matthiasschickinger', mycluster, @par_pos_v1, 1, {path_out} ...
    ,'CaptureDiary',true, 'CurrentDirectory', '.', 'Pool', 63 ...
    ,'AdditionalPaths', {[matlab_dir filesep 'TOOLBOX_GENERAL'], [matlab_dir filesep 'TOOLBOX_MOVIE'],...
    [matlab_dir filesep 'FM_applications'], [matlab_dir filesep 'FM_applications' filesep 'CLUSTER_APPLICATIONS'], [matlab_dir filesep 'DEVELOPMENT']});
elseif strcmp(ask_pos, 'no, vwcm only')
    pos_job = custom_batch('matthiasschickinger', mycluster, @par_vwcm, 1, {path_out} ...
    ,'CaptureDiary',true, 'CurrentDirectory', '.', 'Pool', 63 ...
    ,'AdditionalPaths', {[matlab_dir filesep 'TOOLBOX_GENERAL'], [matlab_dir filesep 'TOOLBOX_MOVIE'],...
    [matlab_dir filesep 'FM_applications' filesep 'CLUSTER_APPLICATIONS'], [matlab_dir filesep 'DEVELOPMENT']});
end

%% plot accepted and discarded spots in bound channel
close all
fig_dim =1*[20 10];
cur_fig = figure('Visible','off', 'PaperPositionMode', 'manual','PaperUnits','centimeters','PaperPosition', [0 0 fig_dim(1) fig_dim(2)], 'Position', [0 scrsz(4) fig_dim(1)*40 fig_dim(2)*40]);
colormap gray
w_plot = 10;

if plot_discarded
    display('Plotting discarded spots...')
    if chb == 1
    for i=1:N_peaks_raw
        if ~accepted(i) % discarded spot
            message = {['Sigma ratio ' channel_bound ' OK: ' num2str(ch1_fit_raw(i,3)./ch1_fit_raw(i,4))],...
                ['Spotsize ' channel_bound ' OK: ' num2str(sqrt(ch1_fit_raw(i,3).^2+ch1_fit_raw(i,4).^2))]};
            if criteria(i,1)==0
                message{1} = ['Sigma ratio ' channel_bound ' BAD: ' num2str(ch1_fit_raw(i,3)./ch1_fit_raw(i,4))];
            end
            if criteria(i,2)==0
                message{2} = ['Spotsize ' channel_bound 'BAD: ' num2str(sqrt(ch1_fit_raw(i,3).^2+ch1_fit_raw(i,4).^2))];
            end
           
            x_1 = ch1_fit_raw(i,1);
            y_1 = ch1_fit_raw(i,2);

            plot_subframe(avg_img{peaks_raw(i, 5), 1}, x_1, y_1, w_plot), hold on
            plot(x_1, y_1, 'g.')
            ellipse(ch1_fit_raw(i,3), ch1_fit_raw(i,4), -ch1_fit_raw(i,5), x_1, y_1, channel{1});
            title({['Pair ' num2str(i) ' of '  num2str(N_peaks_raw) ' at (' num2str(round(x_1)) ',' num2str(round(y_1)) ') in ' channel_bound ' channel'], message{1},message{2}})
            axis square
            hold off

            print(cur_fig, '-dpng', '-r96',  [path_out_discarded filesep 'Discarded_' num2str(i) '.png'])
        end 
    end
    elseif chb == 2
    for i=1:N_peaks_raw
        if ~accepted(i) % discarded spot
            message = {['Sigma ratio ' channel_bound ' OK: ' num2str(ch2_fit_raw(i,3)./ch2_fit_raw(i,4))],...
                ['Spotsize ' channel_bound ' OK: ' num2str(sqrt(ch2_fit_raw(i,3).^2+ch2_fit_raw(i,4).^2))]};
            if criteria(i,1)==0
                message{1} = ['Sigma ratio ' channel_bound ' BAD: ' num2str(ch2_fit_raw(i,3)./ch2_fit_raw(i,4))];
            end
            if criteria(i,2)==0
                message{2} = ['Spotsize ' channel_bound 'BAD: ' num2str(sqrt(ch2_fit_raw(i,3).^2+ch2_fit_raw(i,4).^2))];
            end
           
            x_1 = ch2_fit_raw(i,1);
            y_1 = ch2_fit_raw(i,2);

            plot_subframe(avg_img{peaks_raw(i, 5), 2}, x_1, y_1, w_plot), hold on
            plot(x_1, y_1, 'g.')
            ellipse(ch2_fit_raw(i,3), ch2_fit_raw(i,4), -ch2_fit_raw(i,5), x_1, y_1, channel{2});
            title({['Pair ' num2str(i) ' of '  num2str(N_peaks_raw) ' at (' num2str(round(x_1)) ',' num2str(round(y_1)) ') in ' channel_bound ' channel'], message{1},message{2}})
            axis square
            hold off

            print(cur_fig, '-dpng', '-r96',  [path_out_discarded filesep 'Discarded_' num2str(i) '.png'])
        end 
    end
    end
end

if plot_accepted
    display('Plotting accepted spots...')
    if chb == 1
    for i=1:N_peaks_raw
        if  accepted(i) % discarded spot
            message = {['Sigma ratio ' channel_bound ' OK: ' num2str(ch1_fit_raw(i,3)./ch1_fit_raw(i,4))],...
                ['Spotsize ' channel_bound ' OK: ' num2str(sqrt(ch1_fit_raw(i,3).^2+ch1_fit_raw(i,4).^2))]};
           
            x_1 = ch1_fit_raw(i,1);
            y_1 = ch1_fit_raw(i,2);

            plot_subframe(avg_img{peaks_raw(i, 5), 1}, x_1, y_1, w_plot), hold on
            plot(x_1, y_1, 'g.')
            ellipse(ch1_fit_raw(i,3), ch1_fit_raw(i,4), -ch1_fit_raw(i,5), x_1, y_1, channel{1});
            title({['Pair ' num2str(i) ' of '  num2str(N_peaks_raw) ' at (' num2str(round(x_1)) ',' num2str(round(y_1)) ') in ' channel_bound ' channel'], message{1},message{2}})
            axis square
            hold off

            print(cur_fig, '-dpng', '-r96',  [path_out_accepted filesep 'Accepted_' num2str(i) '.png'])
        end 
    end
    elseif chb == 2
    for i=1:N_peaks_raw
        if  accepted(i) % discarded spot
            message = {['Sigma ratio ' channel_bound ' OK: ' num2str(ch2_fit_raw(i,3)./ch2_fit_raw(i,4))],...
                ['Spotsize ' channel_bound ' OK: ' num2str(sqrt(ch2_fit_raw(i,3).^2+ch2_fit_raw(i,4).^2))]};
           
            x_1 = ch2_fit_raw(i,1);
            y_1 = ch2_fit_raw(i,2);

            plot_subframe(avg_img{peaks_raw(i, 5), 2}, x_1, y_1, w_plot), hold on
            plot(x_1, y_1, 'g.')
            ellipse(ch2_fit_raw(i,3), ch2_fit_raw(i,4), -ch2_fit_raw(i,5), x_1, y_1, channel{2});
            title({['Pair ' num2str(i) ' of '  num2str(N_peaks_raw) ' at (' num2str(round(x_1)) ',' num2str(round(y_1)) ') in ' channel_bound ' channel'], message{1},message{2}})
            axis square
            hold off

            print(cur_fig, '-dpng', '-r96',  [path_out_accepted filesep 'Accepted_' num2str(i) '.png'])
        end 
    end
    end
end

disp('Done plotting.')
% End of program
disp('End of program.')