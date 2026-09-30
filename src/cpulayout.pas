unit CpuLayout;

{$mode delphi}

interface

uses
  Classes, SysUtils,
  CpuInfo,
  Codebot.System,
  Codebot.Graphics,
  Codebot.Graphics.Types;

type
  TBox = TRectI;
  TBoxes = TArrayList<TBox>;

  { TCpuLayout }

  TCpuLayout = class
  private
    FBounds: TBox;
    FCores: Integer;
    FTimeScale: Integer;
    function GetStatsSize: TPointI;
    function GetStatsGrid: TPointI;
    function GetStatsHeight: Integer;
  public
    constructor Create;
    procedure Resize(Bounds: TBox);
    function GetCaption: TBox;
    function GetGrids: TBoxes;
    function GetStats: TBoxes;
    function GetSlider: TBox;
    property TimeScale: Integer read FTimeScale;
  end;

implementation

{ TCpuLayout }

var
  Empty: TBox;

constructor TCpuLayout.Create;
begin
  inherited Create;
  FCores := ProcessorMonitor.CoreCount;
  FTimeScale := 60;
end;

function TCpuLayout.GetStatsSize: TPointI;
begin
  Result := TPointI.Create(150, 40);
end;

function TCpuLayout.GetStatsGrid: TPointI;
var
  S: TPointI;
  W, X, Y: Integer;
begin
  S := GetStatsSize;
  W := FBounds.Width - 50;
  X := W div S.X;
  if X < 1 then
    X := 1;
  Y := FCores div X + 1;
  if FCores mod X = 0 then
    Dec(Y);
  Result.X := X;
  Result.Y := Y;
  if (Result.Y = 1) and (Result.X > FCores) then
    Result.X := FCores;
end;

function TCpuLayout.GetStatsHeight: Integer;
var
  S, G: TPointI;
begin
  S := GetStatsSize;
  G := GetStatsGrid;
  Result := G.Y * S.Y;
end;

procedure TCpuLayout.Resize(Bounds: TBox);
begin
  FBounds := Bounds;
end;

function TCpuLayout.GetCaption: TBox;
begin
  Result := FBounds;
  Result.Inflate(-10, 0);
  Result.Top := 2;
  Result.Height := 24;
  if FBounds.Height < 220 then
    Result := Empty;
  if FBounds.Width < 220 then
    Result := Empty;
end;

{ Find the columns and rows of per core graphs which best fill Area. Cells
  closest to a 2:1 shape win. Returns false if no arrangement fits. }

function ArrangeCells(const Area: TBox; Cores: Integer; out Cols, Rows: Integer): Boolean;
const
  MinCellW = 48;
  MinCellH = 24;
  Gap = 4;
var
  C, R, W, H, Score, Best: Integer;
begin
  Result := False;
  Best := 0;
  Cols := 0;
  Rows := 0;
  for C := 1 to Cores do
  begin
    R := (Cores + C - 1) div C;
    W := (Area.Width - (C - 1) * Gap) div C;
    H := (Area.Height - (R - 1) * Gap) div R;
    if (W < MinCellW) or (H < MinCellH) then
      Continue;
    if W < H * 2 then
      Score := W
    else
      Score := H * 2;
    if Score > Best then
    begin
      Best := Score;
      Cols := C;
      Rows := R;
      Result := True;
    end;
  end;
end;

function TCpuLayout.GetGrids: TBoxes;
const
  Gap = 4;
var
  Stats: TBoxes;
  B, Cell: TBox;
  Cols, Rows, I: Integer;
begin
  B := FBounds;
  B.Left := 40;
  B.Top:= 28;
  if FBounds.Height < 220 then
  begin
    B.Left := 10;
    B.Top := 8;
  end;
  if FBounds.Width < 220 then
    B.Top := 8;
  B.Right := FBounds.Right - 10;
  B.Bottom := FBounds.Bottom - 30;
  if (FBounds.Width < 300) or (FBounds.Height < 120) then
    B.Bottom := FBounds.Bottom - 8;
  if FBounds.Width < 220 then
    B.Left := 10;
  Stats := GetStats;
  if Stats.Length > 0 then
    B.Bottom := Stats[0].Top - 20
  else if (FBounds.Height >= 200) and (FBounds.Width > 300) then
    B.Bottom := B.Bottom - 20;
  { Small windows show a grid of per core graphs when they fit }
  if (FCores > 1) and ((FBounds.Width < 220) or (FBounds.Height < 200)) and
    ArrangeCells(B, FCores, Cols, Rows) then
  begin
    Cell := B;
    Cell.Width := (B.Width - (Cols - 1) * Gap) div Cols;
    Cell.Height := (B.Height - (Rows - 1) * Gap) div Rows;
    for I := 0 to FCores - 1 do
    begin
      Cell.X := B.X + (I mod Cols) * (Cell.Width + Gap);
      Cell.Y := B.Y + (I div Cols) * (Cell.Height + Gap);
      Result.Push(Cell);
    end;
    B := Cell;
  end
  else
    Result.Push(B);
  if B.Width < 200 then
    FTimeScale := 20
  else if B.Width < 400 then
    FTimeScale := 30
  else
    FTimeScale := 60;
end;

function Max(A, B: Integer): Integer; inline;
begin
  if A > B then Result := A else Result := B;
end;

function TCpuLayout.GetStats: TBoxes;
var
  GridSize, StatsSize: TPointI;
  Box: TBox;
  W, H, I: Integer;
begin
  Result.Length := 0;
  GridSize := GetStatsGrid;
  StatsSize := GetStatsSize;
  if (FBounds.Width > 320) and (FBounds.Height > GridSize.Y * StatsSize.Y + 160) then
  begin
    H := GetStatsHeight + 28;
    Result.Length := FCores;
    W := 0;
    for I := 0 to FCores - 1 do
    begin
      Box := TBox.Create(StatsSize);
      Box.Width := Box.Width;
      Box.Height := Box.Height;
      Box.X := 40;
      Box.Y := FBounds.Bottom - H + StatsSize.Y * (I div GridSize.X);
      Box.X := Box.X + (I mod GridSize.X) * StatsSize.X;
      W := Box.Right;
      Result[I] := Box;
    end;
    if W < FBounds.Width - 10 - GridSize.X - 1 then
    begin
      W := FBounds.Width - 50 - GridSize.X * StatsSize.X;
      W := W div 2;
      for I := 0 to FCores - 1 do
        Result.Items[I].X := Result.Items[I].X + W;
    end;
  end;
end;

function TCpuLayout.GetSlider: TBox;
begin
  Result := FBounds;
  Result.Left := 40;
  Result.Right := FBounds.Right - 40;
  Result.Top := Result.Bottom - 30;
  Result.Height := 30;
  if (FBounds.Width < 300) or (FBounds.Height < 120) then
    Result := Empty;
end;

end.

