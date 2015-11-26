function [ data, fit_output, vwcm_output ] = par_pos_v1(data_path)
% Parallel particle tracking function for two-channel movie objects
% gFit and VWCM position estimation + first processing steps (mapping,
% averaging, rms filtering...)
% result is stored in 'data' struct and saved to disk

%% Load data
tic
cd(data_path)
load('data_proc.mat', 'pos_in_frame', 'mapping');
mapping = mapping;
if mapping == 1
    load('data_proc.mat', 'tform');
else
    tform = cell(2,1);
end
load('data_spot_pairs.mat', 'data');
load('movie_objects.mat', 'ch1', 'ch2');

%% Create log file
FID = fopen([data_path filesep 'par_pos_log.txt'], 'w');
log_string = 'Data loaded. Starting position estimation. Time elapsed is ';
fprintf(FID, [datestr(now, 'yyyy-mm-dd, HH:MM') ', status:' '\n']);
fprintf(FID, [log_string datestr(toc/86400, 'HH:MM:SS.') '\n']);
fclose(FID);

%% Gaussian fit part

log_string = 'gF in movie %1d of %1d done. Time elapsed is ';
N_movie = size(ch1,1);
fit_output = cell(size(ch1));
for m=1:size(fit_output,1)
    fit_output{m}=cell(size(pos_in_frame{m,1}{1},1),2);
    for j = 1:size(fit_output{m},1)
        fit_output{m}{j,1} = zeros(length(ch1{m}.frames),7);
        fit_output{m}{j,2} = zeros(length(ch2{m}.frames),7);
    end
end

for m = 1:size(ch1,1)
    tmp_pos_ch1 = pos_in_frame{m,1};
    tmp_pos_ch2 = pos_in_frame{m,2};
    % channel 1
    tmp_fit_output = cell(length(ch1{m}.frames),1);
    for n = 1:size(tmp_fit_output,1)
        tmp_fit_output{n} = zeros(size(pos_in_frame{m,1}{n},1),6);
    end
    parfor p=1:length(ch1{m}.frames)
        tmp = ch1{m}.fit_sym_psfs_to_frame(ch1{m}.frames(p), tmp_pos_ch1{p}, 2); %fit all spots that occur in this frame, sigma = 2
        for j=1:size(tmp,1)
            tmp_fit_output{p}(j,1) = tmp(j,1);
            tmp_fit_output{p}(j,2) = tmp(j,2);
            tmp_fit_output{p}(j,3) = tmp(j,3);
            tmp_fit_output{p}(j,4) = tmp(j,4);
            tmp_fit_output{p}(j,5) = tmp(j,5);
            tmp_fit_output{p}(j,6) = tmp(j,6);
        end
    end
    %write fit loop data to fit_result cell
    for j=1:size(pos_in_frame{m,1}{1},1)
        for i=1:size(tmp_fit_output,1)
            fit_output{m}{j,1}(i,1:3) = tmp_fit_output{i}(j,1:3);
            fit_output{m}{j,1}(i,5:7) = tmp_fit_output{i}(j,4:6);
        end
        fit_output{m}{j,1}(:,4) = fit_output{m}{j,1}(:,3);
    end
    
    % channel 2
    tmp_fit_output = cell(length(ch2{m}.frames),1);
    for n = 1:size(tmp_fit_output,1)
        tmp_fit_output{n} = zeros(size(pos_in_frame{m,2}{n},1),6);
    end
    parfor p = 1:length(ch2{m}.frames);
        tmp = ch2{m}.fit_sym_psfs_to_frame(ch2{m}.frames(p), tmp_pos_ch2{p}, 2); %fit spot in each frame, sigma = 2
        for j=1:size(tmp,1);
            tmp_fit_output{p}(j,1) = tmp(j,1);
            tmp_fit_output{p}(j,2) = tmp(j,2);
            tmp_fit_output{p}(j,3) = tmp(j,3);
            tmp_fit_output{p}(j,4) = tmp(j,4);
            tmp_fit_output{p}(j,5) = tmp(j,5);
            tmp_fit_output{p}(j,6) = tmp(j,6);
        end
    end
    %write fit loop data to fit_result cell
    for j=1:size(pos_in_frame{m,2}{1},1)
        for i=1:size(tmp_fit_output,1)
            fit_output{m}{j,2}(i,1:3) = tmp_fit_output{i}(j,1:3);
            fit_output{m}{j,2}(i,5:7) = tmp_fit_output{i}(j,4:6);
        end
        fit_output{m}{j,2}(:,4) = fit_output{m}{j,2}(:,3);
    end
    FID = fopen('par_pos_log.txt', 'a');
    fprintf(FID, [datestr(now, 'yyyy-mm-dd, HH:MM') ', status:' '\n']);
    fprintf(FID, [log_string datestr(toc/86400, 'HH:MM:SS.') '\n'], m, N_movie);
    fclose(FID);
end

%% VWCM estimator part

log_string = 'VWCM in movie %1d of %1d done. Time elapsed is ';
vwcm_output = cell(size(ch1));
for m=1:size(ch1,1)
    vwcm_output{m} = cell(size(pos_in_frame{m,1}{1},1),2);
    vwcm_output{m}(:,1) = chunky_par_vwcm(ch1{m}, pos_in_frame{m,1}, 100);
    vwcm_output{m}(:,2) = chunky_par_vwcm(ch2{m}, pos_in_frame{m,2}, 100);
    FID = fopen('par_pos_log.txt', 'a');
    fprintf(FID, [datestr(now, 'yyyy-mm-dd, HH:MM') ', status:' '\n']);
    fprintf(FID, [log_string datestr(toc/86400, 'HH:MM:SS.') '\n'], m, N_movie);
    fclose(FID);
