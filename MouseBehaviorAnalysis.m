function MouseBehaviorAnalysis()
%% Open-field mouse tracking and analysis
% MOUSEBEHAVIORANALYSIS Track mice in separate, manually defined arenas.
%   Run MouseBehaviorAnalysis and follow the interactive prompts to select
%   a video, segmentation settings, analysis zones and arena rectangles.
%
%   Outputs include image coordinates, stepwise and cumulative distance,
%   zone occupancy, body-shape measurements, summary figures and an optional
%   tracking-check movie. Image coordinates and shape lengths are in pixels;
%   calibrated path length is in mm, cumulative distance in m, and time in s.

%   See README.md for dependencies and THIRD_PARTY_NOTICES.md for provenance.

%% Initialize the interactive session

clc; % Clear the Command Window.
close all; % Close all open figures.
clear; % Clear variables in the current function workspace.

%% User settings
% Configure the default analysis and display settings in this block.
% Arena calibration:
%   Physical side length (mm) represented by each manually drawn arena ROI.
settings.arenaSizeMm = 400;          % Open-field arena side length in mm.
% Center zone:
%   Define the centre by its inward distance (mm) from each arena wall.
%   Example: a 400 mm arena with a 100 mm margin has a 200 x 200 mm centre.
settings.centerMarginMm = 100;        % Margin from each wall to the center zone in mm.
% Optional corner/object zones:
%   Dimensions and wall offsets for optional upper-right/lower-left zones.
settings.cornerZoneSizeMm = 100;     % Optional corner/object zone size in mm.
settings.cornerZoneMarginMm = 50;    % Optional corner/object zone margin from wall in mm.
% Analysis zones:
%   Zones can also be configured interactively at runtime.
%   X/Y are in mm relative to the upper-left corner of the arena ROI.
%   Width/Height are in mm. Between zero and four zones can be specified.
%   Zero zones disables zone summaries and dashed zone outlines.
settings.analysisZones = struct( ...
    'name', {'Center'}, ...
    'xMm', {settings.centerMarginMm}, ...
    'yMm', {settings.centerMarginMm}, ...
    'widthMm', {settings.arenaSizeMm - settings.centerMarginMm * 2}, ...
    'heightMm', {settings.arenaSizeMm - settings.centerMarginMm * 2});
% Tracking check movie:
%   Default number of sampled frames included in the tracking-check movie.
%   The final source-frame index can also be selected at runtime.
settings.previewMaxFrames = 900;     % Default maximum frames in the tracking-check movie. Use Inf for all analyzed frames.
settings.thresholdStep = 0.05;       % Threshold display increment.
settings.thresholdPanelCount = 5;    % Number of threshold candidates shown at once.
settings.uiFontSize = 16;            % Base font size for selection dialogs and threshold preview labels.
settings.uiTitleFontSize = 18;       % Dialog title font size.
settings.uiBodyFontSize = 14;        % Labels, edit boxes, and normal button font size.
settings.uiSmallFontSize = 12;       % Small helper button font size.
settings.trackColors = {'#0072BD', '#D95319', '#77AC30', '#7E2F8E', '#EDB120'}; % Mouse trajectory colors as hex color codes.
settings.trackLineWidth = 2;         % Trajectory line width in tracking-check movie and summary plot.

setDefaultUiFonts(settings);

    [filename, dirpath] = uigetfile('*.mov;*.wmv;*.mp4;*.avi','Open video');
    
    if isequal(filename, 0) || isequal(dirpath, 0)
        logf('Cancel opening video');
        return;
    end
    
    filepath = fullfile(dirpath, filename);
    
    [u1, video_name, u2] = fileparts(filepath);
                
    result_name = [video_name '_result.mat'];
    outputDir = fullfile(dirpath, video_name);
    resultpath = fullfile(outputDir, result_name);
            
