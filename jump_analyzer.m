%% STARTUP
clc, clear all, close all
path0 = cd;
run('my_prefs')

%% load movie object
cd(data_dir)
[fname, pname]=uigetfile('*.mat','Select a movie object file (*.mat) .');
cd(pname)
load(fname,'ch2');
%tmp = inputdlg({'Enter movie index'});
%idx = str2double(tmp{1});
jumps = cell(size(ch2));
jump_intervals = cell(size(ch2));
corr_traces = cell(size(ch2));
%%
for idx = 1:length(ch2)
    mov = ch2{idx};
    
    %% Display drift path
    figure('Units', 'normalized', 'Position', [0 0.5 1 .5])
    driff = [0;diff(sqrt(mov.drift(:,1).^2+mov.drift(:,2).^2))];
    plot(driff)

    %% Find intervals 
    tmp = find(abs(driff)>2);
    jump_intervals{idx} = [tmp-100 tmp+99];

    %% Set parameters
    mov.N_read = 200;
    corr_traces{idx} = cell(size(jump_intervals{idx},1),1);
    %% Load frames and compute xcorrelation
    for i = 1:size(jump_intervals{idx},1)
        display(['Finding jump in interval ' num2str(i) ' of ' num2str(size(jump_intervals{idx},1))])

        mov.counter = jump_intervals{idx}(i,1);
        [cur_mov, frames, go_on]  = mov.readNext;
        cur_mov = cur_mov(49:464,49:464,:);
        corr_traces{idx}{i} = zeros(size(cur_mov,3),4);

        first_img = cur_mov(:,:,1);
        prev_img = first_img;

        h = waitbar(0, 'Calculating xcorrelation... ');

        for n=1:size(cur_mov,3)

            tmp = normxcorr2(cur_mov(:,:,n), first_img);

            [v,ind]=max(tmp(:));
            [corr_traces{idx}{i}(n,2), corr_traces{idx}{i}(n,3)] = ind2sub(size(tmp),ind);
            corr_traces{idx}{i}(n,1) = v;
            corr_traces{idx}{i}(n,4) = corr2(cur_mov(:,:,n), prev_img);
            prev_img = cur_mov(:,:,n);

            waitbar( n/size(cur_mov,3), h, ['Calculating xcorrelation... ' num2str(n) ' of ' num2str(size(cur_mov,3)) ' done']) % update waitbar

        end
        close(h)
        for j = 2:3
            corr_traces{idx}{i}(:,j) = corr_traces{idx}{i}(:,j) - corr_traces{idx}{i}(1,j);
        end
    end

    %% Locate jumps
    jumps{idx} = zeros(size(jump_intervals{idx},1),1);
    for i = 1:size(jump_intervals{idx},1)
        [~, ind] = min(corr_traces{idx}{i}(:,4));
        jumps{idx}(i) = jump_intervals{idx}(i,1) + ind -1;
    end
end
%% plot dx and dy against frames
close all
cur_fig = figure('Units', 'normalized', 'Position', [0 0 1 1]);
for idx = 1:length(jumps)
    for i = 1:length(jumps{idx})
        subplot(2,1,1)
        hold off
        plot(jump_intervals{idx}(i,1):jump_intervals{idx}(i,2), corr_traces{idx}{i}(:,1), 'k', 'Linewidth', 1)
        hold on
        plot(jump_intervals{idx}(i,1):jump_intervals{idx}(i,2), corr_traces{idx}{i}(:,4), 'r', 'Linewidth', 1)
        plot(jumps{idx}(i), corr_traces{idx}{i}(jumps{idx}(i)-jump_intervals{idx}(i,1)+1,4), 'bo', 'Linewidth', 1)
        xlabel('Frame'), ylabel('Correlation Coefficient')
        set(gca, 'YLim', [0 1])
        title(['Jump number ' num2str(i) ' out of ' num2str(length(jumps{idx}))],'FontSize', 14)

        subplot(2, 1, 2)
        plot(jump_intervals{idx}(i,1):jump_intervals{idx}(i,2), corr_traces{idx}{i}(:,2), 'g', jump_intervals{idx}(i,1):jump_intervals{idx}(i,2), corr_traces{idx}{i}(:,3), 'b', 'Linewidth', 1)
        legend({'deltaX', 'deltaY'})
        xlabel('Frame'), ylabel('Dirift [pixel]')
        YLIM = get(gca, 'Ylim');
        set(gca,'Ylim', YLIM + [-1 1])
        pause
    end
end
%% save data
close all
save jumps.mat jumps
disp('Done.')