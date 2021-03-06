function TrialInfo = ASF_ShowTrialMultiResponse(atrial, windowPtr, Stimuli, Cfg)
%function TrialInfo = ASF_ShowTrialMultiResponse(atrial, windowPtr, Stimuli, Cfg)
%SHOWTRIAL VERSION THAT ALLOWS MULTIPLE RESPONSES WHILE BEING BETWEEN PAGES
%atrial.startRTonPage:atrial.endRTonPage

if ~isfield(Cfg.responseSettings, 'multiResponse'), Cfg.responseSettings.multiResponse = 'allowSingleResponse'; else end;
if ~isfield(Cfg, 'feedbackResponseNumber'), Cfg.feedbackResponseNumber = 1; else end; %IF YOU WANT TO GIVE FEEDBACK REFER BY DEFAULT TO THE FIRST RESPONSE GIVEN IN THIS TRIAL
%SAVE TIME BY ALLOCATING ALL VARIABLES UPFRONT

% VBLTimestamp system time (in seconds) when the actual flip has happened
% StimulusOnsetTime An estimate of Stimulus-onset time
% FlipTimestamp is a timestamp taken at the end of Flip's execution
VBLTimestamp = 0; StimulusOnsetTime = 0; FlipTimestamp = 0; Missed = 0;
Beampos = 0;

StartRTMeasurement = 0; EndRTMeasurement = 0;
timing = [0, VBLTimestamp, StimulusOnsetTime, FlipTimestamp, Missed, Beampos];
nPages = length(atrial.pageNumber);
timing(nPages, end) = 0;
this_response = [];

%ON PAGES WITH WITH RESPONSE COLLECTION MAKE SURE THE CODE RETURNS IN TIME
%BEFORE THE NEXT VERTICAL BLANK. FOR EXAMPLE IF THE RESPONSE WINDOW IS 1000
%ms TOLERANCE MAKES THE RESPONSE COLLECTION CODE RETURN AFTER 1000ms-0.3
%FRAMES, I.E. AFTER 995 ms AT 60Hz
toleranceSec = Cfg.Screen.monitorFlipInterval*0.2; %was .3

%HOWEVER, THIS MUST NOT BE LONGER THAN ONE FRAME
%DURATION. EXPERIMENTING WITH ONE QUARTER OF A FRAME
responseGiven = 0;
this_response.key = [];
this_response.RT = [];


%--------------------------------------------------------------------------
%TRIAL PRESENTATION HAS SEVERAL PHASES
% 1) WAIT FOR THE RIGHT TIME TO START TRIAL PRESENTATION. THIS MAY BE
%    IMMEDIATELY OR USER DEFINED (E.G. IN fMRI EXPERIMENTS)
%
% 2) LOOP THROUGH PAGE PRESENTATIONS WITHOUT RESPONSE COLLECTION
%
% 3) LOOP THROUGH PAGE PRESENTATIONS WHILE CHECKING FOR USER INPUT/RESPONSES
%
% 4) LOOP THROUGH PAGE PRESENTATIONS WITHOUT RESPONSE COLLECTION
%    (AFTER RESPONSE HAS BEEN GIVEN)
%
% 5) FEEDBACK
%--------------------------------------------------------------------------

%IF YOU WANT TO DO ANY OFFLINE STIMULUS RENDERING (I.E. BEFORE THE TRIAL
%STARTS), PUT THAT CODE HERE
responseCounter = 0; %COUNTS THE NUMBER OF RESPONSES GIVEN WITHIN THE ALLLOWED PERIOD
%LOG DATE AND TIME OF TRIAL
strDate = datestr(now); %store when trial was presented

%--------------------------------------------------------------------------
% PHASE 1) WAIT FOR THE RIGHT TIME TO START TRIAL PRESENTATION. THIS MAY BE
% IMMEDIATELY OR USER DEFINED (E.G. IN fMRI EXPERIMENTS)
%--------------------------------------------------------------------------