if exist(resultpath, 'file') ~= 2
 
    logf('Opening the video: %s', filepath);

    useFrameFolder = false;
    useMjpegDirect = false;
    frameFolder = '';
    frameFiles = [];
    mjpegSource = [];
    video_obj = [];

    if isAviMjpegFile(filepath)
        mjpegSource = openAviMjpegSource(filepath);
        useMjpegDirect = ~isempty(mjpegSource.offsets);
    end

    if useMjpegDirect
        nframes = numel(mjpegSource.offsets);
        frameRate = mjpegSource.frameRate;
        duration = nframes / frameRate;
        firstFrame = readFrameFromSource(useFrameFolder, frameFolder, frameFiles, video_obj, 1, useMjpegDirect, mjpegSource);
        videosize = [size(firstFrame, 2), size(firstFrame, 1)];
        previewFrame = min(max(1, round(nframes / 10)), nframes);
        frame100 = readFrameFromSource(useFrameFolder, frameFolder, frameFiles, video_obj, previewFrame, useMjpegDirect, mjpegSource);
        logf('Using direct AVI/MJPEG reader: %s', filepath);
    else
        try
            video_obj = VideoReader(filepath);  
        catch exception
            msgbox(['Error opening video file. Message: ' exception.message], ...
                   'Open video', 'error');
            return;
        end    
        nframes = floor(video_obj.Duration * video_obj.FrameRate);
        previewFrame = min(max(1, round(nframes / 10)), nframes);
        frame100 = read(video_obj, previewFrame);
        videosize = [video_obj.Width,video_obj.Height];
        frameRate = video_obj.FrameRate;
        duration = video_obj.Duration;
    end

        mouseColor = chooseMouseColor(settings);
        if isempty(mouseColor)
            logf('Cancel mouse color selection');
            return;
        end
        detectLightMouse = strcmp(mouseColor, 'White mouse / dark background');

        [trackColors, trackLineWidth] = chooseTrackStyle(settings);
        if isempty(trackColors)
            logf('Cancel trajectory style selection');
            return;
        end
        settings.trackColors = trackColors;
        settings.trackLineWidth = trackLineWidth;

        [analysisZones, cancelAnalysisZones] = chooseAnalysisZones(settings);
        if cancelAnalysisZones
            logf('Cancel analysis zone selection');
            return;
        end
        settings.analysisZones = analysisZones;
        
        if(~exist(outputDir,'dir'))
            mkdir(outputDir);
        end
        imgfilename1 = fullfile(outputDir, [video_name '_threshold']);

        th = chooseThreshold(frame100, detectLightMouse, imgfilename1, previewFrame, settings);
        if isempty(th)
            logf('Cancel threshold selection');
            return;
        end

        defaultans = {th,'200','1','1',num2str(nframes),'1'};
        answer = collectProcessingParameters(defaultans, settings);
        if isempty(answer)
            logf('Cancel movie processing parameters');
            return;
        end
        threshold = str2double(answer{1}); % Segmentation threshold selected in the dialog (range 0 to 1).
        objpixels = floor(str2double(answer{2})); % Minimum connected-object area in pixels; dialog default: 200.
        MouseN = floor(str2double(answer{3})); % Number of animals/arena ROIs; dialog default: 1.
        StartFrame = floor(str2double(answer{4})); % First source frame selected for analysis.
        LastFrame = floor(str2double(answer{5})); % Last source frame selected for analysis.
        Step = floor(str2double(answer{6})); % Frame sampling interval; dialog default: 1.
        StartFrame = max(1, StartFrame);
        LastFrame = min(nframes, LastFrame);
        Step = max(1, Step);
        close all;
        
        hDrawArena = figure('Name','Draw arena','NumberTitle','off');
        centerFigure(hDrawArena, 900, 900);
        imshow(readFrameFromSource(useFrameFolder, frameFolder, frameFiles, video_obj, StartFrame, useMjpegDirect, mjpegSource), 'InitialMagnification', 'fit');
        axis image off;
        
        arenaD = cell(MouseN,1);
        xa = cell(MouseN,1);
        ya = cell(MouseN,1);
        arena_w = cell(MouseN,1);
        arena_h = cell(MouseN,1);
        w0 = 254;
        h0 = 254;
        for n = 1:MouseN
            logf(['please draw the arena for mouse' num2str(n)]);
            arena = drawrectangle('Position',[20 20 w0 h0], 'LineWidth',1); 
            position = customWait(arena);
            arenaD{n} = floor(position);
            xa{n} = arenaD{n}(1);
            ya{n} = arenaD{n}(2);
            arena_w{n} = arenaD{n}(3);
            arena_h{n} = arenaD{n}(4); 
            w0 = arena_w{1};
            h0 = arena_h{1};
        end

        f = waitbar(0,'1','Name','Tracking mouse...');
        movegui(f, 'center');
                        
        close all;
        
        result.filepath = filename;
        result.frameRate = frameRate;
        result.duration = duration;
        result.nframes = nframes;
        result.videosize = videosize;
        result.StartFrame = StartFrame;
        result.LastFrame = LastFrame;
        result.arenaD = arenaD;
        result.mouseN = MouseN;
        result.step = Step;
        result.mouseColor = mouseColor;
        result.detectLightMouse = detectLightMouse;
        result.useFrameFolder = useFrameFolder;
        result.frameFolder = frameFolder;
        result.useMjpegDirect = useMjpegDirect;
        result.mjpegSource = mjpegSource;
        result.settings = settings;
        
        result.positions = [];        

     tic;
     tStart = tic;
     x = StartFrame:Step:LastFrame;
     
     c1 = cell(MouseN, length(x), 2);
     m1_majl = cell(MouseN, length(x), 1);
     m1_minl = cell(MouseN, length(x), 1);
     m1_ori = cell(MouseN, length(x), 1);
     m1_ecc = cell(MouseN, length(x), 1);
     m1_area = cell(MouseN, length(x), 1);
     missCount = zeros(MouseN, 1);
     readErrorCount = 0;
     processErrorCount = zeros(MouseN, 1);
     lastFrameRaw = [];
     if ~useFrameFolder && ~useMjpegDirect
         video_obj.CurrentTime = max(0, (StartFrame - 1) / frameRate);
     end
     
     for jj = 1:length(x)

            [currentFrameRaw, lastFrameRaw, readOk, readMessage] = readTrackingFrame(useFrameFolder, frameFolder, frameFiles, video_obj, x(jj), lastFrameRaw, useMjpegDirect, mjpegSource);
            if ~readOk
                readErrorCount = readErrorCount + 1;
                logf('Frame %d could not be read. Using the previous frame. Message: %s', x(jj), readMessage);
                if isempty(lastFrameRaw)
                    for m = 1:MouseN
                        xStart = max(1, xa{m});
                        yStart = max(1, ya{m});
                        xEnd = min(videosize(1), xa{m} + arena_w{m} - 1);
                        yEnd = min(videosize(2), ya{m} + arena_h{m} - 1);
                        [c1{m}(jj,:), m1_majl{m}(jj,:), m1_minl{m}(jj,:), m1_ori{m}(jj,:), m1_ecc{m}(jj,:), m1_area{m}(jj,:)] = fallbackTrackingValues(c1, m1_majl, m1_minl, m1_ori, m1_ecc, m1_area, m, jj, xStart, yStart, xEnd, yEnd);
                    end
                    waitbar(jj/length(x),f,sprintf(['Tracking Progress: ' num2str(round(jj*10000/length(x))/100) '%%']))
                    continue;
                end
            end

            try
                frame2 = bwareaopen(im2bw(segmentInputFrame(currentFrameRaw, detectLightMouse), threshold),objpixels) * 255; % Remove connected objects smaller than objpixels; retain numeric 0/255 representation.
            catch exception
                readErrorCount = readErrorCount + 1;
                logf('Frame %d could not be converted to binary image. Using previous positions. Message: %s', x(jj), exception.message);
                for m = 1:MouseN
                    xStart = max(1, xa{m});
                    yStart = max(1, ya{m});
                    xEnd = min(videosize(1), xa{m} + arena_w{m} - 1);
                    yEnd = min(videosize(2), ya{m} + arena_h{m} - 1);
                    [c1{m}(jj,:), m1_majl{m}(jj,:), m1_minl{m}(jj,:), m1_ori{m}(jj,:), m1_ecc{m}(jj,:), m1_area{m}(jj,:)] = fallbackTrackingValues(c1, m1_majl, m1_minl, m1_ori, m1_ecc, m1_area, m, jj, xStart, yStart, xEnd, yEnd);
                end
                waitbar(jj/length(x),f,sprintf(['Tracking Progress: ' num2str(round(jj*10000/length(x))/100) '%%']))
                continue;
            end
            
            for m = 1:MouseN
                try
                    xStart = max(1, xa{m});
                    yStart = max(1, ya{m});
                    xEnd = min(size(frame2, 2), xa{m} + arena_w{m} - 1);
                    yEnd = min(size(frame2, 1), ya{m} + arena_h{m} - 1);

                    if xStart > xEnd || yStart > yEnd
                        error('Arena for mouse %d is outside the video image. Please draw the arena inside the image.', m);
                    end
                    % Numeric 0/255 input is a label image: disconnected pixels
                    % with label 255 are measured together by regionprops.

                    mouse = regionprops(frame2(yStart:yEnd, xStart:xEnd),'Area','Centroid','MajorAxisLength','MinorAxisLength','Orientation','Eccentricity');

                    if ~isempty([mouse.Area])                    
                        areaArray = [mouse.Area];
                        [~,idx] = max(areaArray);
                        c1{m}(jj,:) = floor(mouse(idx).Centroid + [xStart - 1, yStart - 1]);

                        m1_majl{m}(jj,:) = mouse(idx).MajorAxisLength;
                        m1_minl{m}(jj,:) = mouse(idx).MinorAxisLength;
                        m1_ori{m}(jj,:) = mouse(idx).Orientation;
                        m1_ecc{m}(jj,:) = mouse(idx).Eccentricity;
                        m1_area{m}(jj,:) = mouse(idx).Area;                    
                    else
                        % Retain the preceding estimate when no object is found.
                        % An initial failure uses the arena midpoint (see helper).
                        missCount(m) = missCount(m) + 1;
                        [c1{m}(jj,:), m1_majl{m}(jj,:), m1_minl{m}(jj,:), m1_ori{m}(jj,:), m1_ecc{m}(jj,:), m1_area{m}(jj,:)] = fallbackTrackingValues(c1, m1_majl, m1_minl, m1_ori, m1_ecc, m1_area, m, jj, xStart, yStart, xEnd, yEnd);
                    end
                catch exception
                    processErrorCount(m) = processErrorCount(m) + 1;
                    missCount(m) = missCount(m) + 1;
                    logf('Mouse %d failed at frame %d. Using previous position. Message: %s', m, x(jj), exception.message);
                    xStart = max(1, xa{m});
                    yStart = max(1, ya{m});
                    xEnd = min(videosize(1), xa{m} + arena_w{m} - 1);
                    yEnd = min(videosize(2), ya{m} + arena_h{m} - 1);
                    [c1{m}(jj,:), m1_majl{m}(jj,:), m1_minl{m}(jj,:), m1_ori{m}(jj,:), m1_ecc{m}(jj,:), m1_area{m}(jj,:)] = fallbackTrackingValues(c1, m1_majl, m1_minl, m1_ori, m1_ecc, m1_area, m, jj, xStart, yStart, xEnd, yEnd);
                end
            end
            % Advance the sequential video reader past unsampled frames.
            % This applies only to the standard VideoReader source.
            if ~useFrameFolder && ~useMjpegDirect && Step>1 && x(jj)+1 <= nframes
                for skipFrame = 1:(Step - 1)
                    if hasFrame(video_obj)
                        readFrame(video_obj);
                    end
                end
            end

         waitbar(jj/length(x),f,sprintf(['Tracking Progress: ' num2str(round(jj*10000/length(x))/100) '%%']))
     end      
     delete(f)   

     detectedCount = zeros(MouseN, 1);
     for m = 1:MouseN
         areaVals = m1_area{m};
         if isempty(areaVals)
             detectedCount(m) = 0;
         else
             detectedCount(m) = sum(areaVals > 0);
         end
     end

     if any(detectedCount == 0)
         debugFrame = readFrameFromSource(useFrameFolder, frameFolder, frameFiles, video_obj, StartFrame, useMjpegDirect, mjpegSource);
         debugBinary = bwareaopen(im2bw(segmentInputFrame(debugFrame, detectLightMouse), threshold), objpixels) * 255;
         debugFig = figure('Name','Tracking debug','NumberTitle','off','Visible','off');
         subplot(1,2,1);
         imshow(debugFrame, 'InitialMagnification', 'fit');
         axis image off;
         title('Original + arena');
         hold on;
         for m = 1:MouseN
             rectangle('Position', arenaD{m}, 'EdgeColor', 'y', 'LineWidth', 2);
         end
         hold off;
         subplot(1,2,2);
         imshow(debugBinary, 'InitialMagnification', 'fit');
         axis image off;
         title(sprintf('Binary threshold %.2f, min pixels %d', threshold, objpixels));
         hold on;
         for m = 1:MouseN
             rectangle('Position', arenaD{m}, 'EdgeColor', 'y', 'LineWidth', 2);
         end
         hold off;
         debugPath = fullfile(outputDir, [video_name '_debug_no_detection.tif']);
         print(debugFig, debugPath, '-dtiff', '-r200');
         close(debugFig);
         logf('Mouse detection failed. Debug image saved: %s', debugPath);
        logf('Try drawing the arena around the floor area that contains the mouse, then use White mouse / dark background and a lower threshold such as 0.60 or 0.65.');
         return;
     end

     result.positions = {};
     result.area = {};
     result.orientation = {};
     
     for p = 1:MouseN         
         result.positions = [result.positions c1{p}];
         result.area = [result.area m1_area{p}];
         result.orientation = [result.orientation [m1_majl{p} m1_minl{p} m1_ori{p} m1_ecc{p}]];     
     end
     
     save(resultpath, 'result');
     tElapsed = toc(tStart);   
     logf(['tracking completed and data saved! used: ' num2str(tElapsed) 'seconds']);          
     if readErrorCount > 0
         logf('Video frame read/convert errors: %d frames. Those frames were filled with previous data.', readErrorCount);
     end
     for m = 1:MouseN
         if missCount(m) > 0
             logf('Mouse %d was not detected in %d frames. Those frames were filled with the previous position.', m, missCount(m));
         end
         if processErrorCount(m) > 0
             logf('Mouse %d had processing errors in %d frames.', m, processErrorCount(m));
         end
     end
