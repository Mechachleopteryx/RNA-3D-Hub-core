function [MM] = aAnalyzeExtraNucleotides(MM, loop_ids)

    disp('Analyzing extra nucleotides...');
    
    Location = getSearchFolder;

    BP_PENALTY      = 4;
    NEAR_BP_PENALTY = 5;
    STACK_PENALTY   = 6;
    FILENAME = 'MM_extraNTs.mat';
    LOGFILE  = 'MM_extraNTs.txt';
    
    BASEPAIRS  = 1:12;
    STACKS     = [21:23 121:123];
    NEAR_PAIRS = 101:112;
    
    N = length(MM(1,:));
    
    fid = fopen(LOGFILE, 'w');

    for i = 1:N        
        
        fprintf('%i out of %i\n',i,N);
                
        ind = find( MM(i,:) > 0 & MM(i,:) < BP_PENALTY );
        
        for j = ind
                        
            load(getSearchAddress(loop_ids{i}, loop_ids{j}), 'Search');
                        
            cand = find(Search.Discrepancy == min(Search.Discrepancy));
            pdb  = Search.Candidates(cand(1),end); %#ok<FNDSB>
            F1   = Search.File(pdb); % structure found in this search

            load(getPrecomputedDataAddress(loop_ids{j}), 'File');
            F2 = File; % the same structure taken independently            

            coreNts  = Search.Candidates(cand(1),1:end-1);            
            indices1 = {F1.NT(coreNts).Number};
            indices2 = {F2.NT.Number};

            if length(indices1) == length(indices2)
                continue;
            end
            
            chains1 = {F1.NT(coreNts).Chain};
            chains2 = {F2.NT.Chain};
            
            if isfield(F1.NT(1),'ModelNum')
                models1 = {F1.NT(coreNts).ModelNum};
                models2 = {F2.NT.ModelNum};                
            else
                models1 = {};
                models2 = {};
                models1(1:length(indices1)) = {''};
                models2(1:length(indices2)) = {''};                
            end
            
            indices1 = strcat(models1, indices1, chains1);
            indices2 = strcat(models2, indices2, chains2);            
            
             % extra nucleotides in the original file
            [extra,indExtra] = setdiff(indices2, indices1);

            F2.Edge = fix(abs(F2.Edge));
            interactions         = reshape(F2.Edge(indExtra,:),1,[]);
            interactionsWithCore = reshape(F2.Edge(indExtra,coreNts),1,[]);

            % extra nucleotides make basepairs with any nucleotide in the motif       
            if ~isempty(intersect(interactions,BASEPAIRS))
                
                MM(i,j) = BP_PENALTY;
                MM(j,i) = BP_PENALTY;                               
                annotate_interaction_conflict(BP_PENALTY, BASEPAIRS);
                
            % extra nucleotides make near bps with the core nucleotides
            elseif ~isempty(intersect(interactionsWithCore,NEAR_PAIRS))

                MM(i,j) = NEAR_BP_PENALTY;
                MM(j,i) = NEAR_BP_PENALTY;                                
                annotate_interaction_conflict(NEAR_BP_PENALTY, NEAR_PAIRS);                
                
            % extra nucleotides make more than 1 stacking interaction 
            % with the core nucleotides
            elseif length(find(ismember(interactionsWithCore,STACKS))) > 1                
                
                MM(i,j) = STACK_PENALTY;
                MM(j,i) = STACK_PENALTY;                
                annotate_interaction_conflict(STACK_PENALTY, STACKS);                                
                
            end
            
        end                
    end

    save(FILENAME, 'MM', 'loop_ids');
    fclose(fid);
    
    % nested functions
    
    % output format: NT1 interaction NT2, NT3 interaction NT4
    function [] = annotate_interaction_conflict(penalty, disallowed_interactions)
                
        comment = {};
        
        for nt1 = indExtra
            [a,b] = intersect(F2.Edge(nt1,:), disallowed_interactions);
            % extra nucleotides can make more than one basepair
            for nt2 = b
                nt1_name = sprintf('%s%s', F2.NT(nt1).Base, F2.NT(nt1).Number);
                nt2_name = sprintf('%s%s', F2.NT(nt2).Base, F2.NT(nt2).Number);        
                bp = strtrim(zEdgeText(F2.Edge(nt1, nt2)));
                comment{end+1} = sprintf('%s %s %s', nt1_name, bp, nt2_name);
            end
        end

        fprintf(fid, '"%s","%s","%i","%s"\n', loop_ids{i}, loop_ids{j}, penalty, aImplode(comment));        
        
    end
    
end