% %JS METHOD: LOOP
% %IF EXTERNAL TIMING REQUESTED (e.g. fMRI JITTERING)
% if Cfg.useTrialOnsetTimes
%     while((GetSecs- Cfg.experimentStart) < atrial.tOnset)
%     end
% end
% %LOG TIME OF TRIAL ONSET WITH RESPECT TO START OF THE EXPERIMENT
% %USEFUL FOR DATA ANALYSIS IN fMRI
% tStart = GetSecs - Cfg.experimentStart;

%SUGGESTED METHOD: TIMED WAIT
%IF EXTERNAL TIMING REQUESTED (e.g. fMRI JITTERING)
if Cfg.useTrialOnsetTimes
    wakeupTime = WaitSecs('UntilTime', Cfg.experimentStart + atrial.tOnset);
else
    wakeupTime = GetSecs;
end
%LOG TIME OF TRIAL ONSET WITH RESPECT TO START OF THE EXPERIMENT
%USEFUL FOR DATA ANALYSIS IN fMRI
tStart = wakeupTime - Cfg.experimentStart;


if Cfg.Eyetracking.doDriftCorrection
    EyelinkDoDriftCorrect(Cfg.Eyetracking.el);
end

%--------------------------------------------------------------------------
%END OF PHASE 1
%--------------------------------------------------------------------------

%MESSAGE TO EYELINK
Cfg = ASF_sendMessageToEyelink(Cfg, 'TRIALSTART');

%--------------------------------------------------------------------------
% PHASE 2) LOOP THROUGH PAGE PRESENTATIONS WITHOUT RESPONSE COLLECTION
%--------------------------------------------------------------------------
%CYCLE THROUGH PAGES FOR THIS TRIAL
atrial.nPages = length(atrial.pageNumber);
for i = 1:atrial.startRTonPage-1
    if (i > atrial.nPages)
        break;
    else
        %PUT THE APPROPRIATE TEXTURE ON THE BACK BUFFER
        Screen('DrawTexture', windowPtr, Stimuli.tex(atrial.pageNumber(i)));
        
        %PRESERVE BACK BUFFER IF THIS TEXTURE IS TO BE SHOWN
        %AGAIN AT THE NEXT FLIP
        bPreserveBackBuffer = atrial.pageDuration(i) > 1;
        
        %FLIP THE CONTENT OF THIS PAGE TO THE DISPLAY AND PRESERVE IT IN THE
        %BACKBUFFER IN CASE THE SAME IMAGE IS TO BE FLIPPED AGAIN TO THE SCREEN
        [VBLTimestamp StimulusOnsetTime FlipTimestamp Missed Beampos] =...
            ASF_xFlip(windowPtr, Stimuli.tex(atrial.pageNumber(i)),...
            Cfg, bPreserveBackBuffer);
        
        %SET TRIGGER (PARALLEL PORT AND EYELINK)
        ASF_setTrigger(Cfg, atrial.pageNumber(i));
        
        
        %LOG WHEN THIS PAGE APPEARED
        timing(i, 1:6) = [atrial.pageDuration(i), VBLTimestamp,...
            StimulusOnsetTime FlipTimestamp Missed Beampos];
        
        
        %WAIT OUT STIMULUS DURATION IN FRAMES. WE USE PAGE FLIPPING RATHER
        %THAN A TIMER WHENEVER POSSIBLE BECAUSE GRAPHICS BOARDS PROVIDE
        %EXCELLENT TIMING; THIS IS THE REASON WHY WE MAY WANT TO KEEP A
        %STIMULUS IN THE BACKBUFFER (NONDESTRUCTIVE PAGE FLIPPING)
        %NOT ALL GRAPHICS CARDS CAN DO THIS. FOR CARDS WITHOUT AUXILIARY
        %BACKBUFFERS WE COPY THE TEXTURE EXPLICITLY ON THE BACKBUFFER AFTER
        %IT HAS BEEN DESTROYED BY FLIPPING
        nFlips = atrial.pageDuration(i) - 1; %WE ALREADY FLIPPED ONCE
        for FlipNumber = 1:nFlips
            %PRESERVE BACK BUFFER IF THIS TEXTURE IS TO BE SHOWN
            %AGAIN AT THE NEXT FLIP
            bPreserveBackBuffer = FlipNumber < nFlips;
            
            %FLIP THE CONTENT OF THIS PAGE TO THE DISPLAY AND PRESERVE IT
            %IN THE BACKBUFFER IN CASE THE SAME IMAGE IS TO BE FLIPPED
            %AGAIN TO THE SCREEN
            ASF_xFlip(windowPtr, Stimuli.tex(atrial.pageNumber(i)),...
                Cfg, bPreserveBackBuffer);
        end
    end
