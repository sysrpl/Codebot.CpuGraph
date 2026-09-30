program cpugraph;

{$mode delphi}

uses
  Codebot.System, Codebot.Unique,
  Interfaces, // this includes the LCL widgetset
  Forms, Main, CpuLayout, CpuRender
  { you can add units after this };

{$R *.res}

begin
  if UniqueInstance('program cpugraph').Original then
  begin
    RequireDerivedFormResource := True;
    Application.Initialize;
    Application.CreateForm(TMainForm, MainForm);
    Application.Run;
  end;
end.

