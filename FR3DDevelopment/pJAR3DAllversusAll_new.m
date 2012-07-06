% pJAR3DAllversusAll runs JAR3D on all motif sequences against all motif
% models.  One should specify the loopType and the SequenceSource

disp('Make sure the Matlab current folder has a MotifLibrary in it');

if ~exist('Rfam'),
  disp('Please set the variable Rfam, 1 to use Rfam sequences, 0 for not');
  break
end

fs = 16;                          % font size for figures

% --------------------------------- Determine loop type

if ~exist('loopType'),
  disp('Please specify a loop type, for example loopType = ''IL'';')
  break
end

switch loopType,
case 'JL'
  R = 3;                      % three rotations, for 3-way junctions
case 'IL'
  R = 2;                      % two rotations are computed
case 'HL'
  R = 1;                      % only one "rotation"
end

% --------------------------------- Read model file names

modelNameFile = [loopType '_Models.txt'];

ModNames = textread(['Models' filesep modelNameFile],'%s');

NumModels = length(ModNames);

for m = 1:NumModels,
  if isempty(strfind(ModNames{m},'Helix')),
    Helical(m) = 0;
  else
    Helical(m) = 1;
  end

  ModNums{m} = ModNames{m}(1:6);

end

Structured(NumModels) = 0;
Keep = pMoreThanFlankingPairs(ModNames,loopType);
Structured(find(Keep)) = 1;

% --------------------------------- Read sequences
% ------------------------------------------------------------------------

clear FASTA
clear OwnGroup
clear OwnPercentile
clear SeqLength
clear LeaveOneOut
clear NumBetterScore
clear OwnScore

% --------------------------------- Read sequence file names

sequenceNameFile = [loopType '_Sequences.txt'];
SeqNames = textread(['Sequences' filesep sequenceNameFile],'%s');

% ------------------------------- Concatenate sequence files

%           Note: OwnGroup is defined below for the case in which
%           the groups of sequences correspond exactly to the group of
%           models.  It won't work for Rfam sequences from unknown groups.

for n = 1:NumModels,
  newFASTA = zReadFASTA(['Sequences' filesep SeqNames{n}]);
  m = length(newFASTA);
  g = n*ones(m,1);                % group that these sequences belong to
  if n == 1,
    FASTA = newFASTA;
    OwnGroup = g;
  else
    FASTA = [FASTA newFASTA];
    OwnGroup = [OwnGroup; g];
  end
end

% -------------------------------- Read sequences aligned to motifs in Rfam

AligText = '';

if Rfam == 1,
  AligText = '_Rfam';

  StructureFASTA = FASTA;
  StructureOwnGroup = OwnGroup;
  for i = 1:length(FASTA),
    StructureCore{i} = pCoreSequence(FASTA(i).Sequence);
  end

  [loop_id,rfam_sequence_variant,freq,original_seq,group_id,rfam_desc,release_id,wc1,wc2,nwc,source,filename,motif_id] = textread('RFAM-PDB-Unobserved-seq.tsv','%s%s%s%s%s%s%s%s%s%s%s%s%s', 'whitespace', '\t','headerlines',1);

  clear FASTA
  clear OwnGroup
  clear Core

  for i = 1:length(rfam_sequence_variant),
    FASTA(i).Sequence = strrep(rfam_sequence_variant{i},'-','');
    FASTA(i).Aligned  = rfam_sequence_variant{i};
    FASTA(i).Header   = group_id{i};
    OwnGroup(i) = find(ismember(ModNums,group_id{i}(1:6)));
    Core{i} = pCoreSequence(FASTA(i).Sequence);    

    % [ModNums{OwnGroup(i)} ' ' group_id{i} ' ' FASTA(i).Sequence ' ' Core{i}]
  end

  Keep = ones(1,length(FASTA));
  for i = 1:length(FASTA),
    g = OwnGroup(i);                   % group of current sequence
    j = find(StructureOwnGroup == g);  % structure sequences from this group
    k = ismember(StructureCore(j),Core{i});

    if any(k),
      Keep(i) = 0;
      w = find(k);
      fprintf('Removed sequence %20s because it matches %20s\n', FASTA(i).Sequence, StructureFASTA(j(w(1))).Sequence);
    else
      fprintf('Kept sequence %20s with core %20s from %20s because it has a new core\n', FASTA(i).Sequence, Core{i}, ModNames{g});

unique(StructureCore(j))

    end
  end