end
               
    if exist(resultpath, 'file') == 2 && exist(fullfile(outputDir, [video_name '_result.xls']), 'file') ~= 2
        logf('Tracking has been done, running analysis...');
        analysis(filename, dirpath);
    end
    
        logf('Tracking and analysis have been done');

         button = chooseYesNoDialog('Check tracking results?', ...
             'Tracking and analysis completed. Create a tracking-check movie?', settings);

         trackmovie_name = [video_name '_result.mp4'];
         trackmoviepath = fullfile(outputDir, trackmovie_name);
         
         if strcmp(button,'Yes')
            if exist(trackmoviepath, 'file') ~= 2 || dir(trackmoviepath).bytes == 0
                close all;
                R = load(resultpath);
                if ~(isfield(R.result, 'useFrameFolder') && R.result.useFrameFolder) && ~(isfield(R.result, 'useMjpegDirect') && R.result.useMjpegDirect)
                    video_obj = VideoReader(filepath);
                end
                MouseN = R.result.mouseN;
                nframes = R.result.nframes;
                startframe = R.result.StartFrame;
                lastframe = R.result.LastFrame;
                c1 = R.result.positions;
                ori = R.result.orientation;
                area = R.result.area;
                step = R.result.step;
                x = startframe:step:lastframe;
                if isfield(R.result, 'settings') && isfield(R.result.settings, 'previewMaxFrames')
                    previewMaxFrames = R.result.settings.previewMaxFrames;
                else
                    previewMaxFrames = 900;
                end
                defaultPreviewLastFrame = min(lastframe, startframe + (previewMaxFrames - 1) * step);
                if isinf(previewMaxFrames)
                    defaultPreviewLastFrame = lastframe;
                end
                previewAnswer = askSingleNumberDialog( ...
                    'Tracking check range', ...
                    'Create tracking-check movie up to frame:', ...
                    num2str(defaultPreviewLastFrame), settings);
                if isempty(previewAnswer)
                    logf('Cancel tracking-check movie creation');
                    return;
                end
                previewLastFrame = floor(str2double(previewAnswer{1}));
                previewLastFrame = min(max(startframe, previewLastFrame), lastframe);
                previewSampleIdx = find(x <= previewLastFrame);
                if isempty(previewSampleIdx)
                    previewSampleIdx = 1;
                end
                previewFrameCount = numel(previewSampleIdx);
                usePreviewFrameFolder = isfield(R.result, 'useFrameFolder') && R.result.useFrameFolder;
                usePreviewMjpegDirect = isfield(R.result, 'useMjpegDirect') && R.result.useMjpegDirect;
                previewMjpegSource = [];
                if usePreviewMjpegDirect
                    previewMjpegSource = R.result.mjpegSource;
                end
                previewFrameFolder = '';
                previewFrameFiles = [];
                if usePreviewFrameFolder
                    previewFrameFolder = R.result.frameFolder;
                    previewFrameFiles = dir(fullfile(previewFrameFolder, 'frame_*.jpg'));
                    if isempty(previewFrameFiles)
                        previewFrameFiles = dir(fullfile(previewFrameFolder, 'frame_*.png'));
                    end
                    [~, sortIdx] = sort({previewFrameFiles.name});
                    previewFrameFiles = previewFrameFiles(sortIdx);
                end
                
                F(previewFrameCount) = struct('cdata',[],'colormap',[]);

                if isfield(R.result, 'settings')
                    styleSettings = R.result.settings;
                else
                    styleSettings.trackColors = {'#0072BD', '#D95319', '#77AC30', '#7E2F8E', '#EDB120'};
                    styleSettings.trackLineWidth = 2;
                end
                colors = normalizeColorList(styleSettings.trackColors, MouseN);
                trackLineWidth = styleSettings.trackLineWidth;
                lastPreviewFrame = [];
                if ~usePreviewFrameFolder && ~usePreviewMjpegDirect
                    video_obj.CurrentTime = max(0, (startframe - 1) / R.result.frameRate);
                end

                for ii=1:previewFrameCount
                    i = previewSampleIdx(ii);

                    [vframe, lastPreviewFrame, previewReadOk, previewReadMessage] = readTrackingFrame(usePreviewFrameFolder, previewFrameFolder, previewFrameFiles, video_obj, x(i), lastPreviewFrame, usePreviewMjpegDirect, previewMjpegSource);
                    if ~previewReadOk
                        logf('Preview frame %d could not be read. Using previous frame. Message: %s', x(i), previewReadMessage);
                        if isempty(lastPreviewFrame)
                            continue;
                        end
                    end
                    image(vframe);
                    hold on

                    for mn=1:MouseN
                        m1_majl{mn} = ori{mn}(:,1);
                        m1_minl{mn} = ori{mn}(:,2);
                        m1_ori{mn} = ori{mn}(:,3);
                        m1_area{mn} = area{mn}(:,1);
                        m1_ecc{mn} = ori{mn}(:,4);
                        p1 = calculateEllipse(c1{mn}(i,1),c1{mn}(i,2),m1_majl{mn}(i,1)./2,m1_minl{mn}(i,1)./2,m1_ori{mn}(i,1));
                        plot(p1(:,1), p1(:,2), '.-', 'Color', colors(mn,:), 'LineWidth', trackLineWidth)
                        text(c1{mn}(i,1),c1{mn}(i,2),num2str(mn),'Color',colors(mn,:),'FontSize',20,'FontWeight','bold')
                    end

                    title(['Frame ' num2str(x(i))])
                    hold off
                    F(ii) = getframe;

                    if ~usePreviewFrameFolder && ~usePreviewMjpegDirect && step > 1
                        for skipFrame = 1:(step - 1)
                            if hasFrame(video_obj)
                                readFrame(video_obj);
                            end
                        end
                    end
                end

                trackmoviepath = writeCompatibleVideo(trackmoviepath, F, frameRate);
                logf('Video saved: %s', trackmoviepath);
            else
                h=implay(trackmoviepath);
                play(h.DataSource.Controls);
            end
        end
        
end        

function analysis(filename1, dirpath1)
% ANALYSIS Export saved trajectories, occupancy summaries and diagnostic plots.
   
    filepath = fullfile(dirpath1, filename1);
    
    [u1 video_name u2] = fileparts(filepath);
                
    result_name = [video_name '_result.mat'];
    outputDir = fullfile(dirpath1, video_name);
    resultpath = fullfile(outputDir, result_name);

    R = load(resultpath);
    startframe = R.result.StartFrame;
    lastframe = R.result.LastFrame;
    step = R.result.step;
    totalframe = floor((lastframe-startframe)/step)+1;
    frameRate = R.result.frameRate;
    videosize = R.result.videosize;
    arena = R.result.arenaD;
    pos = R.result.positions;
    ori = R.result.orientation;
    area = R.result.area;
    mouseN = R.result.mouseN;
    if isfield(R.result, 'settings')
        analysisSettings = R.result.settings;
    else
        analysisSettings.arenaSizeMm = 400;
        analysisSettings.centerMarginMm = 50;
        analysisSettings.cornerZoneSizeMm = 100;
        analysisSettings.cornerZoneMarginMm = 50;
        analysisSettings.trackColors = {'#0072BD', '#D95319', '#77AC30', '#7E2F8E', '#EDB120'};
        analysisSettings.trackLineWidth = 2;
    end
    analysisSettings = ensureAnalysisSettings(analysisSettings);
    colors = normalizeColorList(analysisSettings.trackColors, mouseN);
    trackLineWidth = analysisSettings.trackLineWidth;

    for i=1:mouseN
        m1_majl{i} = ori{i}(:,1);
        m1_ecc{i} = ori{i}(:,4);
        m_area{i} = area{i}(:,1);
    end

    subplot(3,1,1)
    for i=1:mouseN
        eccVals = m1_ecc{i};
        eccVals = eccVals(isfinite(eccVals) & eccVals > 0);
        if numel(eccVals) >= 2
            ecc1{i} = histfit(eccVals,20,'gamma');
            ecc1{i}(1).FaceColor = [i./mouseN 0.8 1./i];
            ecc1{i}(2).Color = [1./i 0.2 i./mouseN];
            set(ecc1{i}(1),'facealpha',0.5)
        end
        hold on
    end    
        xlabel('Eccentricity','FontSize',16);
        ylabel('Distribution','FontSize',16);
        yt = get(gca, 'YTick');
        set(gca, 'YTick', yt, 'YTickLabel', round(100*yt/numel(m1_ecc{1}))/100)
        set(gca,'fontsize',16,'linewidth',2,'box','on')
        hold off

    subplot(3,1,2)
    for i=1:mouseN
        areaVals = area{i}(:,1);
        areaVals = areaVals(isfinite(areaVals) & areaVals > 0);
        if numel(areaVals) >= 2
            h1{i} = histfit(areaVals,20,'Normal');
            h1{i}(1).FaceColor = [i./mouseN 0.8 1./i];
            h1{i}(2).Color = [1./i 0.2 i./mouseN];
            set(h1{i}(1),'facealpha',0.5)
        end
        hold on
    end
    xlabel('Mouse Area','FontSize',16);
    ylabel('Distribution','FontSize',16);
    set(gca,'fontsize',16,'linewidth',2,'box','on')
    hold off

    subplot(3,1,3)
    for i=1:mouseN
        majlVals = m1_majl{i};
        majlVals = majlVals(isfinite(majlVals) & majlVals > 0);
        if numel(majlVals) >= 2
            majl1{i} = histfit(majlVals,40,'Normal');
            majl1{i}(1).FaceColor = [i./mouseN 0.8 1./i];
            majl1{i}(2).Color = [1./i 0.2 i./mouseN];        
            set(majl1{i}(1),'facealpha',0.5)
        end
        hold on
    end
    xlabel('Major Axis Length','FontSize',16);
    ylabel('Distribution','FontSize',16);
    set(gca,'fontsize',16,'linewidth',2,'box','on')

    imgfilename1 = fullfile(outputDir, [video_name '_orientation']);

    centerFigure(gcf, 450, 900);
    print(gcf,[imgfilename1 '.tif'],'-dtiff','-r300');

    hold off

    x = startframe:step:lastframe;
    ctimearray=zeros(length(x),1);
    for j=1:length(x)
        ctimearray(j) = (j-1).*step./frameRate;
    end

    xlsfilename = [video_name '_result.xls'];
    xlsPath = fullfile(outputDir, xlsfilename);
    logf('Saving Results into Excel and TIFF files, please wait...', xlsPath);

    for i=1:mouseN

        arenaW = arena{i}(:,3);
        arenaH = arena{i}(:,4);
        arenaSizeMm = analysisSettings.arenaSizeMm;
        mmPerPixelX = arenaSizeMm ./ arenaW;
        mmPerPixelY = arenaSizeMm ./ arenaH;
        pixels = mean([mmPerPixelX mmPerPixelY]); % Historical distance scale: mean of the X and Y calibration factors (mm/pixel).

        xa = [arena{i}(:,1),arena{i}(:,1)+arenaW,arena{i}(:,1)+arenaW,arena{i}(:,1),arena{i}(:,1)];
        ya = [arena{i}(:,2)+arenaH,arena{i}(:,2)+arenaH,arena{i}(:,2),arena{i}(:,2),arena{i}(:,2)+arenaH];

        mouse = ['mouse' num2str(i)]; 
        xq1 = pos{i}(:,1);
        yq1 = pos{i}(:,2);
        pathl1 =[0];
        dd1 = 0;
        distance1 = [0];

        zoneCount = numel(analysisSettings.analysisZones);
        zoneTimes = zeros(1, zoneCount);
        zoneX = cell(1, zoneCount);
        zoneY = cell(1, zoneCount);
        for z = 1:zoneCount
            zone = analysisSettings.analysisZones(z);
            x1 = arena{i}(:,1) + zone.xMm ./ mmPerPixelX;
            x2 = x1 + zone.widthMm ./ mmPerPixelX;
            y1 = arena{i}(:,2) + zone.yMm ./ mmPerPixelY;
            y2 = y1 + zone.heightMm ./ mmPerPixelY;
            zoneX{z} = [x1 x2 x2 x1 x1];
            zoneY{z} = [y2 y2 y1 y1 y2];
            % Zone boundaries are included; each sample contributes step/frameRate seconds.
            inZone = inpolygon(xq1, yq1, zoneX{z}, zoneY{z});
            zoneTimes(z) = numel(xq1(inZone)) .* step ./ frameRate;
        end

        for k = 2:length(pos{i})
              D1 = sqrt((pos{i}(k,1)-pos{i}(k-1,1))^2+(pos{i}(k,2)-pos{i}(k-1,2))^2);
              D1 = D1.* pixels; % Convert inter-sample displacement to mm using the scalar calibration.
              pathl1 = [pathl1; D1];
              dd1 = dd1 + D1./1000; % Accumulate calibrated travel distance in metres.
              distance1 = [distance1; dd1];
        end

        titlerow = horzcat({'Time (s)'},{[mouse '_X']},{[mouse '_Y']},{[mouse '_PathL (mm)']},{[mouse '_Distance(m)']});
        finaldata = horzcat(ctimearray,xq1,yq1,pathl1,distance1);


        summarytitle = {'FileName'};
        summaryresults = {filename1};
        if zoneCount > 0
            TimeOuter1 = totalframe.*step./frameRate - zoneTimes(1);
            % The fraction below refers to the first configured zone only.
            Thigmotaxis1 = 1 - zoneTimes(1) ./ (length(x).*step./frameRate);
            summarytitle = [summarytitle {[mouse '_Outside_' sanitizeExcelLabel(analysisSettings.analysisZones(1).name) ' (s)']}];
            summaryresults = [summaryresults {TimeOuter1}];
        end
        for z = 1:zoneCount
            zoneLabel = sanitizeExcelLabel(analysisSettings.analysisZones(z).name);
            summarytitle = [summarytitle {[mouse '_' zoneLabel ' (s)']}];
            summaryresults = [summaryresults {zoneTimes(z)}];
        end
        if zoneCount > 0
            summarytitle = [summarytitle {[mouse '_Thigmotaxis_by_' sanitizeExcelLabel(analysisSettings.analysisZones(1).name)]}];
            summaryresults = [summaryresults {Thigmotaxis1}];
        end

        xlwrite(xlsPath,titlerow,mouse,'A1');
        xlwrite(xlsPath,finaldata,mouse,'A2'); % Write per-sample measurements from cell A2.
        xlwrite(xlsPath,summarytitle,mouse,'G1');
        xlwrite(xlsPath,summaryresults,mouse,'G2');

        zoneXAll{i} = zoneX;
        zoneYAll{i} = zoneY;
        xa1{i} = xa;
        ya1{i} = ya;
        finaldata1{i} = finaldata;

    end


    hsum=figure('Visible','on'); 
    movegui(hsum, 'center');
    Bkg = 230 * ones(videosize(2), videosize(1), 3, 'uint8');

    subplot(1,2,1); image(Bkg); axis image off
    hold all
    for i=1:mouseN
        plot(pos{i}(:,1),pos{i}(:,2),'Color',colors(i,:),'LineWidth',trackLineWidth);
        for z = 1:numel(zoneXAll{i})
            plot(zoneXAll{i}{z}, zoneYAll{i}{z}, '--k', 'LineWidth', 2);
        end
        plot(xa1{i},ya1{i},'k','LineWidth',2); % Draw the outer arena boundary.
    end
    set(gca,'fontsize',20)
    ymax = 0;

    subplot(1,2,2);
    for i=1:mouseN 
        ymax = max(ymax, max(finaldata1{i}(:,5)));
        plot(finaldata1{1}(:,1),finaldata1{i}(:,5),'Color',colors(i,:),'LineWidth',trackLineWidth);
        hold on
    end
    hold off
    xlim([0 length(x).*step./frameRate]);
    ylim([0 ymax]);
    xlabel('Times (s)');
    ylabel('Travel Distance (m)');
    set(gca,'linewidth',2,'fontsize',20,'box', 'off');
    set(gcf,'Units','Normalized','Position',[0 0 1 0.5],'PaperPositionMode','auto','PaperSize',[14 14]);
    title([video_name '.mov'],'Interpreter','none');

    imgfilename = fullfile(outputDir, [video_name '_summary']);
    print(gcf,[imgfilename '.tif'],'-dtiff','-r300');
    hold off

    logf('Results saved to folder %s', outputDir);

