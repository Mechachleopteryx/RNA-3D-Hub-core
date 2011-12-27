% pMakeModelFromSearchSaveFile(Search) creates an SCFG/MRF Node variable corresponding to the model in Search

% pMakeModelFromSearchSaveFile('LIB00002 IL 2008-03-20_23_29_25-Sarcin_13_flanked_by_cWW_in_1s72')
% Search = 'LIB00002 IL 2008-03-20_23_29_25-Sarcin_13_flanked_by_cWW_in_1s72';

% load LIB00014_IL_tSH-tSH-tHS-tHS.mat
% pMakeModelFromSearchSaveFile(Search,'IL',1);

function [Node,Truncate,Signature,RSignature] = pMakeMotifModelFromSSF(Search,Param,Prior,loopType,UseIndex)

if nargin < 2,
    Param   = 0;
    Verbose = 0;
else
    Verbose = Param(1);
end
if nargin <3,
    Prior = [10000 10000 10000 10000 0];    % Extremely strong prior, makes for flat letter distribution
end
if nargin <4,
    loopType = 'IL';                          % Assume internal loops if type not specified
end

while length(Prior) < 5,
    Prior = [Prior 0];
end
% ----------------------------------- Load Search from filename, if applicable

if strcmp(class(Search),'char'),
    load(['MotifLibrary' filesep Search],'Search','-mat');
end

% ----------------------------------- Gather basic information about the search

[L,N] = size(Search.Candidates);        % L = num instances; N = num NT
N = N - 1;                              % number of nucleotides

f = Search.Candidates(:,N+1);           % file numbers of motifs

File = Search.File(f(1));                      % file of query motif
NTNumber = double(Search.Candidates(1,1));     % index of first NT
LastNTNumber = double(Search.Candidates(1,N)); % index of last NT

% ----- Display interactions in the first instance

i = Search.Candidates(1,1:N);                   % indices of query motif

if Verbose > 0,
    fprintf('Interactions in the first instance:\n');
    zShowInteractionTable(File,full(i));
end

% ----- Identify where the flanking pair is, to split up the two strands
% --------------------------------------- Find locations of truncations

[Edge,BPh,BR,Search] = pConsensusInteractions(Search); % consensus interactions

F.Edge = Edge;                          % consensus pairs and stacks
F.BPh  = BPh;                           % consensus BPh
F.BR   = BR;

if sum(sum(BPh .* (1-eye(size(BPh))))) > 0,
    fprintf('&&&&&&&&&&&&&& found conserved BPh\n');
    full(BPh)
end

if sum(sum(BR .* (1-eye(size(BR))))) > 0,
    fprintf('&&&&&&&&&&&&&& found conserved BR\n');
    full(BR)
end

if loopType == 'IL',
    index = find(diag(fix(abs(F.Edge)),1)==1);
    Truncate = index+1;
else
    index = [];
    Truncate = [];
end

fprintf('pMakeMotifModelFromSSF: Truncate = %4d\n', Truncate);

% ---------------------------------------- Extract a motif signature
if strcmp(loopType,'HL')
    strands = 1;
else
    strands = 2;
end
try
    Signature = zMotifSignature(F.Edge,strands,1,1);
    fprintf('Signature: %s\n', Signature);

    if strcmp(loopType,'IL'),
        per = [Truncate:N 1:(Truncate-1)];
        RSignature = zMotifSignature(F.Edge(per,per),strands,1,1);
        fprintf('RSignature: %s\n', RSignature);
    else
        RSignature = Signature;
    end

catch
    Signature = 'trouble';
    RSignature = 'trouble';
    fprintf('pMakeMotifModelFromSSF: problem making the signature\n');
    full(min(30,abs(F.Edge)))
end

% -------------------------------- Make the model for the consensus structure

F.NT = File.NT(Search.Candidates(1,1:N));   % use the first candidate as model
F.Crossing = zeros(N,N);                    % small enough, pretend none
F.Range    = zeros(N,N);
F.NumNT = length(F.NT);

if length(Truncate) > 0,                    % at least two strands
    b = 1:N;
    for t = 1:N,
        b(t) = b(t) + 100*sum(t >= Truncate);
    end
    binv = 1:max(b);                                  % invert the spreading

    %size(binv)
    %size(b)
    %N

    binv(b) = 1:N;