if 10 > 1,
  fprintf('Kept %d out of %d sequences because they have new core sequences\n', length(find(Keep)), length(Keep));
  fprintf('There were %d groups represented, ', length(unique(OwnGroup)));

  FASTA = FASTA(find(Keep));
  OwnGroup = OwnGroup(find(Keep));
  Core = Core(find(Keep));
end

  fprintf('now there are %d groups.\n', length(unique(OwnGroup)));

end

NumSequences = length(FASTA);

% --------------------- Histogram number of instances in each group

clear GroupSize

for g = 1:NumModels,
  GroupSize(g) = length(find(OwnGroup == g));
end

figure(10)
clf
hist(GroupSize,30);
title('Number of instances in each group','fontsize',fs);
set(gca,'fontsize',fs)
print(gcf,'-dpng',[loopType AligText '_Num_Instances.png']);

figure(11)
clf
semilogy(1:NumModels,GroupSize,'.');
title('Number of instances versus group number','fontsize',fs);
set(gca,'fontsize',fs)
print(gcf,'-dpng',[loopType AligText '_Num_Instances_By_Group.png']);

% --------------------- Write sequences to one file for each rotation

r = 1;                          % first rotation
AllSequencesFile{1} = [loopType '_All_Sequences_' num2str(r) '.fasta'];
fid = fopen(['Sequences' filesep AllSequencesFile{1}],'w');
for n = 1:length(FASTA),
  fprintf(fid,'>%s\n',FASTA(n).Header);
  fprintf(fid,'%s\n',FASTA(n).Sequence);
end  
fclose(fid);

if R > 1,                       % more than one rotation, for IL, JL
  FASTA_R = FASTA;
end

for r = 2:R,
  for n = 1:length(FASTA_R),
    a = FASTA_R(n).Sequence;
    b = FASTA_R(n).Aligned;

    % fprintf('%s and %s become ', a, b);

    i = strfind(a,'*');
    a = [a((i(1)+1):end) '*' a(1:(i(1)-1))];
    i = strfind(b,'*');
    b = [b((i(1)+1):end) '*' b(1:(i(1)-1))];

    % fprintf('%s and %s.\n', a, b);

    FASTA_R(n).Sequence = a;
    FASTA_R(n).Aligned = b;

  end

  AllSequencesFile{r} = [loopType '_All_Sequences_' num2str(r) '.fasta'];
  fid = fopen(['Sequences' filesep AllSequencesFile{r}],'w');
  for n = 1:length(FASTA_R),
    fprintf(fid,'>%s\n',FASTA_R(n).Header);
    fprintf(fid,'%s\n',FASTA_R(n).Sequence);
  end  
  fclose(fid);
end

% ----------------------- Parse all sequences against all models, all rotations

JAR3D_path;  

clear MLPS
clear Percentile

fprintf('Parsing sequences against %4d models\n', NumModels);
for m = 1:length(ModNames),
  for r = 1:R,
    S = JAR3DMatlab.MotifParseSingle(pwd,AllSequencesFile{r},ModNames{m});
    Q = webJAR3D.getQuantilesB(S, ModNames{m}(4:6), loopType);  % was SeqNames

    MLPS(:,m,r) = S;               % max log probability score for each seq
    Percentile(:,m,r) = Q;           % percentile of this score
  end

  if mod(m,50) == 0,
    fprintf('Parsed against %4d models so far\n', m);
  end
end

% MLPS(a,m,r) is the score of sequence a against model m using rotation r
% Percentile(a,m,r) is the percentile of sequence a against model m using r


% ------------------------------- Histogram percentile against own model

for n = 1:NumSequences,
  g = OwnGroup(n);
  OwnPercentile(n) = Percentile(n,g,1);
end

figure(12)
clf
hist(OwnPercentile,30);
title('Percentile of each sequence against the model for its group','fontsize',fs);
ax = axis;
q = [0.999 0.99 0.98 0.97 0.96 0.95 0.9];
for m = 1:length(q),
  text(ax(1)+0.1*(ax(2)-ax(1)), (0.9-0.08*m)*ax(4), sprintf('%7.4f%% better than %7.3f', 100*sum(OwnPercentile > q(m))/NumSequences, q(m)));
end
set(gca,'fontsize',fs)
print(gcf,'-dpng',[loopType AligText '_Own_Percentile_Histogram.png']);

