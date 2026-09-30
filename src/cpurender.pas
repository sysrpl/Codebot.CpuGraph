unit CpuRender;

{$mode delphi}

interface

uses
  Classes, SysUtils, Graphics,
  CpuInfo,
  CpuLayout,
  Codebot.System,
  Codebot.Forms.Widget,
  Codebot.Graphics,
  Codebot.Graphics.Types;

{ TCpuRender }

type
  TCpuRender = class
  private
    Monitor: TProcessorMonitor;
    Bitmap: IBitmap;
    { Background plus text which only changes once a second. Caching it
      keeps text layout out of the per frame work. }
    Overlay: IBitmap;
    OverlayDirty: Boolean;
    OverlayOffset: Double;
    Font: IFont;
    Bounds: TRectI;
    Caption: string;
    GridBoxes: TBoxes;
    Widget: TWidget;
    Layout: TCpuLayout;
    Surface: ISurface;
    ClientRect: TRectI;
    Offset: Double;
    Seconds: Integer;
    Usage: TArrayList<TProcessorUsage>;
    VisibleCore: TArrayList<Boolean>;
    procedure DrawUsage;
    procedure DrawGrids;
    procedure DrawOutline(Rect: TRectI);
    procedure DrawScales;
    procedure DrawSized;
    procedure DrawBackground;
    procedure DrawCaption;
    procedure DrawStats;
    procedure DrawTimeline;
    function GetOffsetTime: Double;
    procedure SetOffsetTime(Value: Double);
  public
    constructor Create;
    procedure ToggleCore(Index: Integer);
    procedure Render(Widget: TWidget; Layout: TCpuLayout);
    property OffsetTime: Double read GetOffsetTime write SetOffsetTime;
  end;

const
  clBack = TColor($D9E8ED);
  clBackDark = TColor($C2D2D5);

implementation

function CpuColor(Index: Integer): TColorB;
const
  { Twelve distinct hues which read well on a light background.
    Values are TColor, which is $BBGGRR }
  Colors: array[0..11] of TColor = (
    TColor($B4771F),  { blue }
    TColor($2827D6),  { red }
    TColor($2CA02C),  { green }
    TColor($0E7FFF),  { orange }
    TColor($BD6794),  { purple }
    TColor($CFBE17),  { cyan }
    TColor($C277E3),  { pink }
    TColor($4B568C),  { brown }
    TColor($22BDBC),  { olive }
    TColor($7F7F7F),  { gray }
    TColor($202020),  { black }
    TColor($02ABE6)); { gold }
begin
  Result := Colors[Index mod Length(Colors)];
end;

{ TCpuRender }

constructor TCpuRender.Create;
var
  I: Integer;
  S: string;