end    

function frameRaw = readFrameFromSource(useFrameFolder, frameFolder, frameFiles, video_obj, frameIndex, useMjpegDirect, mjpegSource)
% READFRAMEFROMSOURCE Read an indexed frame from the selected video source.

    if useMjpegDirect
        frameRaw = readAviMjpegFrame(mjpegSource, frameIndex);
    elseif useFrameFolder
        frameIndex = min(max(1, frameIndex), numel(frameFiles));
        frameRaw = imread(fullfile(frameFolder, frameFiles(frameIndex).name));
    else
        frameRaw = read(video_obj, frameIndex);
    end

end

function [frameRaw, lastFrameRaw, readOk, readMessage] = readTrackingFrame(useFrameFolder, frameFolder, frameFiles, video_obj, frameIndex, lastFrameRaw, useMjpegDirect, mjpegSource)
% READTRACKINGFRAME Read a sample and return the preceding image on failure.

    readOk = true;
    readMessage = '';

    if useMjpegDirect
        try
            if frameIndex > numel(mjpegSource.offsets)
                readOk = false;
                readMessage = 'Frame index is beyond the AVI/MJPEG frame index.';
                frameRaw = lastFrameRaw;
                return;
            end
            frameRaw = readAviMjpegFrame(mjpegSource, frameIndex);
            lastFrameRaw = frameRaw;
        catch exception
            readOk = false;
            readMessage = exception.message;
            frameRaw = lastFrameRaw;
        end
    elseif useFrameFolder
        try
            if frameIndex > numel(frameFiles)
                readOk = false;
                readMessage = 'Frame index is beyond the extracted frame folder.';
                frameRaw = lastFrameRaw;
                return;
            end
            frameRaw = imread(fullfile(frameFolder, frameFiles(frameIndex).name));
            lastFrameRaw = frameRaw;
        catch exception
            readOk = false;
            readMessage = exception.message;
            frameRaw = lastFrameRaw;
        end
    else
        if hasFrame(video_obj)
            try
                frameRaw = readFrame(video_obj);
                lastFrameRaw = frameRaw;
            catch exception
                readOk = false;
                readMessage = exception.message;
                frameRaw = lastFrameRaw;
            end
        else
            readOk = false;
            readMessage = 'No more frames are available from VideoReader.';
            frameRaw = lastFrameRaw;
        end
    end

end

function tf = isAviMjpegFile(filepath)
% ISAVIMJPEGFILE Inspect the file header for AVI/MJPEG markers.

    tf = false;
    fid = fopen(filepath, 'r');
    if fid < 0
        return;
    end
    cleaner = onCleanup(@() fclose(fid));
    header = fread(fid, min(4096, getFileSize(filepath)), '*uint8')';
    if numel(header) < 16
        return;
    end
    headerText = char(header);
    tf = ~isempty(strfind(headerText, 'RIFF')) && ~isempty(strfind(headerText, 'AVI')) && ~isempty(strfind(headerText, 'MJPG'));

end

function source = openAviMjpegSource(filepath)
% OPENAVIMJPEGSOURCE Build a heuristic index of JPEG payloads in an AVI file.
% Header fallback frame rate is 30 Hz; check against acquisition metadata.

    fid = fopen(filepath, 'r');
    if fid < 0
        error('Could not open AVI/MJPEG file: %s', filepath);
    end
    cleaner = onCleanup(@() fclose(fid));

    source.filepath = filepath;
    source.frameRate = 30;
    source.offsets = [];
    source.sizes = [];
    source.tempJpegPath = [tempname '.jpg'];

    fileSize = getFileSize(filepath);
    headerBytes = fread(fid, min(fileSize, 8192), '*uint8')';
    headerText = char(headerBytes);
    strhPos = strfind(headerText, 'strh');
    if ~isempty(strhPos)
        try
            pos = strhPos(1);
            scale = typecast(uint8(headerBytes(pos + 28:pos + 31)), 'uint32');
            rate = typecast(uint8(headerBytes(pos + 32:pos + 35)), 'uint32');
            if scale > 0 && rate > 0
                source.frameRate = double(rate) ./ double(scale);
            end
        catch
            source.frameRate = 30;
        end
    end

    chunkSize = 1024 * 1024;
    overlap = uint8([]);
    fileOffset = ftell(fid);
    offsets = [];
    sizes = [];

    while ~feof(fid)
        bytes = fread(fid, chunkSize, '*uint8')';
        if isempty(bytes)
            break;
        end
        scanBytes = [overlap bytes];
        scanOffset = fileOffset - numel(overlap);
        hit = strfind(char(scanBytes), '00dc');
        for h = hit
            if h + 7 <= numel(scanBytes)
                payloadSize = double(typecast(uint8(scanBytes(h + 4:h + 7)), 'uint32'));
                payloadStart = h + 8;
                if payloadSize > 0 && payloadSize < 2000000 && payloadStart + 1 <= numel(scanBytes)
                    if scanBytes(payloadStart) == 255 && scanBytes(payloadStart + 1) == 216
                        offsets(end + 1) = scanOffset + payloadStart - 1; %#ok<AGROW>
                        sizes(end + 1) = payloadSize; %#ok<AGROW>
                    end
                end
            end
        end
        overlapLength = min(16, numel(scanBytes));
        overlap = scanBytes(end - overlapLength + 1:end);
        fileOffset = fileOffset + numel(bytes);
    end

    source.offsets = offsets;
    source.sizes = sizes;

