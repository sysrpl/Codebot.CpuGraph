unit Main;

{$mode delphi}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs,
  LCLType, LCLIntf, ExtCtrls, Menus, StdCtrls, CpuInfo, CpuLayout, CpuRender,
  Codebot.System,
  Codebot.Input.Hotkeys,
  Codebot.Animation,
  Codebot.Graphics,
  Codebot.Graphics.Types,
  Codebot.Forms.Widget,
  Codebot.Controls.Sliders;

{ TMainForm }

type
  TMainForm = class(TWidget)
    QuitMenuItem: TMenuItem;
    ShowMenuItem: TMenuItem;
    PopupMenu: TPopupMenu;
    TimeBar: TSlideBar;
    TrayIcon: TTrayIcon;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure QuitMenuItemClick(Sender: TObject);
    procedure ShowMenuItemClick(Sender: TObject);
    procedure TimeBarChange(Sender: TObject);
    procedure TimeBarDrawBackground(Sender: TObject; Surface: ISurface;
      Rect: TRectI; State: TDrawState);
    procedure TimeBarDrawThumb(Sender: TObject; Surface: ISurface;
      Rect: TRectI; State: TDrawState);
  private
    FLayout: TCpuLayout;
    FRender: TCpuRender;
    FSize: TPointI;
    FTime: Double;
    FSecond: Integer;
    procedure ToggleDisplay(Sender: TObject; Key: Word; Shift: TShiftState);
  protected
    procedure Render; override;
    procedure ClickBox(Index: Integer); override;
    function GripColor(Sizing: Boolean): TColorB; override;
    procedure DoTick(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Width := 650;
  Height := 300;
  MinHeight := 96;
  MinWidth := 96;
  Center;
  ProcessorMonitor.Active := True;
  FLayout := TCpuLayout.Create;
  FRender := TCpuRender.Create;
  OnTick := DoTick;
  HotkeyCapture.RegisterNotify(VK_U, [ssCtrl, ssAlt], ToggleDisplay);
  TrayIcon.Visible := True;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  HotkeyCapture.UnregisterNotify(VK_U, [ssCtrl, ssAlt]);
  ProcessorMonitor.Active := False;
  FRender.Free;
  FLayout.Free;
end;

procedure TMainForm.QuitMenuItemClick(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.ShowMenuItemClick(Sender: TObject);
begin
  Faded := not Faded;
  Animated := not Faded;
end;

procedure TMainForm.TimeBarChange(Sender: TObject);
var
  D: Double;
begin
  D := TimeBar.Position / TimeBar.Max;
  D := 1 - D;
  D := Round(59 * 60 * D);
  FRender.OffsetTime := D;
  Invalidate;
end;

procedure TMainForm.TimeBarDrawBackground(Sender: TObject; Surface: ISurface;
  Rect: TRectI; State: TDrawState);
const
  Size = 20;
var
  R: TRectI;
begin
  R := Rect;
  R.Height := Size;
  R.Top := TimeBar.Height div 2 - Size div 2 + 2;
  Surface.FillRoundRect(NewBrush(Rgba(clBlack, 0.1)), R, Size div 2);
  Surface.StrokeRoundRect(NewPen(Rgba(clBackDark, 0.5).Darken(0.3)), R, Size div 2);
end;

procedure TMainForm.TimeBarDrawThumb(Sender: TObject; Surface: ISurface;
  Rect: TRectI; State: TDrawState);
const
  Size = 10;
var
  R: TRectI;
  C: TColorB;
begin
  R := TRectI.Create(Size, Size);
  R.Center(Rect.MidPoint);
  R.Offset(0, -2);
  if R.X < 2 then
    R.X := 2;
  if R.Right > TimeBar.Width - 2 then
    R.X := TimeBar.Width - R.Width - 2;
  Surface.Ellipse(R);
  if dsPressed in State then
    C := clHighlight
  else if dsHot in State then
    C := clWhite
  else
    C := clBack;
  Surface.Fill(NewBrush(C));
end;

procedure TMainForm.Render;
var
  S: TPointI;
  R: TRectI;
begin
  FLayout.Resize(ClientRect);
  if Sized then
    TimeBar.Visible := False
  else
  begin
    S := ClientRect.BottomRight;
    R := FLayout.GetSlider;
    if (not R.Empty) and (S.X <> FSize.X) or (S.Y <> FSize.Y) then
    begin
      ClickBoxes(FLayout.GetStats);
      FSize := S;
      TimeBar.SetBounds(R.Left, R.Top, R.Width, R.Height);
      TimeBar.Visible := True;
    end
    else
      TimeBar.Visible := not R.Empty;
  end;
  FRender.Render(Self, FLayout);
end;

procedure TMainForm.ClickBox(Index: Integer);
begin
  FRender.ToggleCore(Index);
end;

function TMainForm.GripColor(Sizing: Boolean): TColorB;
begin
  { Use the dark end of the background gradient, darkened a little more
    while resizing }
  if Sizing then
    Result := TColorB(clBackDark).Darken(0.35)
  else
    Result := TColorB(clBackDark).Darken(0.15);
end;

procedure TMainForm.DoTick(Sender: TObject);
var
  T: Double;
  S: Integer;
  B: TRectI;
  R: TRect;
  First: Boolean;
begin
  T := TimeQuery;
  if T - FTime > 0.1 then
  begin
    while FTime < T - 0.1 do
      FTime := FTime + 0.1;
    { Stats text changes once a second, so repaint everything then. In
      between only the graphs scroll, so repaint just those. }
    S := Trunc(T);
    if (S <> FSecond) or Sized or not HandleAllocated then
    begin
      FSecond := S;
      Invalidate;
      Exit;
    end;
    First := True;
    for B in FLayout.GetGrids do
      if First then
      begin
        R := Rect(B.Left, B.Top, B.Right, B.Bottom);
        First := False;
      end
      else
      begin
        if B.Left < R.Left then R.Left := B.Left;
        if B.Top < R.Top then R.Top := B.Top;
        if B.Right > R.Right then R.Right := B.Right;
        if B.Bottom > R.Bottom then R.Bottom := B.Bottom;
      end;
    if First then
      Invalidate
    else
    begin
      InflateRect(R, 2, 2);
      InvalidateRect(Handle, @R, False);
    end;
  end;
end;

procedure TMainForm.ToggleDisplay(Sender: TObject; Key: Word; Shift: TShiftState);
begin
  ShowMenuItem.Click;
end;

end.