figure(13)
clf
plot(OwnGroup,OwnPercentile,'.');
title('Own percentiles by group','fontsize',fs);
xlabel('Group number','fontsize',fs);
ylabel('Percentiles of sequences against their own group','fontsize',fs);

gmed = zeros(1,NumModels);
gmax = zeros(1,NumModels);
gmin = zeros(1,NumModels);

for g = 1:NumModels,
  n = find(OwnGroup == g);        % sequences from group g
  if ~isempty(n),
    gmed(g) = median(OwnPercentile(n));
    gmin(g) = min(OwnPercentile(n));
    gmax(g) = max(OwnPercentile(n));
  end
end
set(gca,'fontsize',fs)
print(gcf,'-dpng',[loopType AligText '_Own_Percentile_By_Group.png']);

figure(14)
clf
plot(1:NumModels, gmin, 'r.');
hold on
plot(1:NumModels, gmed, 'b.');
plot(1:NumModels, gmax, 'g.');
title('Min, median, max of percentiles of sequences against their own group','fontsize',fs);
xlabel('Group number','fontsize',fs)
ylabel('Min (red) median (blue) max (green)','fontsize',fs);
set(gca,'fontsize',fs)
print(gcf,'-dpng',[loopType AligText '_Own_Percentile_Min_Max_Med_By_Group.png']);

% ------------------------------- Group-group diagnostic
% ------------------------------- Count models with better MLPS and Percentiles

NumBetterScore = zeros(1,NumModels);

str = find((Structured == 1));  % structured internal loops
                                % this limits what *models* are compared to

for n = 1:NumModels,                          % loop through groups
  j = find(OwnGroup == n);                    % all sequences in group n
  if ~isempty(j),
    mlps = zeros(size(MLPS(1,:,:)));
    for m = 1:length(j),
      mlps = mlps + MLPS(j(m),:,:);           % sum scores of all sequences
    end
    m = max(mlps,[],3);                       % look for biggest sum
    NumBetterScore(n) = length(find(m(str) > mlps(1,n,1)));
  else
    NumBetterScore(n) = -1;                   % group is not represented
  end
end

NBS = NumBetterScore;
%NumBetterScore = NumBetterScore(2:end);

j = find(Helical == 0);                     % true internal loops
NBS = NumBetterScore(j);

j = find((Helical == 0) .* (Structured == 1));  % structured internal loops
                                                % limits what sequence groups
NBS = NumBetterScore(j);

figure(4)
clf
maxrank = 10;
n = hist(min(NBS(NBS >= 0),maxrank),0:maxrank);
if length(n) < 10,
  n(10) = 0;
end
bar(0:maxrank,n/sum(n));
axis([-0.5 maxrank+0.5 0 max(n/sum(n))*1.1]);
set(gca,'XTick',0:10)
set(gca,'XTickLabel',{'0','1','2','3','4','5','6','7','8','9','>=10'})
title(['Group-group diagnostic, ' num2str(sum(NBS >= 0)) ' sequence groups against ' num2str(length(str)) ' models'],'fontsize',fs);
xlabel(['Number of models that score higher than correct model'],'fontsize',fs);
ylabel('Frequency','fontsize',fs);
print(gcf,'-dpng',[loopType AligText '_Group_Group_Structured.png']);

% ------------------------------- Count models with better MLPS and Percentiles
% ------------------------------- Individual-group diagnostic

clear NumBetterScore
for n = 1:NumSequences,                     % loop through sequences
  g = OwnGroup(n);
  mlps = MLPS(n,:,:);                       % extract scores for this sequence
  m = max(mlps,[],3);
  NumBetterScore(n) = length(find(m > MLPS(n,g,1)));
end

NBS = NumBetterScore;
j = find(OwnGroup > 1);
% NBS = NumBetterScore(j);       % doesn't help that much

j = find(Helical(OwnGroup) == 0);     % true internal loops only
NBS = NumBetterScore(j);

figure(5)
maxrank = 10;
n = hist(min(NBS,maxrank),0:maxrank);
if length(n) < 10,
  n(10) = 0;
end
bar(0:maxrank,n/sum(n));
axis([-0.5 maxrank+0.5 0 max(n/sum(n))*1.1]);
set(gca,'XTick',0:10)
set(gca,'XTickLabel',{'0','1','2','3','4','5','6','7','8','9','>=10'})
title(['Individual-group diagnostic, ' num2str(length(find(Helical==0))) ' groups, ' num2str(length(NBS)) ' sequences']);
xlabel(['Number of models that score higher than correct model']);
ylabel('Frequency');