end

function frameRaw = readAviMjpegFrame(source, frameIndex)
% READAVIMJPEGFRAME Decode an indexed JPEG payload using a temporary file.

    frameIndex = min(max(1, frameIndex), numel(source.offsets));
    fid = fopen(source.filepath, 'r');
    if fid < 0
        error('Could not open AVI/MJPEG file: %s', source.filepath);
    end
    cleaner = onCleanup(@() fclose(fid));
    fseek(fid, source.offsets(frameIndex), 'bof');
    payload = fread(fid, source.sizes(frameIndex), '*uint8');
    eoi = find(payload(1:end-1) == 255 & payload(2:end) == 217, 1, 'last');
    if ~isempty(eoi)
        payload = payload(1:eoi+1);
    end

    tempPath = source.tempJpegPath;
    out = fopen(tempPath, 'w');
    if out < 0
        error('Could not create temporary JPEG file.');
    end
    fwrite(out, payload, 'uint8');
    fclose(out);
    frameRaw = imread(tempPath);
    if exist(tempPath, 'file') == 2
        delete(tempPath);
    end

end

function fileSize = getFileSize(filepath)
% GETFILESIZE Return the file size in bytes.

    info = dir(filepath);
    fileSize = info.bytes;

end

function centerFigure(h, widthPx, heightPx)
% CENTERFIGURE Size and centre a figure on the display.

    try
        set(h, 'Units', 'pixels');
        screenSize = get(0, 'ScreenSize');
        left = max(1, round((screenSize(3) - widthPx) / 2));
        bottom = max(1, round((screenSize(4) - heightPx) / 2));
        set(h, 'Position', [left bottom widthPx heightPx]);
        movegui(h, 'center');
    catch
        movegui(h, 'center');
    end

end

function setDefaultUiFonts(settings)
% SETDEFAULTUIFONTS Apply session-wide default font sizes for the interface.

    try
        set(0, 'DefaultUicontrolFontSize', settings.uiBodyFontSize);
        set(0, 'DefaultUitableFontSize', settings.uiBodyFontSize);
        set(0, 'DefaultAxesFontSize', settings.uiBodyFontSize);
        set(0, 'DefaultTextFontSize', settings.uiBodyFontSize);
    catch
    end

end

function rgb = normalizeColorList(colorList, nColors)
% NORMALIZECOLORLIST Convert trajectory colour specifications to RGB rows.

    rgb = zeros(nColors, 3);
    fallback = lines(max(nColors, 1));
    for i = 1:nColors
        if i <= numel(colorList)
            rgb(i,:) = hexToRgb(colorList{i});
        else
            rgb(i,:) = fallback(i,:);
        end
    end

end

function rgb = hexToRgb(hexColor)
% HEXTORGB Convert a hexadecimal colour specification to an RGB triplet.

    if isnumeric(hexColor) && numel(hexColor) == 3
        rgb = hexColor;
        return;
    end

    hexColor = char(hexColor);
    hexColor = strtrim(hexColor);
    if ~isempty(hexColor) && hexColor(1) == '#'
        hexColor = hexColor(2:end);
    end
    if numel(hexColor) ~= 6
        rgb = [0 0.4470 0.7410];
        return;
    end
    rgb = [hex2dec(hexColor(1:2)), hex2dec(hexColor(3:4)), hex2dec(hexColor(5:6))] ./ 255;

end

function hexColor = normalizeHexColor(hexColor)
% NORMALIZEHEXCOLOR Validate and normalize a hexadecimal colour string.

    hexColor = upper(strtrim(char(hexColor)));
    if isempty(hexColor)
        hexColor = '#0072BD';
        return;
    end
    if hexColor(1) ~= '#'
        hexColor = ['#' hexColor];
    end
    if numel(hexColor) ~= 7
        hexColor = '#0072BD';
        return;
    end
    validChars = ismember(hexColor(2:end), ['0':'9' 'A':'F']);
    if ~all(validChars)
        hexColor = '#0072BD';
    end

end

function [trackColors, trackLineWidth] = chooseTrackStyle(settings)
% CHOOSETRACKSTYLE Collect trajectory colours and line width interactively.

    presetColors = {'#0072BD', '#D95319', '#77AC30', '#7E2F8E', '#EDB120'};
    presetNames = {'Blue', 'Orange', 'Green', 'Purple', 'Yellow'};
    trackColors = {};
    trackLineWidth = settings.trackLineWidth;

    d = dialog('Name', 'Trajectory color', 'Position', [320 260 860 580]);
    movegui(d, 'center');

    uicontrol('Parent', d, ...
        'Style', 'text', ...
        'String', 'Select trajectory color', ...
        'Position', [30 525 800 35], ...
        'FontSize', settings.uiTitleFontSize, ...
        'FontWeight', 'bold');

    uicontrol('Parent', d, ...
        'Style', 'text', ...
        'String', 'Presets', ...
        'Position', [35 485 260 25], ...
        'FontSize', settings.uiBodyFontSize, ...
        'FontWeight', 'bold');

    for i = 1:numel(presetColors)
        y = 425 - (i - 1) * 75;
        ax = axes('Parent', d, 'Units', 'pixels', 'Position', [40 y 155 55]);
        drawTrajectorySample(ax, presetColors{i}, settings.trackLineWidth);
        buttonColor = hexToRgb(presetColors{i});
        if mean(buttonColor) < 0.45
            textColor = [1 1 1];
        else
            textColor = [0 0 0];
        end
        uicontrol('Parent', d, ...
            'Style', 'pushbutton', ...
            'String', {presetNames{i}; presetColors{i}}, ...
            'Position', [215 y 155 55], ...
            'FontSize', settings.uiSmallFontSize, ...
            'BackgroundColor', buttonColor, ...
            'ForegroundColor', textColor, ...
            'Callback', @(~,~) selectPreset(i));
    end

    uicontrol('Parent', d, ...
        'Style', 'text', ...
        'String', 'Custom color code', ...
        'Position', [430 485 210 25], ...
        'FontSize', settings.uiBodyFontSize, ...
        'FontWeight', 'bold');

    uicontrol('Parent', d, ...
        'Style', 'pushbutton', ...
        'String', 'Open color chart', ...
        'Position', [650 480 150 34], ...
        'FontSize', settings.uiSmallFontSize, ...
        'Callback', @(~,~) openColorChart());

    customAx = axes('Parent', d, 'Units', 'pixels', 'Position', [430 305 350 160]);
    defaultHex = normalizeHexColor(settings.trackColors{1});
    drawTrajectorySample(customAx, defaultHex, settings.trackLineWidth);

    uicontrol('Parent', d, ...
        'Style', 'text', ...
        'String', 'Hex color:', ...
        'HorizontalAlignment', 'left', ...
        'Position', [430 260 115 28], ...
        'FontSize', settings.uiBodyFontSize);
    hexEdit = uicontrol('Parent', d, ...
        'Style', 'edit', ...
        'String', defaultHex, ...
        'Position', [560 258 160 34], ...
        'FontSize', settings.uiBodyFontSize, ...
        'Callback', @(~,~) previewCustom());

    uicontrol('Parent', d, ...
        'Style', 'text', ...
        'String', 'Line width:', ...
        'HorizontalAlignment', 'left', ...
        'Position', [430 215 115 28], ...
        'FontSize', settings.uiBodyFontSize);
    widthEdit = uicontrol('Parent', d, ...
        'Style', 'edit', ...
        'String', num2str(settings.trackLineWidth), ...
        'Position', [560 213 90 34], ...
        'FontSize', settings.uiBodyFontSize, ...
        'Callback', @(~,~) previewCustom());

    uicontrol('Parent', d, ...
        'Style', 'pushbutton', ...
        'String', 'Preview custom', ...
        'Position', [430 150 165 48], ...
        'FontSize', settings.uiBodyFontSize, ...
        'Callback', @(~,~) previewCustom());

    uicontrol('Parent', d, ...
        'Style', 'pushbutton', ...
        'String', 'Use custom', ...
        'Position', [625 150 165 48], ...
        'FontSize', settings.uiBodyFontSize, ...
        'Callback', @(~,~) useCustom());

    uicontrol('Parent', d, ...
        'Style', 'pushbutton', ...
        'String', 'Cancel', ...
        'Position', [625 45 165 42], ...
        'FontSize', settings.uiBodyFontSize, ...
        'Callback', @(~,~) cancelDialog());

    uiwait(d);

    function selectPreset(index)
        trackLineWidth = readLineWidth();
        selected = presetColors(index:end);
        trackColors = [selected presetColors(1:index-1)];
        closeDialog();
    end

    function previewCustom()
        hexValue = normalizeHexColor(get(hexEdit, 'String'));
        set(hexEdit, 'String', hexValue);
        drawTrajectorySample(customAx, hexValue, readLineWidth());
    end

    function useCustom()
        hexValue = normalizeHexColor(get(hexEdit, 'String'));
        set(hexEdit, 'String', hexValue);
        trackLineWidth = readLineWidth();
        trackColors = [{hexValue} presetColors];
        closeDialog();
    end

    function value = readLineWidth()
        value = str2double(get(widthEdit, 'String'));
        if ~isfinite(value) || value <= 0
            value = settings.trackLineWidth;
        end
        value = min(max(value, 0.5), 10);
        set(widthEdit, 'String', num2str(value));
    end

    function cancelDialog()
        trackColors = {};
        closeDialog();
    end

    function openColorChart()
        web('https://www.colordic.org/', '-browser');
    end

    function closeDialog()
        if isvalid(d)
            delete(d);
        end
    end

