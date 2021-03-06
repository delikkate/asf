function ExpInfo = runExampleCentral
%THIS PROGRAM PUTS TOGETHER 
% -CREATION OF TRIAL DEFINITION FILE (TRD)
% -RUNNING A MASKED PRIMING EXPERIMENT IN WHICH STIMULI ARE
%  CENTRALLY PRESENTED
% -POSTHOC CHECKING OF TIMING ERRORS
% -SIMPLE FACTORIAL DATA ANALYSIS
%%ASF Jens Schwarzbach

Cfg = []; %DEFAULT CONFIGURATION

projectName = 'exampleCentral';
stdName = 'example.std';
logName = projectName;

%MAKE TRD FILE
trdName = makeExampleCentralTrd(projectName);

%RUN EXPERIMENT
ExpInfo = ASF(stdName, trdName, logName, Cfg);

ASF_timingDiagnosis(ExpInfo); %CONTROL TIMING 