% -------------------------------- Individual-group, structured only

str = find((Structured == 1));  % structured internal loops
                                % this limits what *models* are compared to

clear NumBetterScore
for n = 1:NumSequences,                     % loop through sequences
  g = OwnGroup(n);
  mlps = MLPS(n,:,:);                       % extract scores for this sequence
  m = max(mlps,[],3);
  NumBetterScore(n) = length(find(m(str) > MLPS(n,g,1)));
end

NBS = NumBetterScore;

j = find(OwnGroup > 1);
% NBS = NumBetterScore(j);       % doesn't help that much

j = find(Helical(OwnGroup) == 0);     % true internal loops only
NBS = NumBetterScore(j);

j = find((Helical(OwnGroup) == 0) .* (Structured(OwnGroup) == 1));  % structured internal loops
                                       % restricts the sequence groups
NBS = NumBetterScore(j);

figure(6)
clf
fs = 12;
maxrank = 10;
n = hist(min(NBS(NBS >= 0),maxrank),0:maxrank);
if length(n) < 10,
  n(10) = 0;
end
bar(0:maxrank,n/sum(n));
axis([-0.5 maxrank+0.5 0 max(n/sum(n))*1.1]);
set(gca,'XTick',0:10)
set(gca,'XTickLabel',{'0','1','2','3','4','5','6','7','8','9','>=10'})
title(['Individual-group diagnostic, ' num2str(length(NBS)) ' sequences against ' num2str(length(str)) ' structured models'],'fontsize',fs);
xlabel(['Number of models that score higher than correct model'],'fontsize',fs);
ylabel('Frequency','fontsize',fs);
print(gcf,'-dpng',[loopType AligText '_Individual_Group_Structured.png']);


% ------------------------------- Retrieve leave-one-out scores

if Rfam == 0,

load IL_L1O_diagnostic_06-Dec-2011.mat

c = 0;
d = 1;
clear LeaveOneOut
for i = 1:length(FASTA),
  G = ModNames{OwnGroup(i)};                 % was SeqNames
  G = G(1:6);
  a = pCoreSequence(FASTA(i).Sequence);
  OwnScore(i) = MLPS(i,OwnGroup(i),1);
  LeaveOneOut(i) = -Inf;                     % default, generally overridden
  for n = 1:length(group),
    b = pCoreSequence(sequence{n}{1});
    if strcmp(a, b) && strcmp(G, group{n}),
if scores(n) > OwnScore(i),
%      fprintf('%6s %20s %20s Core: %20s Scores: %10.6f  %10.6f\n', G, FASTA(i).Sequence, sequence{n}{1}, a, OwnScore(i), scores(n));
      c = c + 1;
end

if scores(n) < -900,
      fprintf('%6s %20s %20s Core: %20s Scores: %10.6f  %10.6f\n', G, FASTA(i).Sequence, sequence{n}{1}, a, OwnScore(i), scores(n));

end

      LeaveOneOut(i) = scores(n);
    end
  end

if length(LeaveOneOut) < i && OwnGroup(i) < 160,
%  fprintf('%6s %20s Core: %20s\n', G, FASTA(i).Sequence, a);

  OneVariant{d} = G(4:6);
  d = d + 1;
end

end

% unique(OneVariant)


figure(3)
clf
plot(OwnScore(1:length(LeaveOneOut)),max(-30,LeaveOneOut),'.')
hold on
plot([-100 0],[-100 0],'r');
axis([-30 0 -30 0]);
xlabel('Score from own model');
ylabel('Score from leave-one-out model (min is -30)');

% ------ additional diagnostics concerning leave-one-out models

if 0 > 1,

for a = 1:length(FASTA),
  FASTASEQ{a} = FASTA(a).Sequence;
end
  
i = find(OwnGroup == 2);
unique(FASTASEQ(i))

c = 0;
clear JIMSEQ
for a = 1:length(group),
  if strcmp(group{a},'IL_002'),
    c = c + 1;   
    JIMSEQ{c} = sequence{a}{1};
  end
end
unique(JIMSEQ)

for a = 1:length(group),
  fprintf('%10s %20s Core: %20s\n', group{a}, sequence{a}{1}, pCoreSequence(sequence{a}{1}));
end


end

end

% ------------------------------- Leave-one-out diagnostic
% ------------------------------- Count models with better MLPS and Percentiles

str = find((Structured == 1));  % structured internal loops
                                % this limits what *models* are compared to