end

function drawTrajectorySample(ax, hexColor, lineWidth)
% DRAWTRAJECTORYSAMPLE Show a preview of the selected trajectory style.

    cla(ax);
    t = linspace(0, 1, 30);
    x = 10 + 80 .* t + 7 .* sin(5 .* pi .* t);
    y = 12 + 25 .* sin(2 .* pi .* t) + 35 .* t;
    plot(ax, x, y, '.-', 'Color', hexToRgb(hexColor), 'LineWidth', lineWidth, 'MarkerSize', 8);
    hold(ax, 'on');
    plot(ax, x(1), y(1), 'o', 'Color', [0.15 0.15 0.15], 'MarkerFaceColor', [0.15 0.15 0.15], 'MarkerSize', 4);
    plot(ax, x(end), y(end), 's', 'Color', [0.15 0.15 0.15], 'MarkerFaceColor', [0.15 0.15 0.15], 'MarkerSize', 4);
    hold(ax, 'off');
    set(ax, 'XLim', [0 110], 'YLim', [0 85], 'XTick', [], 'YTick', [], 'Box', 'on', 'Color', [0.92 0.92 0.92]);
    axis(ax, 'ij');

end

function answer = collectProcessingParameters(defaultans, settings)
% COLLECTPROCESSINGPARAMETERS Collect threshold, area and frame settings.

    labels = {'Threshold:', 'Minimal pixels:', 'Mouse number:', 'Start frame:', 'Last frame:', 'Frame step:'};
    d = dialog('Name', 'Processing parameters', 'Position', [320 260 860 580]);
    set(d, 'CloseRequestFcn', @(~,~) cancelDialog());
    movegui(d, 'center');

    answer = {};

    uicontrol('Parent', d, ...
        'Style', 'text', ...
        'String', 'Collect movie processing parameters', ...
        'Position', [30 525 800 35], ...
        'FontSize', settings.uiTitleFontSize, ...
        'FontWeight', 'bold');

    uicontrol('Parent', d, ...
        'Style', 'text', ...
        'String', 'Confirm or edit the values before tracking starts.', ...
        'HorizontalAlignment', 'left', ...
        'Position', [40 480 760 28], ...
        'FontSize', settings.uiSmallFontSize);

    edits = gobjects(1, numel(labels));
    for i = 1:numel(labels)
        y = 420 - (i - 1) .* 58;
        uicontrol('Parent', d, ...
            'Style', 'text', ...
            'String', labels{i}, ...
            'HorizontalAlignment', 'left', ...
            'Position', [105 y + 5 260 28], ...
            'FontSize', settings.uiBodyFontSize);
        edits(i) = uicontrol('Parent', d, ...
            'Style', 'edit', ...
            'String', defaultans{i}, ...
            'Position', [390 y 260 36], ...
            'FontSize', settings.uiBodyFontSize);
    end

    uicontrol('Parent', d, ...
        'Style', 'pushbutton', ...
        'String', 'Use', ...
        'Position', [515 35 140 44], ...
        'FontSize', settings.uiBodyFontSize, ...
        'Callback', @(~,~) useValues());

    uicontrol('Parent', d, ...
        'Style', 'pushbutton', ...
        'String', 'Cancel', ...
        'Position', [685 35 140 44], ...
        'FontSize', settings.uiBodyFontSize, ...
        'Callback', @(~,~) cancelDialog());

    uiwait(d);

    function useValues()
        answer = cell(1, numel(edits));
        for ei = 1:numel(edits)
            answer{ei} = get(edits(ei), 'String');
        end
        closeDialog();
    end

    function cancelDialog()
        answer = {};
        closeDialog();
    end

    function closeDialog()
        if isvalid(d)
            delete(d);
        end
    end

end

function button = chooseYesNoDialog(titleText, messageText, settings)
% CHOOSEYESNODIALOG Display a modal yes/no selection dialog.

    button = '';
    d = dialog('Name', titleText, 'Position', [420 340 620 260]);
    set(d, 'CloseRequestFcn', @(~,~) selectButton('No'));
    movegui(d, 'center');

    uicontrol('Parent', d, ...
        'Style', 'text', ...
        'String', titleText, ...
        'Position', [30 190 560 35], ...
        'FontSize', settings.uiTitleFontSize, ...
        'FontWeight', 'bold');

    uicontrol('Parent', d, ...
        'Style', 'text', ...
        'String', messageText, ...
        'HorizontalAlignment', 'left', ...
        'Position', [45 120 530 45], ...
        'FontSize', settings.uiBodyFontSize);

    uicontrol('Parent', d, ...
        'Style', 'pushbutton', ...
        'String', 'Yes', ...
        'Position', [300 35 120 44], ...
        'FontSize', settings.uiBodyFontSize, ...
        'Callback', @(~,~) selectButton('Yes'));

    uicontrol('Parent', d, ...
        'Style', 'pushbutton', ...
        'String', 'No', ...
        'Position', [455 35 120 44], ...
        'FontSize', settings.uiBodyFontSize, ...
        'Callback', @(~,~) selectButton('No'));

    uiwait(d);

    function selectButton(value)
        button = value;
        if isvalid(d)
            delete(d);
        end
    end

end

function answer = askSingleNumberDialog(titleText, promptText, defaultValue, settings)
% ASKSINGLENUMBERDIALOG Collect a numeric value as dialog text.

    answer = {};
    d = dialog('Name', titleText, 'Position', [420 340 620 260]);
    set(d, 'CloseRequestFcn', @(~,~) cancelDialog());
    movegui(d, 'center');

    uicontrol('Parent', d, ...
        'Style', 'text', ...
        'String', titleText, ...
        'Position', [30 190 560 35], ...
        'FontSize', settings.uiTitleFontSize, ...
        'FontWeight', 'bold');

    uicontrol('Parent', d, ...
        'Style', 'text', ...
        'String', promptText, ...
        'HorizontalAlignment', 'left', ...
        'Position', [45 125 365 30], ...
        'FontSize', settings.uiBodyFontSize);

    editBox = uicontrol('Parent', d, ...
        'Style', 'edit', ...
        'String', defaultValue, ...
        'Position', [420 122 130 36], ...
        'FontSize', settings.uiBodyFontSize);

    uicontrol('Parent', d, ...
        'Style', 'pushbutton', ...
        'String', 'Use', ...
        'Position', [300 35 120 44], ...
        'FontSize', settings.uiBodyFontSize, ...
        'Callback', @(~,~) useValue());

    uicontrol('Parent', d, ...
        'Style', 'pushbutton', ...
        'String', 'Cancel', ...
        'Position', [455 35 120 44], ...
        'FontSize', settings.uiBodyFontSize, ...
        'Callback', @(~,~) cancelDialog());

    uiwait(d);

    function useValue()
        answer = {get(editBox, 'String')};
        closeDialog();
    end

    function cancelDialog()
        answer = {};
        closeDialog();
    end

    function closeDialog()
        if isvalid(d)
            delete(d);
        end
    end

end