begin
  inherited Create;
  Monitor := ProcessorMonitor;
  S := Monitor.Model;
  S := S.FirstOf('@').Trim;
  if Monitor.Speed > 100 then
    Caption := Format('%s @ %.2f GHz with %d cores',
      [S, Monitor.Speed / 1000, Monitor.CoreCount])
  else
    Caption := S;
  Seconds := -1;
  Usage.Length := Monitor.CoreCount;
  for I := 0 to Monitor.CoreCount - 1 do
    VisibleCore.Push(True);
  Font := NewFont;
  { The graph is always light, so don't inherit a theme text color }
  Font.Color := clBlack;
  Bitmap := NewBitmap;
  Overlay := NewBitmap;
  OverlayDirty := True;
end;

procedure TCpuRender.ToggleCore(Index: Integer);
begin
  VisibleCore[Index] := not VisibleCore[Index];
  OverlayDirty := True;
end;

function CpuGradiant(const R: TRectI): IGradientBrush;
begin
  Result := NewBrush(R.TopLeft, R.BottomLeft);
  Result.AddStop(Rgba(clHighlight, 0.1), 0);
  Result.AddStop(Rgba(clHighlight, 0.4), 1);
end;

procedure TCpuRender.DrawOutline(Rect: TRectI);
begin
  Surface.FillRect(NewBrush(Rgba(clWhite, 0.25)), Rect);
  Surface.StrokeRect(NewPen(Rgba(clHighlight, 0.4)), Rect);
end;

procedure TCpuRender.DrawSized;
var
  Box: TRectI;
begin
  Surface.Rectangle(ClientRect);
  Surface.Fill(CpuGradiant(ClientRect), True);
  DrawOutline(Layout.GetCaption);
  for Box in Layout.GetGrids do
    DrawOutline(Box);
  for Box in Layout.GetStats do
    DrawOutline(Box);
  DrawOutline(Layout.GetSlider);
end;

function Mix(Source, Dest: TColorB; Percent: Float): TColorB;
begin
  Result := Source.Blend(Dest, Percent);
end;

procedure TCpuRender.DrawBackground;
var
  B: IGradientBrush;
  R, G: TRectI;
  P: IPen;
begin
  R := ClientRect;
  if Widget.Compositing then
  begin
    R.Inflate(-2, -2);
    Surface.RoundRectangle(R, 10);
  end
  else
    Surface.Rectangle(R);
  for R in Layout.GetGrids do
  begin
    Surface.MoveTo(R.Left, R.Top);
    Surface.LineTo(R.Left, R.Bottom);
    Surface.LineTo(R.Right, R.Bottom);
    Surface.LineTo(R.Right, R.Top);
    Surface.Path.Close;
  end;
  R := ClientRect;
  B := NewBrush(R.TopLeft, R.BottomLeft);
  B.AddStop(Rgba(clWhite, 0.85), 0);
  B.AddStop(Rgba(clBack, 0.7), 0.4);
  B.AddStop(Rgba(clBack, 0.8), 0.75);
  B.AddStop(clBackDark, 1);
  Surface.Fill(B);
  for G in Layout.GetGrids do
  begin
    R := G;
    R.Inflate(150, 100);
    R.Offset(0, 50);
    B := NewBrush(R);
    B.AddStop(Rgba(clWhite, 0.5), 0);
    B.AddStop(Mix(clWhite, clSilver, 0.2).Fade(0.65), 0.6);
    B.AddStop(Mix(clWhite, clSilver, 0.8).Fade(0.8), 1);
    R := G;
    Surface.FillRect(B, R);
  end;
  R := ClientRect;
  if Widget.Compositing then
  begin
    R.Inflate(-1, -1);
    Surface.RoundRectangle(R, 10);
  end
  else
    Surface.Rectangle(R);
  P := NewPen(Mix(clBack, clBlack, 0.3).Fade(0.5), 2);
  Surface.Stroke(P);
end;

procedure TCpuRender.DrawCaption;
begin
  Font.Size := 11;
  Surface.TextOut(Font, Caption, Layout.GetCaption, drCenter);
end;

procedure TCpuRender.DrawGrids;
const
  Delta = 0.5;
var
  G: TRectI;
  R: TRectF;
  P: IPen;
  I: Integer;
  X, W, X1, Y1: Float;
begin
  GridBoxes := Layout.GetGrids;
  for G in GridBoxes do
  begin
    R := G;
    R.Offset(1, 0.5);
    P := NewPen(Rgba(clMedGray, 1));
    P.LinePattern := pnDash;
    { Small per core graphs get fewer grid lines to avoid clutter }
    if G.Height < 60 then
    begin
      Y1 := Round(R.Top + G.Height / 2) + Delta;
      Surface.MoveTo(Round(R.Right - 2), Y1);
      Surface.LineTo(Round(R.Left), Y1);
      Surface.Stroke(P);
    end
    else
      for I := 0 to 8 do
      begin
        Y1 := Round(R.Top) + Delta;
        if (I > 0) and (I mod 2 = 0) then
        begin
          Surface.MoveTo(Round(R.Right - 2), Y1);
          Surface.LineTo(Round(R.Left), Y1);
          Surface.Stroke(P);
        end;
        R.Top := R.Top + G.Height / 10;
      end;
    R := G;
    R.Offset(0.5, 0.5);
    X := R.Left;
    W := R.Width / (Layout.TimeScale / 10);
    if G.Width >= 100 then
      for I := 1 to Layout.TimeScale div 10 - 1 do
      begin
        X1 := Round(X + W * I)  + Delta;
        Surface.MoveTo(X1, Round(R.Top));
        Surface.LineTo(X1, Round(R.Bottom - 2));
        Surface.Stroke(P);
      end;
    Surface.StrokeRect(NewPen(Rgba(clMedGray, 0.75)), G);
  end;
end;

procedure TCpuRender.DrawScales;
var
  Grid, B: TBox;
  I: Integer;
begin
  if GridBoxes.Length > 1 then
    Exit;
  Grid := GridBoxes[0];
  if Grid.Left < 20 then
    Exit;
  B := Grid;
  B.Left := 0;
  B.Height := 20;
  B.Right := Grid.Left - 4;
  B.Y := Grid.Top - 10;
  Font.Size := 8;
  for I := 0 to 5 do
  begin
    if Grid.Height < 150 then
      if I in [1, 2, 3, 4] then
        Continue;
    B.Y := Round(Grid.Top - 10 + Grid.Height / 5 * I);
    if I = 0 then
      B.Offset(0, 5)
    else if I = 5 then
      B.Offset(0, -5);
    Surface.TextOut(Font, IntToStr((5 - I) * 20) + '%', B, drRight);
  end;
end;

procedure TCpuRender.DrawTimeline;
var
  Grid, B: TBox;
  Min, Sec: Integer;
  S: string;
  W: Double;
  I, J: Integer;
begin
  if GridBoxes.Length > 1  then
    Exit;
  Grid := GridBoxes[0];
  B := Layout.GetSlider;
  if B.Top - Grid.Bottom < 10 then
    Exit;
  if Offset < 1 then
    S := IntToStr(Layout.TimeScale) + ' seconds'
  else if Offset > 3599 - Layout.TimeScale then
    S := '1 hour ago'
  else
  begin
    Min := Trunc(Layout.TimeScale + Offset) div 60;
    Sec := Trunc(Layout.TimeScale + Offset);
    Sec := Sec mod 60;
    S := Format('%d:%.2d ago', [Min, Sec]);
  end;
  B := Grid;
  B.Top := B.Bottom;
  B.Height := 20;
  B.Width := 100;
  Font.Size := 8;
  if B.X > 20 then
    B.X := B.X - 20;
  Surface.TextOut(Font, S, B, drLeft);
  W := Grid.Width / Layout.TimeScale * 10;
  J := Layout.TimeScale div 10;
  for I := 1 to J do
  begin
    B.X := Round(Grid.X - 50 + I * W);
    if Offset < 1 then
    begin
      S := IntToStr(Layout.TimeScale - I * 10);
    end
    else if Offset > 3599 - Layout.TimeScale then
    begin
      Min := 59;
      Sec := 60 - I * 10;
      S := Format('%d:%.2d', [Min, Sec]);
    end
    else
    begin
      Min := Trunc((J - I) * 10 + Offset) div 60;
      Sec := Trunc((J - I) * 10 + Offset);
      Sec := Sec mod 60;
      S := Format('%d:%.2d', [Min, Sec]);
    end;
    if I = J then
    begin
      B.Right := Grid.Right;
      Surface.TextOut(Font, S, B, drRight);
    end
    else
      Surface.TextOut(Font, S, B, drCenter);
  end;
end;

function TCpuRender.GetOffsetTime: Double;
begin
	  Result := Offset;
end;

procedure TCpuRender.SetOffsetTime(Value: Double);
begin
  if Value <> Offset then
	  Offset := Value;
end;

procedure TCpuRender.DrawUsage;
const
  Range = 4;
var
  Core: TProcessorCore;
  Usage: PProcessorUsage;
  Start, Time: Double;
  Data: array[0..Range - 1] of Double;
  Total: Double;
  Moved: Boolean;
  Box: TBox;
  R: TRectI;
  P: IPen;
  X, Y: Float;
  J, K: Integer;

  procedure DrawLines;
  var
    Points: array of TPointF;
    Count, BucketCount: Integer;
    Key, BucketKey, LiveKey: Int64;
    BucketSec, BucketSum: Double;
    P0, P1, P2, P3, C1, C2: TPointF;
    I: Integer;

    { Place a bucket's average at the middle of its time span }
    procedure AddBucket(BKey: Int64; Value: Double);
    var
      Age: Double;
    begin
      if Count = Length(Points) then
        SetLength(Points, Count * 2 + 16);
      { Shift by 2.5 buckets so the newest finished segment always reaches
        past the right edge, leaving no gap while the next bucket fills }
      Age := Start - (BKey + 0.5) * BucketSec - 2.5 * BucketSec;
      Points[Count] := TPointF.Create(R.Right - Age / Layout.TimeScale * R.Width,
        R.Bottom - R.Height * Value);
      Inc(Count);
    end;

    function Clamp(V, Lo, Hi: Float): Float;
    begin
      if V < Lo then Result := Lo
      else if V > Hi then Result := Hi
      else Result := V;
    end;

  begin
    Core := Monitor.Cores[J];
    Start := TimeQuery - Offset;
    Total := 0;
    Data[0] := 0;
    for I := Low(Data) + 1 to High(Data) do
    begin
      Data[I] := Core.Usage[I].Utilization;
      Total := Total + Data[I];
    end;
    Moved := False;
    K := 0;
    if Offset > 0 then
    begin
      K := Round(Offset * 3.75);
      while True do
      begin
        Usage := Core.Usage[K + 1000];
        if Usage = nil then
          Break;
        if Usage.Time < Start then
          Break;
        Inc(K, 1000);
      end;
      while True do
      begin
        Usage := Core.Usage[K + 100];
        if Usage = nil then
          Break;
        if Usage.Time < Start then
          Break;
        Inc(K, 100);
      end;
      while True do
      begin
        Usage := Core.Usage[K + 25];
        if Usage = nil then
          Break;
        if Usage.Time < Start then
          Break;
        Inc(K, 25);
      end;
    end;
    { Average the raw samples into buckets fixed to absolute time, so a
      bucket always holds the same samples no matter when it is drawn }
    { One second buckets hold about four samples each, so none are empty }
    BucketSec := 1;
    { Skip the bucket still collecting samples }
    LiveKey := Trunc(TimeQuery / BucketSec);
    Count := 0;
    BucketCount := 0;
    BucketSum := 0;
    BucketKey := -1;
    for I := K to Monitor.Ticks - Range do
    begin
      Usage := Core.Usage[I];
      if Usage = nil then
        Break;
      Key := Trunc(Usage.Time / BucketSec);
      if Key >= LiveKey then
        Continue;
      if (BucketCount > 0) and (Key <> BucketKey) then
      begin
        AddBucket(BucketKey, BucketSum / BucketCount);
        BucketCount := 0;
        BucketSum := 0;
      end;
      BucketKey := Key;
      BucketSum := BucketSum + Usage.Utilization;
      Inc(BucketCount);
      { Keep a few buckets past the left edge so the visible curves always
        have their real neighbors }
      if Start - Usage.Time > Layout.TimeScale + 4 * BucketSec + 3 then
        Break;
    end;
    { Points run from newest to oldest. Only draw a segment once both of
      its neighbors exist, so a drawn curve never changes shape. The
      newest segment waits until the next bucket completes. }
    if Count < 4 then
      Exit;
    Surface.MoveTo(Points[1].X, Points[1].Y);
    for I := 1 to Count - 3 do
    begin
      P0 := Points[I - 1];
      P1 := Points[I];
      P2 := Points[I + 1];
      P3 := Points[I + 2];
      C1 := TPointF.Create(P1.X + (P2.X - P0.X) / 6, P1.Y + (P2.Y - P0.Y) / 6);
      C2 := TPointF.Create(P2.X - (P3.X - P1.X) / 6, P2.Y - (P3.Y - P1.Y) / 6);
      { Keep the curve from swinging outside 0% to 100% }
      C1.Y := Clamp(C1.Y, R.Top, R.Bottom);
      C2.Y := Clamp(C2.Y, R.Top, R.Bottom);
      Surface.CurveTo(P2.X, P2.Y, C1, C2);
    end;
    P.Color := CpuColor(J).Fade(0.8);
    Surface.Stroke(P);
  end;

begin
  if Monitor.Ticks < Range + 1 then
    Exit;
  J := 0;
  for Box in GridBoxes do
  begin
    R := Box;
    R.Inflate(-1, -1);
    Surface.Rectangle(R);
    Surface.Path.Clip;
    P := NewPen(clBlack, 1.3);
    if GridBoxes.Length < Monitor.CoreCount then
      for J := 0 to Monitor.CoreCount - 1 do
      begin
        if VisibleCore[J] then
          DrawLines;
      end
      else
        DrawLines;
    Surface.Path.Unclip;
    Inc(J);
    if GridBoxes.Length < Monitor.CoreCount then
      Break;
  end;
end;

procedure TCpuRender.DrawStats;
var
  Color: TColorB;
  G, R: TRectI;
  S: string;
  I: Integer;
begin
  Font.Size := 9;
  I := 0;
  for G in Layout.GetStats do
  begin
    R := G;
    R.Width := 50;
    R.Height := 25;
    R.Y := G.Y + (G.Height - R.Height) div 2;
    Color := CpuColor(I);
    Surface.StrokeRect(NewPen(Color.Darken(0.5)), R);
    R.Inflate(-1, -1);
    Surface.StrokeRect(NewPen(Color.Lighten(0.5)), R);
    R.Inflate(-1, -1);
    if VisibleCore[I] then
      Surface.FillRect(NewBrush(Color), R)
    else
      Surface.FillRect(Brushes.Dither(clBackDark, Color), R);
    R := G;
    R.Left := R.Left + 54;
    R.Offset(0, -2);
    S := 'CPU%d: %.1f%s'#10'%.1f GHz'.Format([I, Usage[I].Utilization * 100, '%',
      Usage[I].Speed / 1024]);
    Surface.TextOut(Font, S, R, drLeft);
    Inc(I);
  end;