else
    b = 1:N;
    binv = 1:N;
end

FF.Filename      = File.Filename;
FF.Edge(b,b)     = F.Edge;                        % spread the strands out
FF.NT(b)         = F.NT;
FF.Crossing(b,b) = F.Crossing;
FF.Range(b,b)    = F.Range;

disp('pMakeMotifModelFromSSF:  Consensus interaction table with nucleotides from the first candidate:');
zShowInteractionTable(FF,b);

Node = pMakeNodes(FF,Param,1,b(N),Truncate);          % make the SCFG/MRF model

for n = 1:length(Node),
    Node(n).LeftIndex    = binv(Node(n).LeftIndex);
    Node(n).RightIndex   = binv(Node(n).RightIndex);
    Node(n).MiddleIndex  = binv(Node(n).MiddleIndex);
    Node(n).InterIndices = binv(Node(n).InterIndices);
end

% -------------------------------------- Insert initial node after cluster

m = 1;
for n = 1:length(Node),
    NNode(m) = Node(n);
    NNode(m).nextnode = m+1;
    if strcmp(Node(n).type,'Cluster'),
        if ~strcmp(Node(n+1).type,'Initial'),
            fprintf('pMakeMotifModelFromSSF:  Adding an Initial node after Cluster\n');
            m = m + 1;
            NNode(m).type       = 'Initial';
            NNode(m).nextnode   = m+1;
            NNode(m).LeftIndex  = NNode(m-1).LeftIndex;
            NNode(m).RightIndex = NNode(m-1).RightIndex;
            NNode(m).leftLengthDist = [0.9999 0.0001];
            NNode(m).leftLetterDist = [1 1 1 1]/4;
            NNode(m).rightLengthDist = [0.9999 0.0001];
            NNode(m).rightLetterDist = [1 1 1 1]/4;
        end
    end
    m = m + 1;
end

Node = NNode;

% ---------------------------- Show alignment of instances

Text = xAlignCandidates(Search.File,Search);

for t = 1:length(Text),
    fprintf('%s\n', Text{t});
end

Node = pUpdateModelWithSSF(Node,Search,f,F,Verbose,Prior,loopType,File,UseIndex);      %Adjust pair and substitution probabilities