for i = 1:NumSequences,
  SeqLength(i) = length(FASTA(i).Sequence)-1;
end

for g = 1:NumModels,
  j = find(OwnGroup == g);
  if ~isempty(j),
    MinSeqLength(g) = min(SeqLength(j));
  end
end

clear NumBetterScore
for n = 1:NumSequences,                     % loop through sequences
  g = OwnGroup(n);
  mlps = MLPS(n,:,:);                       % extract scores for this sequence
  m = max(mlps,[],3);                       % maximum over rotations
  m(g) = -Inf;                              % ignore own model's score
  NumBetterScore(n) = length(find(m(str) > LeaveOneOut(n)));

  if NumBetterScore(n) >= 10 && LeaveOneOut(n) > -Inf && Helical(g) == 0 && Structured(g) == 1,
    fprintf('%6s %20s Length %2d Min group length %2d Difference %2d NumBetterScore %4d Best: %10.6f Group: %10.6f L1O: %10.6f\n', ModNames{g}(1:6), FASTA(n).Sequence, SeqLength(n), MinSeqLength(g), SeqLength(n)-MinSeqLength(g), NumBetterScore(n), max(m), MLPS(n,g,1), LeaveOneOut(n) );
  end
end

j = find((OwnGroup' > 0) .* (Helical(OwnGroup) == 0) .* (Structured(OwnGroup) == 1));  % structured internal loops
NBS = NumBetterScore(j);

figure(7)
maxrank = 10;
n = hist(min(NBS,maxrank),0:maxrank);
if length(n) < 10,
  n(10) = 0;
end
bar(0:maxrank,n/sum(n));
axis([-0.5 maxrank+0.5 0 max(n/sum(n))*1.1]);
set(gca,'XTick',0:10)
set(gca,'XTickLabel',{'0','1','2','3','4','5','6','7','8','9','>=10'})
title(['Leave-one-out diagnostic, ' num2str(length(NBS)) ' sequences against ' num2str(length(str)) ' structured models'],'fontsize',fs);
xlabel(['Number of models that score higher than correct model'],'fontsize',fs);
ylabel('Frequency','fontsize',fs);

% -------------------------------- Only show sequences with LeaveOneOut > -Inf

str = find((Structured == 1));  % structured internal loops
                                % this limits what *models* are compared to

for i = 1:NumSequences,
  SeqLength(i) = length(FASTA(i).Sequence)-1;
end

for g = 1:NumModels,
  j = find(OwnGroup == g);
  if ~isempty(j),
    MinSeqLength(g) = min(SeqLength(j));
  end
end

clear NumBetterScore
for n = 1:NumSequences,                     % loop through sequences
  g = OwnGroup(n);
  mlps = MLPS(n,:,:);                       % extract scores for this sequence
  m = max(mlps,[],3);                       % maximum over rotations
  m(g) = -Inf;                              % ignore own model's score
  NumBetterScore(n) = length(find(m(str) > LeaveOneOut(n)));

  if NumBetterScore(n) >= 10 && LeaveOneOut(n) > -Inf && Helical(g) == 0 && Structured(g) == 1,
    fprintf('%6s %20s Length %2d Min group length %2d Difference %2d NumBetterScore %4d Best: %10.6f Group: %10.6f L1O: %10.6f\n', ModNames{g}(1:6), FASTA(n).Sequence, SeqLength(n), MinSeqLength(g), SeqLength(n)-MinSeqLength(g), NumBetterScore(n), max(m), MLPS(n,g,1), LeaveOneOut(n) );
  end
end

j = find((LeaveOneOut > -Inf) .* (Helical(OwnGroup) == 0) .* (Structured(OwnGroup) == 1));  % sequences from structured internal loops
NBS = NumBetterScore(j);

figure(8)
maxrank = 10;
n = hist(min(NBS,maxrank),0:maxrank);
if length(n) < 10,
  n(10) = 0;
end
bar(0:maxrank,n/sum(n));
axis([-0.5 maxrank+0.5 0 max(n/sum(n))*1.1]);
set(gca,'XTick',0:10)
set(gca,'XTickLabel',{'0','1','2','3','4','5','6','7','8','9','>=10'})
title(['Leave-one-out diagnostic, ' num2str(length(NBS)) ' sequences against ' num2str(length(str)) ' structured models'],'fontsize',fs);
xlabel(['Number of models that score higher than correct model'],'fontsize',fs);
ylabel('Frequency','fontsize',fs);