end;

procedure TCpuRender.Render(Widget: TWidget; Layout: TCpuLayout);
var
  R: TRectI;
  S: Integer;
  I: Integer;
begin
  Self.Widget := Widget;
  Self.Layout := Layout;;
  Surface := Widget.Surface;
  ClientRect := Widget.ClientRect;
  if Widget.Sized then
  begin
    DrawSized;
    Exit;
  end;
  R := ClientRect;
  Surface := Bitmap.Surface;
  if (R.Width <> Bounds.Width) or (R.Height <> Bounds.Height) then
  begin
    Bounds := R;
    Bitmap.SetSize(Bounds.Width, Bounds.Height);
    DrawBackground;
    DrawCaption;
    DrawGrids;
    DrawScales;
    OverlayDirty := True;
  end;
  S := Round(Floor(TimeQuery));
  if S > Seconds then
  begin
    Seconds := S;
    for I := 0 to Monitor.CoreCount - 1 do
      Monitor.Cores[I].Average(0, 4, Usage.Items[I]);
    OverlayDirty := True;
  end;
  if Offset <> OverlayOffset then
    OverlayDirty := True;
  if OverlayDirty then
  begin
    OverlayDirty := False;
    OverlayOffset := Offset;
    Overlay.SetSize(Bounds.Width, Bounds.Height);
    Overlay.Surface.Clear(clTransparent);
    Bitmap.Surface.CopyTo(ClientRect, Overlay.Surface, ClientRect);
    Surface := Overlay.Surface;
    DrawTimeline;
    DrawStats;
  end;
  Overlay.Surface.CopyTo(ClientRect, Widget.Surface, ClientRect);
  Surface := Widget.Surface;
  DrawUsage;
  Surface := nil;
  Self.Layout := nil;
  Self.Widget := nil;
end;

end.