% % ---------------------------- Set parameters for the nodes from instances
% 
% for n = 1:length(Node),
%     switch Node(n).type
%         case 'Initial' % ==========================================================
%             if n == 1,
%                 % much harsher penalties for initial node insertions
%                 Node(n).leftLengthDist = [.9999,.0001];
%                 Node(n).rightLengthDist = [.9999,.0001];
%             else
%                 a = max(Node(n-1).LeftIndex);       % left NT of the query motif
%                 aa = min(Node(n+1).LeftIndex);      % next interacting base in the model
%                 b = min(Node(n-1).RightIndex);      % right NT of the query motif
%                 bb = max(Node(n+1).RightIndex);     % next interacting base in the model
%                 % adjust insertion probs for initial nodes after clusters
%                 % ----------------------------- tally insertions on the left
%                 letter = Prior;                     % record which bases occur
%                 if n < length(Node)-1,              % no insertions after last pair
% 
%                     inscount = zeros(1,L);
%                     for c = 1:L,
%                         inscount(c) = abs(Search.Candidates(c,aa) - Search.Candidates(c,a)) - 1;
%                     end
% 
%                     %disp('pMakeMotifModelFromSSF: Left insertion counts:')
%                     %inscount
% 
%                     lld = zeros(1,max(inscount)+2);           % Dirichlet distribution
%                     for c = 1:L,
% 
%                         if inscount(c) > 0,
%                             lld(inscount(c)+0) = lld(inscount(c)+0) + 0.01;% spread a little
%                         end
%                         lld(inscount(c)+1) = lld(inscount(c)+1) + 1.00;
%                         lld(inscount(c)+2) = lld(inscount(c)+2) + 0.01;% spread a little
% 
%                         ff = Search.Candidates(c,N+1);          % file number
%                         d = Search.Candidates(c,a);             % index of interacting base
%                         if inscount(c) > 0,
%                             for i = 1:inscount(c),
%                                 insb = Search.File(ff).NT(d+i).Code;  % A=1, C=2, G=3, U=4
%                                 if ~isempty(insb)
%                                     letter(insb) = letter(insb) + 1;
%                                 end
%                             end
%                         end
%                     end
% 
%                     %disp('pMakeMotifModelFromSSF: Left insertion tallies:')
%                     %lld
%                     Node(n).leftLengthDist = lld / sum(lld);        % normalize
%                     Node(n).leftLetterDist = letter / sum(letter);  % normalize
% 
%                     %     bb = max(Node(n+1).RightIndex);
%                     %     [rld,letter] = pInsertionConcenses(Search,Node,n,bb,b,Prior);
%                     %     Node(n).rightLengthDist = lld;
%                     %     Node(n).rightLetterDist = letter;
% 
%                     % ----------------------------- tally insertions on the right
%                     inscount = zeros(1,L);
%                     letter = Prior;
%                     if bb==b
%                         inscount(1:L) = 0;
%                     else
%                         for c = 1:L,
%                             inscount(c) = abs(Search.Candidates(c,b) - Search.Candidates(c,bb)) - 1;
%                         end
%                     end
% 
%                     %disp('pMakeMotifModelFromSSF: Right insertion counts:')
%                     %inscount
%                     rld = zeros(1,max(inscount)+2);  % Dirichlet distribution
%                     for c = 1:L,
% 
%                         if inscount(c) > 0,
%                             rld(inscount(c)+0) = rld(inscount(c)+0) + 0.01;% spread a little
%                         end
%                         rld(inscount(c)+1) = rld(inscount(c)+1) + 1.00;
%                         rld(inscount(c)+2) = rld(inscount(c)+2) + 0.01;% spread a little
% 
%                         ff = Search.Candidates(c,N+1);          % file number
%                         d = Search.Candidates(c,b);            % index of interacting base
%                         if inscount(c) > 0,
%                             for i = 1:inscount(c),
%                                 insb = Search.File(ff).NT(d-i).Code; % A=1, C=2, G=3, U=4
%                                 if ~isempty(insb)
%                                     letter(insb) = letter(insb) + 1;
%                                 end
%                             end
%                         end
%                     end
%                     %disp('pMakeMotifModelFromSSF: Right insertion tallies:')
%                     %rld
% 
%                     Node(n).rightLengthDist = rld / sum(rld);        % normalize
%                     Node(n).rightLetterDist = letter / sum(letter);  % normalize
%                 end
%             end
% 
%         case 'Basepair' % =======================================================
%             Node(n).Delete = 0.0001;
% 
%             if n == length(Node)-1 && strcmp(loopType,'IL'), % last basepair in IL
%                 Node(n).leftLengthDist  = [0.9999 0.0001];   % should be no insertions
%                 Node(n).rightLengthDist = [0.9999 0.0001];
%             end
% 
%             a = Node(n).LeftIndex;                   % left NT of the query motif
%             b = Node(n).RightIndex;                  % right NT of the query motif
% 
%             disp('pMakeMotifModelFromSSF: Getting consensus for a basepair');
% 
%             Score = pConsensusPairSubstitution(a,b,f,Search.File,F,L,Search,Verbose);
% 
%             if Verbose > 0,
%                 fprintf('Original substitution probabilities\n');
%                 Node(n).SubsProb
% 
%                 fprintf('Consensus substitution probabilities\n');
%                 Score
%             end
% 
%             Node(n).SubsProb = Score;
% 
%             % ----------------------------- tally insertions on the left
%             inscount = zeros(1,L);
%             letter = Prior;                           % record which bases occur
%             aa = min(Node(n+1).LeftIndex);          % next interacting base in the model
%             bb = max(Node(n+1).RightIndex);      % next interacting base in the model
%             if (n < length(Node)-1 || strcmp(loopType,'HL')) && aa <= bb,                    % no insertions after last pair
%                 for c = 1:L,
%                     inscount(c) = abs(Search.Candidates(c,aa) - Search.Candidates(c,a)) - 1;
%                 end
% 
%                 %disp('pMakeMotifModelFromSSF: Left insertion counts:')
%                 %inscount
% 
%                 lld = zeros(1,max(inscount)+2);           % Dirichlet distribution
%                 for c = 1:L,
%                     if inscount(c) > 0,
%                         lld(inscount(c)+0) = lld(inscount(c)+0) + 0.01;  % spread a little
%                     end
%                     lld(inscount(c)+1) = lld(inscount(c)+1) + 1.00;
%                     lld(inscount(c)+2) = lld(inscount(c)+2) + 0.01;  % spread a little
% 
%                     ff = Search.Candidates(c,N+1);          % file number
%                     d = Search.Candidates(c,a);             % index of interacting base
%                     if inscount(c) > 0,
%                         for i = 1:inscount(c),
%                             insb = Search.File(ff).NT(d+i).Code;  % A=1, C=2, G=3, U=4
%                             if ~isempty(insb)
%                                 letter(insb) = letter(insb) + 1;
%                             end
%                         end
%                     end
%                 end
% 
%                 %disp('pMakeMotifModelFromSSF: Left insertion tallies:')
%                 %lld
% 
%                 Node(n).leftLengthDist = lld / sum(lld);    % normalize
%                 Node(n).leftLetterDist = letter / sum(letter);  % normalize
% 
%                 %     bb = max(Node(n+1).RightIndex);
%                 %     [rld,letter] = pInsertionConcenses(Search,Node,n,bb,b,Prior);
%                 %     Node(n).rightLengthDist = lld;
%                 %     Node(n).rightLetterDist = letter;
% 
%                 % ----------------------------- tally insertions on the right
%                 inscount = zeros(1,L);
%                 letter = Prior;
% 
%                 if bb==b
%                     inscount(1:L) = 0;
%                 else
%                     for c = 1:L,
%                         inscount(c) = abs(Search.Candidates(c,b) - Search.Candidates(c,bb)) - 1;
%                     end
%                 end
% 
%                 %disp('pMakeMotifModelFromSSF: Right insertion counts:')
%                 %inscount
% 
%                 rld = zeros(1,max(inscount)+2);  % Dirichlet distribution
%                 for c = 1:L,
% 
%                     if inscount(c) > 0,
%                         rld(inscount(c)+0) = rld(inscount(c)+0) + 0.01;  % spread a little
%                     end
%                     rld(inscount(c)+1) = rld(inscount(c)+1) + 1.00;
%                     rld(inscount(c)+2) = rld(inscount(c)+2) + 0.01;  % spread a little
% 
%                     ff = Search.Candidates(c,N+1);          % file number
%                     d = Search.Candidates(c,b);            % index of interacting base
%                     if inscount(c) > 0,
%                         for i = 1:inscount(c),
%                             insb = Search.File(ff).NT(d-i).Code; % A=1, C=2, G=3, U=4
%                             if ~isempty(insb)
%                                 letter(insb) = letter(insb) + 1;
%                             end
%                         end
%                     end
%                 end
%                 %disp('pMakeMotifModelFromSSF: Right insertion tallies:')
%                 %rld
% 
%                 Node(n).rightLengthDist = rld / sum(rld);    % normalize
%                 Node(n).rightLetterDist = letter / sum(letter);  % normalize
%             end
% 
%         case 'Cluster' % ===========================================================
%             Node(n).Delete = 0.00000001;              % very small deletion probability
%             Indices = [Node(n).LeftIndex(Node(n).Left) ...
%                 Node(n).RightIndex(Node(n).Right)];
%             for ii = 1:length(Node(n).IBases(:,1)),
%                 a = Indices(Node(n).IBases(ii,1));
%                 b = Indices(Node(n).IBases(ii,2));
% 
%                 disp('pMakeMotifModelFromSSF: Getting consensus for pairs in a cluster');
% 
%                 Score = pConsensusPairSubstitution(a,b,f,Search.File,F,L,Search,Verbose);
% 
%                 if Verbose > 0,
%                     fprintf('Original substitution probabilities\n');
%                     Node(n).SubsProb(:,:,ii)
% 
%                     fprintf('Consensus substitution probabilities\n');
%                     Score
%                 end
% 
%                 Node(n).SubsProb(:,:,ii) = Score;
%                 if Verbose > 0,
%                     fprintf('\n');
%                 end
% 
%                 %Adjust insertion probabilities
%                 if L<100,
%                     Node(n).Insertion = [];
%                     LeftInteracting = intersect(Node(n).LeftIndex, Node(n).InterIndices(:));
%                     RightInteracting = intersect(Node(n).RightIndex, Node(n).InterIndices(:));
%                     Interacting = union(LeftInteracting,RightInteracting);
%                     PosIns = setdiff(Interacting,union(max(LeftInteracting),max(RightInteracting)));
%                     for k = 1:length(PosIns),
%                         minIns = 0;
%                         if ismember(PosIns(k),LeftInteracting),      %Left side
%                             a = PosIns(k);
%                             aloc = find(LeftInteracting == a);
%                             aa = LeftInteracting(aloc+1);
%                             fi = find(Node(n).LeftIndex == a);
%                             li = find(Node(n).LeftIndex == aa);
%                             Right=0;
%                             %          minIns = li-fi-1;
%                         else                                         %Right side
%                             a = PosIns(k);
%                             aloc = find(RightInteracting == a);
%                             aa = RightInteracting(aloc+1);
%                             fi = find(Node(n).RightIndex == a);
%                             li = find(Node(n).RightIndex == aa);
%                             Right=1;
%                             %          minIns = li-fi-1;
%                         end
%                         inscount = [];
%                         letter = Prior;
%                         for c = 1:L,
%                             inscount(c) = abs(Search.Candidates(c,aa) - Search.Candidates(c,a)) - 1;
%                         end
%                         if max(inscount) ~= 0,                    % if insertion seen, add to node
%                             lld = zeros(1,max(inscount)+2);         % Dirichlet distribution
%                             for c = 1:L,
% 
%                                 if inscount(c) > 0,
%                                     lld(inscount(c)+0) = lld(inscount(c)+0) + 0.01;  % spread a little
%                                 end
%                                 lld(inscount(c)+1) = lld(inscount(c)+1) + 1.00;
%                                 lld(inscount(c)+2) = lld(inscount(c)+2) + 0.01;  % spread a little
% 
%                                 ff = Search.Candidates(c,N+1);         % file number
%                                 d = Search.Candidates(c,a);            % index of interacting base
%                                 if inscount(c) > 0,
%                                     for i = 1:inscount(c),
%                                         insb = Search.File(ff).NT(d+i).Code;  % A=1, C=2, G=3, U=4
%                                         if ~isempty(insb)
%                                             letter(insb) = letter(insb) + 1;
%                                         end
%                                     end
%                                 end
%                             end
%                             InsNum = length(Node(n).Insertion)+1;
% 
%                             if minIns > 0,
%                                 lld(1:minIns) = 0;
%                             end
% 
%                             Node(n).Insertion(InsNum).Position = find(Interacting == a);
%                             Node(n).Insertion(InsNum).LengthDist = lld / sum(lld);   % normalize
%                             Node(n).Insertion(InsNum).LetterDist = letter / sum(letter);% norm
% 
%                             l1=Search.Candidates(1,a);
%                             l2=Search.Candidates(1,aa);
%                             Node(n).InsertionComment{InsNum} = [' // Insertion between ' File.NT(l1).Base File.NT(l1).Number ' and ' File.NT(l2).Base File.NT(l2).Number];
%                         end
%                     end
%                 end
%             end
%         case 'Junction' % =========================================================
% 
%         case 'Hairpin'  % =========================================================
%             if ~strcmp(loopType,'IL')         % don't do this for * hairpins in ILs
%                 interactions = 0;
%                 [index,dum] = size(Node(n).IBases);
%                 insertions = 0;
%                 a = Node(n).LeftIndex;
%                 b = Node(n).RightIndex;
%                 interbases = Node(n).MiddleIndex(unique(Node(n).IBases));
%                 [files,nucleo] = size(Search.Candidates);
%                 if a<b,
%                     for i = a:b,
%                         interactions = interactions+1;
%                         if isempty(find(interbases==i)),
%                             index = index + 1;
%                             Node(n).IBases(index,1) = interactions;
%                             Node(n).IBases(index,2) = interactions;
%                             Node(n).SubsProb(:,:,index) = zeros(4);
%                             dist = Prior;
%                             clear basesInds
%                             nucleo = nucleo-1;
%                             for j = 1:files
%                                 f = Search.Candidates(j,end);
%                                 if nucleo == length(Search.File(j).NT),  % if insertions seem to be missing or there are none
%                                     baseCode = Search.File(f).NT(i).Code;
%                                 else
%                                     position = Search.Candidates(j,i);
%                                     baseCode = Search.File(f).NT(position).Code;
%                                 end
%                                 dist(baseCode) = dist(baseCode) + 1;
%                             end
%                             dist = dist / sum(dist); %normalize
%                             for k = 1:4
%                                 Node(n).SubsProb(k,k,index) = dist(k);
%                             end
%                             Node(n).InteractionComment{index} = ' // Hairpin Base';
%                             % ------------------ check for insertions
%                         end
%                         if i ~= Node(n).RightIndex,
%                             insCounts = 0;
%                             dist = Prior;
%                             for j = 1:files
%                                 f = Search.Candidates(j,end);
%                                 inserts = Search.Candidates(f,i+1)-Search.Candidates(f,i)-1;
%                                 if length(insCounts) >= inserts+1,
%                                     insCounts(inserts+1) = insCounts(inserts+1)+1;
%                                 else
%                                     insCounts(inserts+1) = 1;
%                                 end
%                                 if inserts ~= 0,
%                                     if nucleo ~= length(Search.File(f).NT),
%                                         start = Search.Candidates(j,i);
%                                         for k = 1:inserts,
%                                             baseCode = Search.File(f).NT(start+k).Code;
%                                             dist(baseCode) = dist(baseCode) + 1;
%                                         end
%                                     end
%                                 end
%                             end
%                             if length(insCounts) > 1;
%                                 insertions = insertions + 1;
%                                 Node(n).Insertion(insertions).Position = interactions;
%                                 Node(n).Insertion(insertions).LengthDist = insCounts / sum(insCounts);   % normalize
%                                 Node(n).Insertion(insertions).LetterDist = dist / sum(dist);% normalize
%                                 Node(n).InsertionComment{insertions} = '// Insertion in Hairpin';
%                             end
%                         end
% 
%                     end
%                 else
%                     temp = a;
%                     a = b;
%                     b = temp;
%                     ins = Search.Candidates(:,b) - Search.Candidates(:,a) - 1;
%                     first = Prior;
%                     extra = Prior;
%                     extracount = 0;
%                     for j = 1:length(ins),
%                         f = Search.Candidates(j,end);
%                         if ins(j) >= 1,
%                             position = Search.Candidates(j,a)+1;
%                             baseCode = Search.File(f).NT(position).Code;
%                             first(baseCode) = first(baseCode) + 1;
%                             if length(extracount) >= ins(j),
%                                 extracount(ins(j)) = extracount(ins(j)) + 1;
%                             else
%                                 extracount(ins(j)) = 1;
%                             end
%                             if ins(j) >= 2,
%                                 for i = 1:ins(j)-1
%                                     position = Search.Candidates(j,a)+i+1;
%                                     baseCode = Search.File(f).NT(position).Code;
%                                     extra(baseCode) = extra(baseCode) + 1;
%                                 end
%                             end
%                         end
%                     end
%                     first = first / sum(first); %normalize
%                     for k = 1:4
%                         Node(n).SubsProb(k,k) = first(k);
%                     end
%                     Node(n).SubsProb(5,5) = 0;
%                     Node(n).MiddleIndex = -1;
%                     Node(n).LeftIndex = a;
%                     Node(n).RightIndex = b;
%                     Node(n).Comment = ' // Hairpin node for bases outside motif core';
%                     Node(n).IBases(1,:) = [1,1];
%                     Node(n).InteractionComment{1} = ' // Hairpin Base';
%                     if length(extracount) > 1,
%                         Node(n).Insertion.Position = 1;
%                         Node(n).Insertion.LengthDist = extracount / sum(extracount);   % normalize
%                         Node(n).Insertion.LetterDist = extra / sum(extra);% normalize
%                         Node(n).InsertionComment{1} = '// Insertion in Hairpin';
%                     end
%                 end
%             end
%     end

    if Verbose > 0,
        fprintf('\n')
    end
end