end

cd(data_path)
save -v7.3 'pos_outputs.mat' 'fit_output' 'vwcm_output'

%% Output structure part

for m = 1:size(data,1)
    tmp = data{m};
    tmp_fit_output = fit_output{m};
    tmp_vwcm_output = vwcm_output{m};
    parfor s = 1:size(data{m},1)
        for c = 1:2
            % get data from gaussian fit
            tmp{s,c}.gF.pos = tmp_fit_output{s,c}(:,1:2);
            tmp{s,c}.gF.sigmaX = tmp_fit_output{s,c}(:,3);
            tmp{s,c}.gF.sigmaY = tmp_fit_output{s,c}(:,4);
            tmp{s,c}.gF.A_bg_corr = tmp_fit_output{s,c}(:,5);
            tmp{s,c}.gF.bg = tmp_fit_output{s,c}(:,6);
            tmp{s,c}.gF.chi2 = tmp_fit_output{s,c}(:,7);
            
            % get data from vwcm estimate
            tmp{s,c}.vwcm.pos = tmp_vwcm_output{s,c}(:,1:2);
            tmp{s,c}.vwcm.delta = tmp_vwcm_output{s,c}(:,3);
            tmp{s,c}.vwcm.N = tmp_vwcm_output{s,c}(:,4);
            tmp{s,c}.vwcm.pos_max = tmp_vwcm_output{s,c}(:,5:6);
            tmp{s,c}.vwcm.v_max = tmp_vwcm_output{s,c}(:,7);
            tmp{s,c}.vwcm.stDev = tmp_vwcm_output{s,c}(:,8);
            
            % complete datasets
            tmp{s,c}.gF.means100 = running_avg_2d_nnz(tmp{s,c}.gF.pos,100);
            tmp{s,c}.gF.means500 = running_avg_2d_nnz(tmp{s,c}.gF.pos,500);
            tmp{s,c}.vwcm.means100 = running_avg_2d_nnz(tmp{s,c}.vwcm.pos,100);
            tmp{s,c}.vwcm.means500 = running_avg_2d_nnz(tmp{s,c}.vwcm.pos,500);
            
            tmp{s,c}.gF.disp100 = tmp{s,c}.gF.pos - tmp{s,c}.gF.means100;
            tmp{s,c}.gF.disp500 = tmp{s,c}.gF.pos - tmp{s,c}.gF.means500;
            tmp{s,c}.vwcm.disp100 = tmp{s,c}.vwcm.pos - tmp{s,c}.vwcm.means100;
            tmp{s,c}.vwcm.disp500 = tmp{s,c}.vwcm.pos - tmp{s,c}.vwcm.means500;
            
            tmp{s,c}.gF.r = sqrt(tmp{s,c}.gF.disp100(:,1).^2+tmp{s,c}.gF.disp100(:,2).^2);
            % no radius calculation for 500 frame window so far
            tmp{s,c}.vwcm.r = sqrt(tmp{s,c}.vwcm.disp100(:,1).^2+tmp{s,c}.vwcm.disp100(:,2).^2);
            % no radius calculation for 500 frame window so far

            tmp{s,c}.gF.rms10 = RMSfilt2d(tmp{s,c}.gF.pos,10);
            % no rms calculation for 500 frame window so far
            tmp{s,c}.vwcm.rms10 = RMSfilt2d(tmp{s,c}.vwcm.pos,10);
            % no rms calculation for 500 frame window so far       
            
            % mapping
            if mapping
            tmp{s,c}.vwcm.pos_map = zeros(size(tmp{s,c}.vwcm.pos));
            tmp{s,c}.gF.pos_map = zeros(size(tmp{s,c}.gF.pos));  
            for i = 1:size(tmp{s,c}.vwcm.pos_map,1)
            if sum(tmp{s,c}.vwcm.pos(i,:)) > 0
                tmp{s,c}.vwcm.pos_map(i,:) = transformPointsInverse(tform{c}, tmp{s,c}.vwcm.pos(i,:));  %%this takes coords in ch2 and transforms them to coords in ch1
            end
            end
            for i = 1:size(tmp{s,c}.gF.pos_map,1)
            if sum(tmp{s,c}.gF.pos(i,:)) > 0
                tmp{s,c}.gF.pos_map(i,:) = transformPointsInverse(tform{c}, tmp{s,c}.gF.pos(i,:));
            end
            end
            end
        end
    end
    data{m} = tmp;
    display(['Movie #' num2str(m) ' done.'])
end

log_string = 'Data structuring done. Saving data. Time elapsed is ';
FID = fopen('par_pos_log.txt', 'a');
fprintf(FID, [datestr(now, 'yyyy-mm-dd, HH:MM') ', status:' '\n']);
fprintf(FID, [log_string datestr(toc/86400, 'HH:MM:SS.') '\n']);
fclose(FID);

%% Save data
cd(data_path)
save -v7.3 'data_spot_pairs.mat' 'data'

end

