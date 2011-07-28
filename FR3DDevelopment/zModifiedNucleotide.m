
% preliminary work on getting a rotation matrix for modified nucleotide

% F = zReadandAnalyzeModNucl('1S72.pdb',1);

Code = cat(1,F.NT.Code);

mn = find(Code == 5);

VP.Sugar = 1;
VP.AtOrigin = 1;

for i = 16:length(mn),

  NT = F.NT(mn(i));
  NT = zFitModifiedNucleotide(NT,1);
  F.NT(mn(i)) = NT;

  figure(1)
  clf
  zDisplayNT(F,mn(i),VP);
  view(2)
  
  if VP.AtOrigin == 0,
    L = NT.Loc;
    for j = 1:length(L(:,1)),         % loop over atoms
      text(L(j,1),L(j,2),L(j,3),NT.AtomName(j));
    end
  end


  figure(2)
  clf
  zPlotStandardBase(4,1)

  pause
end

break

% ---------------------- Read NR files to build collection of known
%                        modified NTs

Filenames = zReadPDBList('Nonredundant_4A_2011-06-18_list',1);

VP.Sugar = 1;
VP.AtOrigin = 1;

for f = 1:length(Filenames),               % 1S72 is the first!
  F = zReadandAnalyzeModNucl([Filenames{f} '.pdb'],1);

  c = cat(1,F.NT.Center);
  D = zMutualDistance(c,20); % compute distances < 16 Angstroms

  for i = 1:length(F.NT),
    if F.NT(i).Code == 5,                  % modified nucleotide,
      j = find((D(i,:) < 15) .* (D(i,:) > 0));
      figure(1)
      clf
      k = i;
      for jj = 1:length(j),
        DC = F.NT(i).Center - F.NT(j(jj)).Center;
        n  = F.NT(j(jj)).Rot * [0 0 1]';    % near the plane of the base
        if abs(DC*n / norm(DC)) < 0.4 || F.NT(j(jj)).Code > 4,
          k = [k j(jj)];
        end
      end
      [R,S] = zDisplayNT(F,k,VP);
      view(2)

      saveas(gcf,[F.Filename '_' F.NT(i).Chain '_' F.NT(i).Base '_' F.NT(i).Number '.png']);

      saveas(gcf,[F.Filename '_' F.NT(i).Chain '_' F.NT(i).Base '_' F.NT(i).Number '.fig']);

      fid = fopen([F.Filename '_' F.NT(i).Chain '_' F.NT(i).Base '_' F.NT(i).Number '.pdb'],'w');

      a = 1;                               % atom number

      sh = [0 0 0];
      Rot = F.NT(i).Rot;

      for kk = 1:length(k),
        a = zWriteNucleotidePDB(fid,F.NT(k(kk)),a,0);
      end

      fclose(fid);
      
%pause
    end
  end

end




break




% F = zReadandAnalyzeModNucl('1H3E.pdb',1);

ModList = {'5BU','PSU','H2U','OMG','5IC','5IU'};

c = 1;

for f = 1:length(File),
  d = 1;
  clear W

  for n = 1:length(File(f).Het),
    G(c,:) = '   ';
    W(d,:) = '   ';
    h = File(f).Het(n).Unit;
    L = length(h);
    G(c,1:L) = h;
    W(d,1:L) = h;
    c = c + 1;
    d = d + 1;
  end

  if length(File(f).Het) > 0,
    [b,t,i] = zUniqueRows(W);

    fprintf('%4s %s | %s | %s\n', File(f).Filename, File(f).Info.Source, File(f).Info.Descriptor, File(f).Info.Author);

    for n = 1:length(b(:,1)),
      fprintf('%4s occurs %10d times\n', b(n,:), t(n));
    end
  
    fprintf('\n');
  end
end

[b,t,i] = zUniqueRows(G);

fprintf('Report on HETATM records, some of which are modified nucleotides\n');

for n = 1:length(b),
  fprintf('%4s occurs %10d times\n', b(n,:), t(n));
end

for f = 1:length(File),
  fprintf('PDB file %s\n', File(f).Filename);

  for n = 1:length(File(f).Het),
    h = File(f).Het(n).Unit;
    if ~isempty(find(ismember(h,ModList))),
      File(f).Het(n)
    end
  end
end


break


for f = 231:length(Filenames),
  F = zReadandAnalyzeModNucl([Filenames{f} '.pdb'],1);
end


break


