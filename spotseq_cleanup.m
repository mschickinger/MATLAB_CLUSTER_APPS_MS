% Cleans up spotseq folders with .png sequences, leaves .zip archives

clear GiTSiK
load('GiTSiK.mat')

stem = (['spotseq_' GiTSiK.date{1}([3 4 6 7 9 10]) '_' GiTSiK.sample{1} '_m']);

for m = 1:size(GiTSiK.behaviour,1)
    display(['Starting cleanup for movie #' num2str(m)])
    for s = find(GiTSiK.behaviour{m}==2)'
        if exist([stem num2str(m) 's' num2str(s)],'file')
            if exist([stem num2str(m) 's' num2str(s) '.zip'],'file')
                cd([stem num2str(m) 's' num2str(s)])
                delete('*.png')
                cd ..
                rmdir([stem num2str(m) 's' num2str(s)])
                display(['movie #' num2str(m) ', spot #' num2str(s) ': done.'])
            end
        end 
    end    
end
display('all done.')