end
%--------------------------------------------------------------------------
%END OF PHASE 2
%--------------------------------------------------------------------------

%--------------------------------------------------------------------------
% PHASE 3) LOOP THROUGH PAGE PRESENTATIONS WHILE CHECKING FOR USER
%          INPUT/RESPONSES
%--------------------------------------------------------------------------
%SPECIAL TREATMENT FOR THE DISPLAY PAGES ON WHICH WE ALLOW REACTIONS
allowResponse = 1;
responseCounter = 0;
DEBUGMSG = 1;
if DEBUGMSG
    fprintf(1, '\n');
end
for i = atrial.startRTonPage:atrial.endRTonPage
    if (i > atrial.nPages)
        break;
    else
        
        %PUT THE APPROPRIATE TEXTURE ON THE BACK BUFFER
        Screen('DrawTexture', windowPtr, Stimuli.tex(atrial.pageNumber(i)));
        
        %DO NOT PUT THIS PAGE AGAIN ON THE BACKBUFFER, WE WILL WAIT IT OUT
        %USING THE TIMER NOT FLIPPING
        bPreserveBackBuffer = 0;
        
        %FLIP THE CONTENT OF THIS PAGE TO THE DISPLAY AND PRESERVE IT
        %IN THE BACKBUFFER IN CASE THE SAME IMAGE IS TO BE FLIPPED
        %AGAIN TO THE SCREEN
        [VBLTimestamp StimulusOnsetTime FlipTimestamp Missed Beampos] =...
            ASF_xFlip(windowPtr, Stimuli.tex(atrial.pageNumber(i)),...
            Cfg, bPreserveBackBuffer);
        
        %SET TRIGGER
        ASF_setTrigger(Cfg, atrial.pageNumber(i));
        
        if i == atrial.startRTonPage
            StartRTMeasurement = VBLTimestamp;
        end
        
        %STORE TIME OF PAGE FLIPPING FOR DIAGNOSTIC PURPOSES
        timing(i, 1:6) = [atrial.pageDuration(i), VBLTimestamp,...
            StimulusOnsetTime, FlipTimestamp, Missed, Beampos];
        
        pageDuration_in_sec =...
            atrial.pageDuration(i)*Cfg.Screen.monitorFlipInterval;

        if DEBUGMSG
            strMsg = sprintf('PAGE %03d SHOWN StimulusOnsetTime: %12.3f, pageDuration_in_sec: %5.3f', i, StimulusOnsetTime, pageDuration_in_sec);
            logMsg(i, strMsg);
        end
    
        if allowResponse
            if DEBUGMSG
                strMsg = sprintf('ALLOW RESPONSE');
                logMsg(i, strMsg);
            end

            %---------------------------
            %WITH RESPONSE COLLECTION
            %---------------------------
            if DEBUGMSG
                strMsg = sprintf('CHECK FOR RESPONSE WITH %5.3f secs timeout', pageDuration_in_sec - toleranceSec);
                logMsg(i, strMsg);
            end

            [x, y, buttons, t0, t1] =...
                ASF_waitForResponse(Cfg, pageDuration_in_sec - toleranceSec);
            
            if DEBUGMSG
                strMsg = sprintf('RETURNED FROM RESPONSE CHECKING AFTER %5.3f secs (%5.3f ms after start of response collection)', t1 - t0, (t1 - StartRTMeasurement)*1000);
                logMsg(i, strMsg);
            end
            if any(buttons)
                if DEBUGMSG
                    strMsg = sprintf('A RESPONSE BUTTON HAS BEEN PRESSED');
                    logMsg(i, strMsg);
                    fprintf(1, 'Buttons: ');
                    fprintf(1, '%d ', buttons);
                    fprintf(1, '\n');
                end

                %BUTTON HAS BEEN PRESSED
                %THIS ALSO MEANS THAT THE PAGE MAY HAVE TO BE SHOWN FOR LONGER.
                %IF MULTIPLE RESPONSES ARE ALLOWED EVEN WITH MORE RESPONSE COLLECTION
                
                %INCREASE RESPONSE COUNTER
                responseCounter = responseCounter + 1;
                if DEBUGMSG
                    strMsg = sprintf('THIS IS THE %3d th RESPONSE IN THIS TRIAL', responseCounter);
                    logMsg(i, strMsg);
                end

                %FIND WHICH BUTTON IT WAS
                this_response.key(responseCounter) = find(buttons);
                %COMPUTE RESPONSE TIME
                this_response.RT(responseCounter) = (t1 - StartRTMeasurement)*1000;
                switch Cfg.responseSettings.multiResponse
                    case 'responseTerminatesTrial'
                        %NEED TO WORK ON THIS PART
                        break;
                    case 'allowMultipleResponses'
                        if DEBUGMSG
                            strMsg = sprintf('ALLOW MULTIPLE RESPONSES');
                            logMsg(i, strMsg);
                        end

                        %WE CHECK FOR MORE RESPONSES AS LONG AS THE PAGE HAS
                        %NOT EXPIRED
                        %T1 LOOKS STILL WRONG WHAT IS IT A RELATIVE OR AN
                        %ABSOLUTE TIME?
                        tRemain = pageDuration_in_sec - ( t1 - StimulusOnsetTime);
                        tEnd = StimulusOnsetTime + tRemain; %ABSOLUTE TIME
                        %CHECK WHETHER PAGE HAS EXPIRED
                        boolContinue = GetSecs < tEnd;
                        while  (boolContinue)
                            if DEBUGMSG
                                strMsg = sprintf('CHECK FOR RESPONSE WITH %5.3f secs timeout', tRemain - toleranceSec);
                                logMsg(i, strMsg);
                            end

                            [x, y, buttons, t0, t1, extraKey] =...
                                ASF_waitForResponse(Cfg, tRemain - toleranceSec);
                            if any(buttons)
                                if DEBUGMSG
                                    strMsg = sprintf('A RESPONSE BUTTON HAS BEEN PRESSED');
                                    logMsg(i, strMsg);
                                end

                                %INCREASE RESPONSE COUNTER
                                responseCounter = responseCounter + 1;
                                if DEBUGMSG
                                    strMsg = sprintf('THIS IS THE %3d th RESPONSE IN THIS TRIAL', responseCounter);
                                    logMsg(i, strMsg);
                                end
                                
                                %FIND WHICH BUTTON IT WAS
                                this_response.key(responseCounter) = find(buttons);
                                %COMPUTE RESPONSE TIME
                                this_response.RT(responseCounter) = (t1 - StartRTMeasurement)*1000;
                                tRemain = pageDuration_in_sec - ( t1 - StimulusOnsetTime);
                                %CHECK WHETHER PAGE HAS EXPIRED
                                boolContinue = GetSecs < (tEnd- toleranceSec);
                            else
                                %NO BUTTON PRESSED, WHAT IS tRemain NOW?
                                if DEBUGMSG
                                    strMsg = sprintf('%5.3f SECONDS HAVE PASSED. ', t1-t0); 
                                    logMsg(i, strMsg);
                                    strMsg = sprintf('NO ADDITIONAL RESPONSE BUTTON HAS BEEN PRESSED');
                                    logMsg(i, strMsg);
                                end

                                tRemain = 0;
                                boolContinue = 0;
                                junk = GetSecs;
                                strMsg = sprintf('%RC: 3d SOn: %12.2f StartRT %12.2f current: %12.2f', responseCounter, StimulusOnsetTime, StartRTMeasurement, junk);
                                logMsg(i, strMsg);
                            end
                        end
                       
                    case 'allowSingleResponse'
                        if DEBUGMSG
                            strMsg = sprintf('ALLOW ONLY SINGLE RESPONSE');
                            logMsg(i, strMsg);
                        end

                        %A BUTTON HAS BEEN PRESSED BEFORE TIMEOUT
                        allowResponse = 0; %NO FURTHER RESPONSE ALLOWED IN THIS TRIAL
                        %WAIT OUT THE REMAINDER OF THE STIMULUS DURATION WITH
                        %MARGIN OF toleranceSec
                        wakeupTime = WaitSecs('UntilTime',...
                            StimulusOnsetTime + pageDuration_in_sec - toleranceSec);
                end
            else
                if DEBUGMSG
                    strMsg = sprintf('NO BUTTON ON PAGE %d', i);
                    logMsg(i, strMsg);
                end

            end
        else
            %-----------------------------------
            %NO RESPONSE COLLECTION ON THIS PAGE
            %This can occur when
            %response period spans multiple pages, only one response
            %allowed, and response already given on a previous page
            %-----------------------------------
            if DEBUGMSG
                strMsg = sprintf('DO NOT ALLOW RESPONSE');
                logMsg(i, strMsg);
            end

            %MAKE APPROPRIATE NUMBER OF NONDESTRUCTIVE FLIPS
            nFlips = atrial.pageDuration(i) - 1; %WE ALREADY FLIPPED ONCE
            for FlipNumber = 1:nFlips
                %PRESERVE BACK BUFFER IF THIS TEXTURE IS TO BE SHOWN
                %AGAIN AT THE NEXT FLIP
                bPreserveBackBuffer = FlipNumber < nFlips;
                
                %FLIP THE CONTENT OF THIS PAGE TO THE DISPLAY AND PRESERVE IT
                %IN THE BACKBUFFER IN CASE THE SAME IMAGE IS TO BE FLIPPED
                %AGAIN TO THE SCREEN
                ASF_xFlip(windowPtr, Stimuli.tex(atrial.pageNumber(i)),...
                    Cfg, bPreserveBackBuffer);
            end
        end
    end