function [analysisZones, wasCancelled] = chooseAnalysisZones(settings)
% CHOOSEANALYSISZONES Configure up to four rectangular zones in millimetres.

    wasCancelled = false;
    settings = ensureAnalysisSettings(settings);
    defaultZones = defaultAnalysisZones(settings);
    if isfield(settings, 'analysisZones') && ~isempty(settings.analysisZones)
        currentZones = normalizeAnalysisZones(settings.analysisZones, settings);
    else
        currentZones = defaultZones(1);
    end

    d = dialog('Name', 'Analysis zones', 'Position', [320 260 860 580]);
    set(d, 'CloseRequestFcn', @(~,~) cancelDialog());
    movegui(d, 'center');

    uicontrol('Parent', d, ...
        'Style', 'text', ...
        'String', 'Select analysis zones', ...
        'Position', [30 525 800 35], ...
        'FontSize', settings.uiTitleFontSize, ...
        'FontWeight', 'bold');

    uicontrol('Parent', d, ...
        'Style', 'text', ...
        'String', 'Number of zones (0-4):', ...
        'HorizontalAlignment', 'left', ...
        'Position', [40 480 230 28], ...
        'FontSize', settings.uiBodyFontSize);

    zoneCountEdit = uicontrol('Parent', d, ...
        'Style', 'edit', ...
        'String', num2str(min(max(numel(currentZones), 0), 4)), ...
        'Position', [275 478 70 34], ...
        'FontSize', settings.uiBodyFontSize, ...
        'Callback', @(~,~) updateZoneEnable());

    uicontrol('Parent', d, ...
        'Style', 'text', ...
        'String', 'X/Y are measured from the arena upper-left corner in mm.', ...
        'HorizontalAlignment', 'left', ...
        'Position', [380 480 430 28], ...
        'FontSize', settings.uiSmallFontSize);

    headerY = 435;
    headers = {'Zone', 'Name', 'X', 'Y', 'Width', 'Height'};
    headerX = [45 115 315 415 515 635];
    headerW = [55 170 75 75 95 95];
    for h = 1:numel(headers)
        uicontrol('Parent', d, ...
            'Style', 'text', ...
            'String', headers{h}, ...
            'HorizontalAlignment', 'left', ...
            'Position', [headerX(h) headerY headerW(h) 26], ...
            'FontSize', settings.uiBodyFontSize, ...
            'FontWeight', 'bold');
    end

    nameEdits = gobjects(1, 4);
    xEdits = gobjects(1, 4);
    yEdits = gobjects(1, 4);
    widthEdits = gobjects(1, 4);
    heightEdits = gobjects(1, 4);

    for z = 1:4
        if z <= numel(currentZones)
            zone = currentZones(z);
        else
            zone = defaultZones(z);
        end
        rowY = 388 - (z - 1) .* 70;
        uicontrol('Parent', d, ...
            'Style', 'text', ...
            'String', num2str(z), ...
            'HorizontalAlignment', 'left', ...
            'Position', [50 rowY + 8 40 28], ...
            'FontSize', settings.uiBodyFontSize);
        nameEdits(z) = uicontrol('Parent', d, ...
            'Style', 'edit', ...
            'String', zone.name, ...
            'Position', [115 rowY 170 36], ...
            'FontSize', settings.uiBodyFontSize);
        xEdits(z) = uicontrol('Parent', d, ...
            'Style', 'edit', ...
            'String', num2str(zone.xMm), ...
            'Position', [315 rowY 75 36], ...
            'FontSize', settings.uiBodyFontSize);
        yEdits(z) = uicontrol('Parent', d, ...
            'Style', 'edit', ...
            'String', num2str(zone.yMm), ...
            'Position', [415 rowY 75 36], ...
            'FontSize', settings.uiBodyFontSize);
        widthEdits(z) = uicontrol('Parent', d, ...
            'Style', 'edit', ...
            'String', num2str(zone.widthMm), ...
            'Position', [515 rowY 95 36], ...
            'FontSize', settings.uiBodyFontSize);
        heightEdits(z) = uicontrol('Parent', d, ...
            'Style', 'edit', ...
            'String', num2str(zone.heightMm), ...
            'Position', [635 rowY 95 36], ...
            'FontSize', settings.uiBodyFontSize);
    end

    uicontrol('Parent', d, ...
        'Style', 'text', ...
        'String', 'If zones = 0, dotted analysis-zone lines and zone-time outputs are omitted.', ...
        'HorizontalAlignment', 'left', ...
        'Position', [45 95 730 28], ...
        'FontSize', settings.uiSmallFontSize);

    uicontrol('Parent', d, ...
        'Style', 'pushbutton', ...
        'String', 'Use', ...
        'Position', [515 35 140 44], ...
        'FontSize', settings.uiBodyFontSize, ...
        'Callback', @(~,~) useZones());

    uicontrol('Parent', d, ...
        'Style', 'pushbutton', ...
        'String', 'Cancel', ...
        'Position', [685 35 140 44], ...
        'FontSize', settings.uiBodyFontSize, ...
        'Callback', @(~,~) cancelDialog());

    analysisZones = emptyAnalysisZones();
    updateZoneEnable();
    uiwait(d);

    if wasCancelled
        analysisZones = emptyAnalysisZones();
        return;
    end
    analysisZones = normalizeAnalysisZones(analysisZones, settings);

    function zoneCount = readZoneCount()
        zoneCount = floor(str2double(get(zoneCountEdit, 'String')));
        if ~isfinite(zoneCount)
            zoneCount = 0;
        end
        zoneCount = min(max(zoneCount, 0), 4);
        set(zoneCountEdit, 'String', num2str(zoneCount));
    end

    function updateZoneEnable()
        zoneCount = readZoneCount();
        for zi = 1:4
            if zi <= zoneCount
                state = 'on';
                bg = [1 1 1];
            else
                state = 'off';
                bg = [0.92 0.92 0.92];
            end
            set([nameEdits(zi), xEdits(zi), yEdits(zi), widthEdits(zi), heightEdits(zi)], ...
                'Enable', state, 'BackgroundColor', bg);
        end
    end

    function useZones()
        zoneCount = readZoneCount();
        if zoneCount == 0
            analysisZones = emptyAnalysisZones();
        else
            for zi = 1:zoneCount
                analysisZones(zi).name = strtrim(get(nameEdits(zi), 'String'));
                if isempty(analysisZones(zi).name)
                    analysisZones(zi).name = ['Zone' num2str(zi)];
                end
                analysisZones(zi).xMm = str2double(get(xEdits(zi), 'String'));
                analysisZones(zi).yMm = str2double(get(yEdits(zi), 'String'));
                analysisZones(zi).widthMm = str2double(get(widthEdits(zi), 'String'));
                analysisZones(zi).heightMm = str2double(get(heightEdits(zi), 'String'));
            end
        end
        if isvalid(d)
            delete(d);
        end
    end

    function cancelDialog()
        wasCancelled = true;
        if isvalid(d)
            delete(d);
        end
    end

end

function settings = ensureAnalysisSettings(settings)
% ENSUREANALYSISSETTINGS Fill missing settings using the existing defaults.

    if ~isfield(settings, 'arenaSizeMm') || ~isfinite(settings.arenaSizeMm) || settings.arenaSizeMm <= 0
        settings.arenaSizeMm = 400;
    end
    if ~isfield(settings, 'centerMarginMm') || ~isfinite(settings.centerMarginMm) || settings.centerMarginMm < 0
        settings.centerMarginMm = settings.arenaSizeMm ./ 4;
    end
    if ~isfield(settings, 'cornerZoneSizeMm') || ~isfinite(settings.cornerZoneSizeMm) || settings.cornerZoneSizeMm <= 0
        settings.cornerZoneSizeMm = settings.arenaSizeMm ./ 4;
    end
    if ~isfield(settings, 'cornerZoneMarginMm') || ~isfinite(settings.cornerZoneMarginMm) || settings.cornerZoneMarginMm < 0
        settings.cornerZoneMarginMm = settings.arenaSizeMm ./ 8;
    end
    if ~isfield(settings, 'trackColors') || isempty(settings.trackColors)
        settings.trackColors = {'#0072BD', '#D95319', '#77AC30', '#7E2F8E', '#EDB120'};
    end
    if ~isfield(settings, 'trackLineWidth') || ~isfinite(settings.trackLineWidth) || settings.trackLineWidth <= 0
        settings.trackLineWidth = 2;
    end
    if ~isfield(settings, 'uiFontSize') || ~isfinite(settings.uiFontSize) || settings.uiFontSize <= 0
        settings.uiFontSize = 16;
    end
    if ~isfield(settings, 'uiTitleFontSize') || ~isfinite(settings.uiTitleFontSize) || settings.uiTitleFontSize <= 0
        settings.uiTitleFontSize = max(18, settings.uiFontSize + 2);
    end
    if ~isfield(settings, 'uiBodyFontSize') || ~isfinite(settings.uiBodyFontSize) || settings.uiBodyFontSize <= 0
        settings.uiBodyFontSize = max(14, settings.uiFontSize - 2);
    end
    if ~isfield(settings, 'uiSmallFontSize') || ~isfinite(settings.uiSmallFontSize) || settings.uiSmallFontSize <= 0
        settings.uiSmallFontSize = max(12, settings.uiFontSize - 4);
    end
    if ~isfield(settings, 'analysisZones')
        defaultZones = defaultAnalysisZones(settings);
        settings.analysisZones = defaultZones(1);
    elseif isempty(settings.analysisZones)
        settings.analysisZones = emptyAnalysisZones();
    else
        settings.analysisZones = normalizeAnalysisZones(settings.analysisZones, settings);
    end

end

function zones = emptyAnalysisZones()
% EMPTYANALYSISZONES Return an empty zone structure with the required fields.

    zones = struct('name', {}, 'xMm', {}, 'yMm', {}, 'widthMm', {}, 'heightMm', {});

end

function zones = defaultAnalysisZones(settings)
% DEFAULTANALYSISZONES Construct the available default zone geometries.

    arenaSizeMm = settings.arenaSizeMm;
    centerMarginMm = min(settings.centerMarginMm, arenaSizeMm ./ 2 - 1);
    centerSizeMm = max(1, arenaSizeMm - centerMarginMm .* 2);
    cornerSizeMm = min(settings.cornerZoneSizeMm, arenaSizeMm);
    cornerMarginMm = min(settings.cornerZoneMarginMm, arenaSizeMm - cornerSizeMm);

    zones = struct( ...
        'name', {'Center', 'UpperRight', 'LowerLeft', 'FullArena'}, ...
        'xMm', {centerMarginMm, arenaSizeMm - cornerMarginMm - cornerSizeMm, cornerMarginMm, 0}, ...
        'yMm', {centerMarginMm, cornerMarginMm, arenaSizeMm - cornerMarginMm - cornerSizeMm, 0}, ...
        'widthMm', {centerSizeMm, cornerSizeMm, cornerSizeMm, arenaSizeMm}, ...
        'heightMm', {centerSizeMm, cornerSizeMm, cornerSizeMm, arenaSizeMm});

end

function zones = normalizeAnalysisZones(zones, settings)
% NORMALIZEANALYSISZONES Apply defaults and constrain zones to the arena.

    defaultZones = defaultAnalysisZones(settings);
    maxZones = min(max(numel(zones), 1), 4);
    arenaSizeMm = settings.arenaSizeMm;
    for z = 1:maxZones
        if ~isfield(zones, 'name') || isempty(strtrim(zones(z).name))
            zones(z).name = defaultZones(z).name;
        end
        if ~isfield(zones, 'xMm') || ~isfinite(zones(z).xMm)
            zones(z).xMm = defaultZones(z).xMm;
        end
        if ~isfield(zones, 'yMm') || ~isfinite(zones(z).yMm)
            zones(z).yMm = defaultZones(z).yMm;
        end
        if ~isfield(zones, 'widthMm') || ~isfinite(zones(z).widthMm) || zones(z).widthMm <= 0
            zones(z).widthMm = defaultZones(z).widthMm;
        end
        if ~isfield(zones, 'heightMm') || ~isfinite(zones(z).heightMm) || zones(z).heightMm <= 0
            zones(z).heightMm = defaultZones(z).heightMm;
        end
        zones(z).xMm = min(max(zones(z).xMm, 0), arenaSizeMm - 1);
        zones(z).yMm = min(max(zones(z).yMm, 0), arenaSizeMm - 1);
        zones(z).widthMm = min(max(zones(z).widthMm, 1), arenaSizeMm - zones(z).xMm);
        zones(z).heightMm = min(max(zones(z).heightMm, 1), arenaSizeMm - zones(z).yMm);
    end
    zones = zones(1:maxZones);

