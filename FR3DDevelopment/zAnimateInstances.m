% zAnimateInstances(Search) displays the first instance from Search, asks
% the user to orient it in space, aligns all other instances to the first,
% writes out PDB files for each, then writes a jmol script to display and
% rotate each one and write out separate frames that can be made into an
% animated gif

% function [void] = zAnimateInstances(Search,VP,n)

if nargin < 2 || 0 < 1,
  VP.Sugar = 1;
  VP.LabelBases = 0;
  VP.AtOrigin = 1;
end

if nargin < 3,
  n = 3;
end

Cand = Search.Candidates;
[L,N] = size(Cand);
N = N - 1;                    % number of instances


  
f1 = Cand(1,N+1);              % file number of first instance
File1 = Search.File(f1);
R = File1.NT(Cand(1,n)).Rot;  % rotation matrix of key nucleotide
S = File1.NT(Cand(1,n)).Fit(1,:); % location of first atom
VPP = VP;
VPP.Plot = 0;
figure(1)

% set nDegrees * nFrames * L = k*360 to make it join smoothly

fid = fopen('script.jmol','w');
fprintf(fid,'%s\n','  thisFrame = 0;');  % current frame number
fprintf(fid,'%s\n','  nDegrees = 5.1429/2;');   % angle to rotate per frame
fprintf(fid,'%s\n','  nFrames = 10;');    % number of frames per instance
fprintf(fid,'%s\n','  cumDegrees = 0;');  % degrees rotated so far
fprintf(fid,'%s\n',['  cd ' pwd]);    % number of frames per instance
fprintf(fid,'\n');

for c = 1:L,
  f2 = Cand(c,N+1);           % file number of current candidate
  [disc,Shift,SuperR] = zSuperimposeNucleotides(File1,Cand(1,1:N),Search.File(f2),Cand(c,1:N),VPP);
  clf
  VP.Rotation = SuperR*R;
  VP.Shift    = Shift+S;
  VP.AtOrigin = 0;
  zDisplayNT(Search.File(f2),Cand(c,[1:N]),VP);
%  pause
  F.NT = Search.File(f2).NT(Cand(c,1:N));
  Filename = [zLeadingZeros(c,5) '.pdb'];
  zWritePDB(F,Filename,SuperR*R,Shift+S);

  fprintf(fid,'%s\n','  refresh;');
  fprintf(fid,'%s\n',['  load "' Filename '"']);
  fprintf(fid,'%s\n','  select all');
  fprintf(fid,'%s\n','  wireframe 75');
  fprintf(fid,'%s\n','  zoom 140');
  fprintf(fid,'%s\n','  select [U]; color blue');
  fprintf(fid,'%s\n','  select [A]; color red');
  fprintf(fid,'%s\n','  select [C]; color gold');
  fprintf(fid,'%s\n','  select [G]; color green');
  fprintf(fid,'%s\n','  select backbone; color gray');
  fprintf(fid,'%s\n','  background white;');
  fprintf(fid,'%s\n','  width = 640;');
  fprintf(fid,'%s\n','  height = 480;');
  fprintf(fid,'%s\n','  set zoomLarge false;');
  fprintf(fid,'%s\n','  refresh;');
  fprintf(fid,'%s\n','  thisInstanceFrame = 0;');  % current frame number

  fprintf(fid,'%s\n','  rotate x -90;');
  fprintf(fid,'%s\n','  rotate y @cumDegrees;');

  fprintf(fid,'  message loop%d;\n',c);
  fprintf(fid,'%s\n','  thisInstanceFrame = thisInstanceFrame + 1;');
  fprintf(fid,'%s\n','  thisFrame = thisFrame + 1;');
  fprintf(fid,'%s\n','  name = "./frame00000.gif";');
  fprintf(fid,'%s\n','  fileName = name.replace("00000","" + ("00000" + thisFrame)[-4][0]);');
  fprintf(fid,'%s\n','  #rotate x @nDegrees;');
  fprintf(fid,'%s\n','  rotate y @nDegrees;  # use these options if you want to rotate the molecule');
  fprintf(fid,'%s\n','  cumDegrees = cumDegrees + nDegrees;');
  fprintf(fid,'%s\n','  #rotate z @nDegrees;');
  fprintf(fid,'%s\n','  #frame next; # only use this if you have a multiframe file.');
  fprintf(fid,'%s\n','  refresh;');
  fprintf(fid,'%s\n','  write image @width @height @fileName;');
  fprintf(fid,'  if (thisInstanceFrame < nFrames);goto loop%d;endif;\n',c);
  fprintf(fid,'  zap\n');
  fprintf(fid,'\n');

end

fprintf(fid,'# gifsicle --delay=10 --colors 256 --loop frame*.gif > animated.gif\n');

fclose(fid);