end
%--------------------------------------------------------------------------
%END OF PHASE 3
%--------------------------------------------------------------------------

%--------------------------------------------------------------------------
% PHASE 4) LOOP THROUGH PAGE PRESENTATIONS WITHOUT RESPONSE COLLECTION
% (AFTER RESPONSE HAS BEEN GIVEN) SAME AS PHASE 2
%--------------------------------------------------------------------------
%OTHER PICS
for i = (atrial.endRTonPage+1):nPages
    if (i > atrial.nPages)
        break;
    else
        %PUT THE APPROPRIATE TEXTURE ON THE BACK BUFFER
        Screen('DrawTexture', windowPtr, Stimuli.tex(atrial.pageNumber(i)));
        
        %PRESERVE BACK BUFFER IF THIS TEXTURE IS TO BE SHOWN
        %AGAIN AT THE NEXT FLIP
        bPreserveBackBuffer = atrial.pageDuration(i) > 1;
        
        %FLIP THE CONTENT OF THIS PAGE TO THE DISPLAY AND PRESERVE IT
        %IN THE BACKBUFFER IN CASE THE SAME IMAGE IS TO BE FLIPPED
        %AGAIN TO THE SCREEN
        [VBLTimestamp StimulusOnsetTime FlipTimestamp Missed Beampos] =...
            ASF_xFlip(windowPtr, Stimuli.tex(atrial.pageNumber(i)),...
            Cfg, bPreserveBackBuffer);
        
        %SET TRIGGER (PARALLEL PORT AND EYELINK)
        ASF_setTrigger(Cfg, atrial.pageNumber(i));
        
        
        %LOG WHEN THIS PAGE APPEARED
        timing(i, 1:6) = [atrial.pageDuration(i), VBLTimestamp,...
            StimulusOnsetTime FlipTimestamp Missed Beampos];
        
        %WAIT OUT STIMULUS DURATION IN FRAMES.
        nFlips = atrial.pageDuration(i) - 1; %WE ALREADY FLIPPED ONCE
        for FlipNumber = 1:nFlips
            %PRESERVE BACK BUFFER IF THIS TEXTURE IS TO BE SHOWN
            %AGAIN AT THE NEXT FLIP
            bPreserveBackBuffer = FlipNumber < nFlips;
            
            %FLIP THE CONTENT OF THIS PAGE TO THE DISPLAY AND PRESERVE IT
            %IN THE BACKBUFFER IN CASE THE SAME IMAGE IS TO BE FLIPPED
            %AGAIN TO THE SCREEN
            ASF_xFlip(windowPtr, Stimuli.tex(atrial.pageNumber(i)),...
                Cfg, bPreserveBackBuffer);
        end
    end