end

function label = sanitizeExcelLabel(label)
% SANITIZEEXCELLABEL Make a label suitable for the exported column headers.

    label = regexprep(strtrim(char(label)), '[^A-Za-z0-9_]', '_');
    if isempty(label)
        label = 'Zone';
    end

end

function outputPath = writeCompatibleVideo(preferredPath, frames, frameRate)
% WRITECOMPATIBLEVIDEO Try MPEG-4 output, then fall back to Motion JPEG AVI.

    [folder, name, ~] = fileparts(preferredPath);
    outputPath = fullfile(folder, [name '.mp4']);
    try
        v = VideoWriter(outputPath, 'MPEG-4');
        v.FrameRate = frameRate;
        v.Quality = 95;
        open(v);
        writeVideo(v, frames);
        close(v);
        if exist(outputPath, 'file') == 2 && dir(outputPath).bytes > 0
            return;
        end
    catch
        try
            close(v);
        catch
        end
    end

    outputPath = fullfile(folder, [name '.avi']);
    v = VideoWriter(outputPath, 'Motion JPEG AVI');
    v.FrameRate = frameRate;
    v.Quality = 95;
    open(v);
    writeVideo(v, frames);
    close(v);

end

function mouseColor = chooseMouseColor(settings)
% CHOOSEMOUSECOLOR Select light-on-dark or dark-on-light segmentation.

    mouseColor = '';
    d = dialog('Name', 'Mouse/background', 'Position', [450 500 720 290]);
    movegui(d, 'center');

    uicontrol('Parent', d, ...
        'Style', 'text', ...
        'String', 'Select mouse/background', ...
        'Position', [30 220 660 40], ...
        'FontSize', settings.uiTitleFontSize, ...
        'FontWeight', 'bold');

    uicontrol('Parent', d, ...
        'Style', 'pushbutton', ...
        'String', '<html><center>Black mouse<br>Light background</center></html>', ...
        'Position', [40 80 300 105], ...
        'FontSize', settings.uiFontSize, ...
        'Callback', @(~,~) selectMouse('Black mouse / light background'));

    uicontrol('Parent', d, ...
        'Style', 'pushbutton', ...
        'String', '<html><center>White mouse<br>Dark background</center></html>', ...
        'Position', [380 80 300 105], ...
        'FontSize', settings.uiFontSize, ...
        'Callback', @(~,~) selectMouse('White mouse / dark background'));

    uicontrol('Parent', d, ...
        'Style', 'pushbutton', ...
        'String', 'Cancel', ...
        'Position', [295 25 130 40], ...
        'FontSize', settings.uiBodyFontSize, ...
        'Callback', @(~,~) selectMouse(''));

    uiwait(d);

    function selectMouse(value)
        mouseColor = value;
        if isvalid(d)
            delete(d);
        end
    end

end

function th = chooseThreshold(frameRaw, detectLightMouse, imgfilenameBase, previewFrame, settings)
% CHOOSETHRESHOLD Display candidate thresholds for interactive selection.

    thresholdStart = 0.60;
    th = '';

    while true
        kk = thresholdStart + (0:(settings.thresholdPanelCount - 1)) .* settings.thresholdStep;
        kk = kk(kk > 0 & kk < 1);

        hThresholdFig = figure('Name','Choose threshold','NumberTitle','off');
        subplot(2,3,1)
        imshow(frameRaw, 'InitialMagnification', 'fit');
        axis image off;
        title(sprintf('Preview frame %d', previewFrame));

        for k = 1:length(kk)
            subplot(2,3,k+1)
            hImage = imshow(bwareaopen(im2bw(segmentInputFrame(frameRaw, detectLightMouse), kk(k)),50) * 255, 'InitialMagnification', 'fit');
            axis image off;
            set(gca,'tag',num2str(kk(k), '%.2f'))
            set(hImage, 'ButtonDownFcn', @(~,~) selectThreshold(num2str(kk(k), '%.2f')));
            title(['Threshold: ' num2str(kk(k), '%.2f')]);
        end

        set(findall(hThresholdFig, '-property', 'FontSize'), 'FontSize', settings.uiFontSize);
        sgtitle('Click one threshold image, or move to another threshold range.', 'FontSize', settings.uiTitleFontSize);

        setappdata(hThresholdFig, 'thresholdAction', '');
        setappdata(hThresholdFig, 'selectedThreshold', '');
        uicontrol('Parent', hThresholdFig, ...
            'Style', 'pushbutton', ...
            'String', {'Previous'; 'page'}, ...
            'Units', 'pixels', ...
            'Position', [190 18 170 56], ...
            'FontSize', settings.uiBodyFontSize, ...
            'Callback', @(~,~) selectAction('Previous page'));
        uicontrol('Parent', hThresholdFig, ...
            'Style', 'pushbutton', ...
            'String', {'Next'; 'page'}, ...
            'Units', 'pixels', ...
            'Position', [470 18 170 56], ...
            'FontSize', settings.uiBodyFontSize, ...
            'Callback', @(~,~) selectAction('Next page'));
        uicontrol('Parent', hThresholdFig, ...
            'Style', 'pushbutton', ...
            'String', 'Cancel', ...
            'Units', 'pixels', ...
            'Position', [750 25 110 42], ...
            'FontSize', settings.uiBodyFontSize, ...
            'Callback', @(~,~) selectAction('Cancel'));

        centerFigure(hThresholdFig, 900, 680);
        uiwait(hThresholdFig);

        if ~isvalid(hThresholdFig)
            th = '';
            return;
        end

        button = getappdata(hThresholdFig, 'thresholdAction');
        selectedThreshold = getappdata(hThresholdFig, 'selectedThreshold');

        if strcmp(button, 'Select')
            print(hThresholdFig,[imgfilenameBase '.tif'],'-dtiff','-r300');
            th = selectedThreshold;
            close(hThresholdFig);
            return;
        elseif strcmp(button, 'Previous page')
            thresholdStart = max(0.05, thresholdStart - settings.thresholdStep .* settings.thresholdPanelCount);
            close(hThresholdFig);
        elseif strcmp(button, 'Next page')
            thresholdStart = min(0.95 - (settings.thresholdPanelCount - 1) .* settings.thresholdStep, thresholdStart + settings.thresholdStep .* settings.thresholdPanelCount);
            close(hThresholdFig);
        elseif strcmp(button, 'Cancel') || isempty(button)
            close(hThresholdFig);
            th = '';
            return;
        else
            close(hThresholdFig);
            th = '';
            return;
        end
    end

    function selectThreshold(value)
        setappdata(hThresholdFig, 'selectedThreshold', value);
        setappdata(hThresholdFig, 'thresholdAction', 'Select');
        uiresume(hThresholdFig);
    end

    function selectAction(value)
        setappdata(hThresholdFig, 'thresholdAction', value);
        uiresume(hThresholdFig);
    end

end

function bwInput = segmentInputFrame(frameRaw, detectLightMouse)
% SEGMENTINPUTFRAME Use or invert image intensities for the selected polarity.

    if detectLightMouse
        bwInput = frameRaw;
    else
        bwInput = 255 - frameRaw;
    end

end

function [posVal, majlVal, minlVal, oriVal, eccVal, areaVal] = fallbackTrackingValues(c1, m1_majl, m1_minl, m1_ori, m1_ecc, m1_area, m, jj, xStart, yStart, xEnd, yEnd)
% FALLBACKTRACKINGVALUES Reuse the previous estimate after a tracking failure.
% If no preceding estimate is available, use the ROI midpoint and zero shape
% values. These are substituted values, not new detections.

    if jj > 1 && ~isempty(c1{m}) && size(c1{m}, 1) >= jj - 1 && any(c1{m}(jj-1,:))
        posVal = c1{m}(jj-1,:);
        majlVal = m1_majl{m}(jj-1);
        minlVal = m1_minl{m}(jj-1);
        oriVal = m1_ori{m}(jj-1);
        eccVal = m1_ecc{m}(jj-1);
        areaVal = m1_area{m}(jj-1);
    else
        posVal = floor([xStart + (xEnd - xStart) / 2, yStart + (yEnd - yStart) / 2]);
        majlVal = 0;
        minlVal = 0;
        oriVal = 0;
        eccVal = 0;
        areaVal = 0;
    end

end

function pos = customWait(hROI)

    % Wait for a double-click to confirm the rectangle.
    l = addlistener(hROI,'ROIClicked',@clickCallback);

    % Pause interaction until the ROI callback resumes the figure.
    uiwait;

    % Remove the temporary click listener.
    delete(l);

    % Return the selected [x y width height] in image pixels.
    pos = hROI.Position;

end

function clickCallback(~,evt)

    if strcmp(evt.SelectionType,'double')
        uiresume;
    end

end

function logf(varargin)
% LOGF Print a time-stamped message to the Command Window.
    message = sprintf(varargin{1}, varargin{2:end});
    str = ['[' datestr(now(), 'HH:MM:SS') '] ' message];
    disp(str);
end

function [X,Y]=calculateEllipse(x, y, a, b, angle, steps)
% CALCULATEELLIPSE Generate outline points from ellipse parameters.
%   x, y: centre coordinates in image pixels.
%   a: semimajor-axis length in pixels.
%   b: semiminor-axis length in pixels.
%   angle: orientation in degrees.
%   steps: optional number of points used to sample the outline.

    narginchk(5, 6);
    if nargin<6, steps = 36; end

    beta = -angle * (pi / 180);
    sinbeta = sin(beta);
    cosbeta = cos(beta);

    alpha = linspace(0, 360, steps)' .* (pi / 180);
    sinalpha = sin(alpha);
    cosalpha = cos(alpha);

    X = x + (a * cosalpha * cosbeta - b * sinalpha * sinbeta);
    Y = y + (a * cosalpha * sinbeta + b * sinalpha * cosbeta);

    if nargout==1, X = [X Y]; end

end
