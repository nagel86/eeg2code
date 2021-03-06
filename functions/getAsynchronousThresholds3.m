function [maxTrialDuration,pvalthreshold] = getAsynchronousThresholds3(path,subject,runs,ncruns,quanti,testnc)

    
    windowSize = 150;
    trialdurations = (300:150:1800);
    %minTrialDuration = 150;
    %maxTrialDuration = 900;
    
    subjectpath = sprintf('%s/%s001/',path,subject);

    bla=load('targetdelays.mat');
    targetdelays = bla.targetdelays;
    load([subjectpath 'spatialFilter.mat']);
    load([subjectpath 'trainedModel.mat']);
%%
    if exist([subjectpath 'thresholdData.mat'], 'file') == 2
        load([subjectpath 'thresholdData.mat']);
    else
        run = 0;
        %predData = cell(1,length(trialdurations));
        pvalDataCorrect = cell(1,length(trialdurations));
        pvalDataWrong = cell(1,length(trialdurations));
        for testrun = runs
            filename = sprintf('%s%sS001R%02i.dat',subjectpath,subject,testrun);
            [signal, bci_StateSamples, params]=load_bcidat(filename,'-calibrated');

            run = run+1;

            pport =  double([bci_StateSamples.DigitalInput1,...
                      bci_StateSamples.DigitalInput2,...
                      bci_StateSamples.DigitalInput3,...
                      bci_StateSamples.DigitalInput4,...
                      bci_StateSamples.DigitalInput5,...
                      bci_StateSamples.DigitalInput6,...
                      bci_StateSamples.DigitalInput7,...
                      bci_StateSamples.DigitalInput8]);


            channels = params.TransmitChList.NumericValue;
            signal = signal(:,channels)';
            settings = struct();
            settings.filterType = filterType;

            trialstarts = find(diff(pport(:,4))==1)+1;
            trialends = find(diff(pport(:,4))==-1);


            load([filename '_bits.mat']);
            [~,bitOrder]=sort(bits(:,1));
            bits = bits(bitOrder,2:end);
            for trial = 1:length(trialstarts)
                trialstart = trialstarts(trial);
                trialstop = trialends(trial);
                bitchanges = pport(trialstart:trialstop,3)';
                [samples,bits] = upsampleBits(bits,bitchanges,[]);

                trialdata = applySpatialFilter(signal(:,trialstart:trialstop)',spfilter,settings)';

                data_x_timelag = zeros(size(trialdata,1),windowSize);
                for t=1:150
                    data_x_timelag(:,t) = circshift(trialdata,[-t 0])';
                end

                predSamples = trainedmodel(2:end)*data_x_timelag'+trainedmodel(1);
                predSamplesTrimmed = predSamples(1:end-windowSize);
                samples = samples(:,1:end-windowSize);
                %minsize = min(size(samples,2), size(predSamplesTrimmed,2));
                %samples = samples(:,1:minsize);
                %predSamplesTrimmed = predSamplesTrimmed(1:minsize);
                numWindows = min(50,floor((length(predSamplesTrimmed)-(trialdurations(end)-windowSize))/10));
                %start parpool
                startParPool(length(trialdurations))
                parfor trialdur = 1:length(trialdurations)
                    maxtrialend = (trialdurations(trialdur)-windowSize)+numWindows*10;
                    subtrialends = (trialdurations(trialdur):10:length(predSamples))-windowSize;
                    subtrialends = subtrialends(randperm(length(subtrialends),numWindows));
                    targetPred = zeros(1,length(subtrialends));
                    targetPval = zeros(1,length(subtrialends));

                    for subtrialcounter=1:length(subtrialends)
                        subtrialend = subtrialends(subtrialcounter);
                        subtrialstart = max(1,subtrialend-(trialdurations(trialdur)-windowSize)+1);
                        predsamples = predSamplesTrimmed(subtrialstart:subtrialend);


                        targetPVals = zeros(1,size(bits,2));
                        for target=1:size(bits,2)
                            targetdelay = targetdelays(target);
                            eegshift = round(targetdelay * 10);

                            targetsamples = samples(target,subtrialstart:subtrialend)';

                            [~, targetPVals(target)] = ...
                                corr(targetsamples,circshift(predsamples,[0 -eegshift])','tail','right');
                        end

                        [targetPval(subtrialcounter),targetPred(subtrialcounter)] = min(targetPVals);
                    end

                    %predData{trialdur} = [predData{trialdur},mean(targetPred==trial)];
                    pvalDataCorrect{trialdur} = [pvalDataCorrect{trialdur},targetPval(targetPred==trial)];
                    pvalDataWrong{trialdur} = [pvalDataWrong{trialdur},targetPval(targetPred~=trial)];
                end
            end
            fprintf('Run %.0f\n',run);
        end

        save([subjectpath 'thresholdData.mat'], 'pvalDataCorrect','pvalDataWrong');
    end
    %%
    %pvalthreshold=min(cellfun(@(x) ifelse(isempty(x), 1,min(x)),pvalDataWrong));
    pvalthreshold = quantile(horzcat(pvalDataWrong{:}),quanti);
    maxTrialDuration=trialdurations(find(cellfun(@(x) ifelse(isempty(x),0,mean(x<=pvalthreshold)),pvalDataCorrect)>=0.99,1,'first'));
    if isempty(maxTrialDuration), maxTrialDuration = trialdurations(end); end
    
    if testnc
        %% test non-control
        ncpvals = [];
        for testrun = ncruns
            filename = sprintf('%s%sS001R%02i.dat',subjectpath,subject,testrun);
            [signal, bci_StateSamples, params]=load_bcidat(filename,'-calibrated');


            pport =  double([bci_StateSamples.DigitalInput1,...
                      bci_StateSamples.DigitalInput2,...
                      bci_StateSamples.DigitalInput3,...
                      bci_StateSamples.DigitalInput4,...
                      bci_StateSamples.DigitalInput5,...
                      bci_StateSamples.DigitalInput6,...
                      bci_StateSamples.DigitalInput7,...
                      bci_StateSamples.DigitalInput8]);


            channels = params.TransmitChList.NumericValue;
            signal = signal(:,channels)';
            settings = struct();
            settings.filterType = filterType;

            trialstarts = find(diff(pport(:,4))==1)+1;
            trialends = find(diff(pport(:,4))==-1);
            if length(trialends) < length(trialstarts)
                trialends(end+1) = size(signal,2);
            end
            load([filename '_bits.mat']);
            [~,bitOrder]=sort(bits(:,1));
            bits = bits(bitOrder,2:end);

            for trial = 1:length(trialstarts)
                trialstart = trialstarts(trial);
                trialstop = trialends(trial);
                bitchanges = pport(trialstart:trialstop,3)';
                bitends = [find(diff(bitchanges)~=0),length(bitchanges)];
                [samples,bits] = upsampleBits(bits,bitchanges,[]);
    %             if trial <= size(samples,1)
    %                 continue;
    %             end
                trialdata = applySpatialFilter(signal(:,trialstart:trialstop)',spfilter,settings)';

                data_x_timelag = zeros(size(trialdata,1),windowSize);
                for t=1:150
                    data_x_timelag(:,t) = circshift(trialdata,[-t 0])';
                end

                predSamples = trainedmodel(2:end)*data_x_timelag'+trainedmodel(1);
                predSamplesTrimmed = predSamples(1:end-windowSize);
                samples = samples(:,1:end-windowSize);

                bitends = bitends(bitends>=trialdurations(1));
                ncpval = zeros(1,length(bitends));
                parfor subtrialind = 1:length(bitends)
                    subtrialend = bitends(subtrialind)-windowSize;
                    subtrialstart=max(1,subtrialend-(maxTrialDuration-windowSize));
                    predsamples = predSamplesTrimmed(subtrialstart:subtrialend);

                    targetPVals = zeros(1,size(bits,2));
                    for target=1:size(bits,2)
                        targetdelay = targetdelays(target);
                        eegshift = round(targetdelay * 10);

                        targetsamples = samples(target,subtrialstart:subtrialend)';

                        [~, targetPVals(target)] = ...
                            corr(targetsamples,circshift(predsamples,[0 -eegshift])','tail','right');
                    end
                    ncpval(subtrialind) = min(targetPVals);
                end
                ncpvals = [ncpvals,ncpval];
            end
        end

        if sum(ncpvals<=pvalthreshold)
            pvalthreshold = min(ncpvals);
        end
    end
end