end

%--------------------------------------------------------------------------
%END OF PHASE 4
%--------------------------------------------------------------------------

%--------------------------------------------------------------------------
% PHASE 5) FEEDBACK
%--------------------------------------------------------------------------
%IF YOU WANT TO FORCE A RESPONSE
if Cfg.waitUntilResponseAfterTrial && ~responseGiven
    [x, y, buttons, t0, t1] = ASF_waitForResponse(Cfg, 10);
    
    if any(buttons)
        %A BUTTON HAS BEEN PRESSED BEFORE TIMEOUT
        responseGiven = 1;  %#ok<NASGU>
        %FINDO OUT WHICH BUTTON IT WAS
        this_response.key = find(buttons);
        %COMPUTE RESPONSE TIME
        this_response.RT = (t1 - StartRTMeasurement)*1000;
    end
end

%TRIAL BY TRIAL FEEDBACK
if Cfg.feedbackTrialCorrect || Cfg.feedbackTrialError
    ASF_trialFeeback(...
        this_response.key(Cfg.feedbackResponseNumber) == atrial.CorrectResponse, Cfg, windowPtr);
end

%--------------------------------------------------------------------------
%END OF PHASE 5
%--------------------------------------------------------------------------


%PACK INFORMATION ABOUT THIS TRIAL INTO STRUCTURE TrialInfo (THE RETURN
%ARGUMENT). PLEASE MAKE SURE THAT TrialInfo CONTAINS THE FIELDS:
%   trial
%   datestr
%   tStart
%   Response
%   timing
%   StartRTMeasurement
%   EndRTMeasurement
%OTHERWISE DIAGNOSTIC PROCEDURES OR ROUTINES FOR DATA ANALYSIS MAIGHT FAIL
TrialInfo.trial = atrial;  %REQUESTED PAGE NUMBERS AND DURATIONS
TrialInfo.datestr = strDate; %STORE WHEN THIS HAPPENED
TrialInfo.tStart = tStart; %TIME OF TRIAL-START
TrialInfo.Response = this_response; %KEY AND RT
TrialInfo.timing = timing; %TIMING OF PAGES
TrialInfo.StartRTMeasurement = StartRTMeasurement; %TIMESTAMP START RT
TrialInfo.EndRTMeasurement = EndRTMeasurement; %TIMESTAMP END RT

function logMsg(iPage, strMsg)
persistent lastTime;
if isempty(lastTime)
    lastTime = GetSecs;
end

curTime = GetSecs;
fprintf('%12.3f\t%8d\tPAGE %04d\t MSG: %s\n', curTime, fix((curTime-lastTime)*1000), iPage, strMsg);
lastTime = curTime;