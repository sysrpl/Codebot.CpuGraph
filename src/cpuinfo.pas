unit CpuInfo;

{$mode delphi}

interface

uses
  Classes, SysUtils,
  Codebot.System;

{ TProcessorUsage }

type
  TProcessorUsage = record
    Utilization: Double;
    Speed: Single;
    Time: Double;
  end;

  PProcessorUsage = ^TProcessorUsage;

{ TProcessorCore }

  TProcessorCore = class
  private
    FUsage: TArrayList<TProcessorUsage>;
    FIndex: Integer;
    function GetUsage(Index: Integer): PProcessorUsage;
  protected
    procedure Next;
  public
    constructor Create;
    function Average(Index, Range: Integer; out Usage: TProcessorUsage): Boolean;
    property Usage[Index: Integer]: PProcessorUsage read GetUsage;
  end;

{ TProcessorMonitor }

  TProcessorMonitor = class
  private
    FActive: Boolean;
    FTicks: Integer;
    FCores: TArrayList<TProcessorCore>;
    FUsage: TArrayList<TProcessorUsage>;
    FModel: string;
    FSpeed: Integer;
    FThread: TSimpleThread;
    procedure Execute(Thread: TSimpleThread);
    procedure SetActive(Value: Boolean);
    function GetCore(Index: Integer): TProcessorCore;
    function GetCoreCount: Integer;
  protected
    procedure Initialize; virtual; abstract;
    procedure Work(Thread: TSimpleThread); virtual; abstract;
  public
    constructor Create;
    destructor Destroy; override;
    property Active: Boolean read FActive write SetActive;
    property Ticks: Integer read FTicks;
    property Cores[Index: Integer]: TProcessorCore read GetCore;
    property CoreCount: Integer read GetCoreCount;
    property Model: string read FModel;
    property Speed: Integer read FSpeed;
  end;

{ The global ProcessorMonitor object }

function ProcessorMonitor: TProcessorMonitor;

implementation

{$ifdef linux}
{ Contents of various files:

/proc/cpuinfo
-----
processor	: 0
vendor_id	: AuthenticAMD
cpu family	: 16
model		: 5
model name	: AMD Athlon(tm) II X4 630 Processor
stepping	: 2
microcode	: 0x10000c6
cpu MHz		: 800.000
cache size	: 512 KB
physical id	: 0
siblings	: 4
core id		: 0
cpu cores	: 4

/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq
-----
800000

/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq
-----
2800000

/proc/stat
-----
cpu  528755 66117 132403 9907546 67604 20 8706 0 0 0
cpu0 132794 16744 32842 2484423 14577 0 754 0 0 0
cpu1 128018 18489 32075 2491808 11818 0 13 0 0 0
cpu2 129016 14810 33331 2484993 12281 12 45 0 0 0
cpu3 138926 16073 34154 2446320 28927 7 7893 0 0 0 }

{ TLinuxCoreData represents the data above }

var
  IdValues: StringArray;

procedure IdParse(const S: string);
begin
  IdValues := S.Split(' ');
end;

function IdUser: Int64; inline; begin Result := StrToInt64(IdValues[1]); end;
function IdNice: Int64; inline; begin Result := StrToInt64(IdValues[2]); end;
function IdSystem: Int64; inline; begin Result := StrToInt64(IdValues[3]); end;
function IdIdle: Int64; inline; begin Result := StrToInt64(IdValues[4]); end;
function IdIowait: Int64; inline; begin Result := StrToInt64(IdValues[5]); end;
function IdIrq: Int64; inline; begin Result := StrToInt64(IdValues[6]); end;
function IdSoftirq: Int64; inline; begin Result := StrToInt64(IdValues[7]); end;
function IdSteal: Int64; inline; begin Result := StrToInt64(IdValues[8]); end;
function IdGuest: Int64; inline; begin Result := StrToInt64(IdValues[9]); end;
function IdGuestNice: Int64; inline; begin Result := StrToInt64(IdValues[10]); end;

type
  TLinuxCoreData = record
    Idle: Int64;
    Total: Int64;
  end;

{ TLinuxMonitor }

type
  TLinuxMonitor = class(TProcessorMonitor)
  private
    FCoreData: TArrayList<TLinuxCoreData>;
    procedure CopyUsage;
  protected
    procedure Initialize; override;
    procedure Work(Thread: TSimpleThread); override;
  end;

  TProcessorMontiorImpl = TLinuxMonitor;

procedure TLinuxMonitor.Initialize;
var
  Data: TLinuxCoreData;
  S: string;
  I: Integer;
begin
  S := FileReadStr('/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq').Trim;
  FSpeed := StrToIntDef(S, 0) div 1000;
  S := FileReadStr('/proc/cpuinfo');
  for S in S.Split(#10) do
    if S.BeginsWith('model name') then
      FModel := S.SecondOf(': ' );
  I := -1;
  for S in FileReadStr('/proc/stat').Split(#10) do
    if S.BeginsWith('cpu') then
    begin
      if I > -1 then
      begin
        IdParse(S);
        Data.Idle := IdIdle + IdIowait;
        Data.Total := Data.Idle + IdUser + IdNice + IdSystem + IdIrq + IdSoftirq + IdSteal;
        FCoreData.Push(Data);
      end;
      Inc(I);
    end
    else
      Break;
  while I > 0 do
  begin
    FCores.Push(TProcessorCore.Create);
    Dec(I);
  end;
  FUsage.Length := FCores.Length;
end;

procedure TLinuxMonitor.CopyUsage;
var
  Core: TProcessorCore;
  T: Double;
  U: PProcessorUsage;
  I: Integer;
begin
  Inc(FTicks);
  T := TimeQuery;
  for I := 0 to FCores.Length - 1 do
  begin
    Core := FCores[I];
    Core.Next;
    U := @Core.FUsage.Items[Core.FIndex];
    U.Time := T;
    U.Utilization := FUsage[I].Utilization;
    U.Speed := FUsage[I].Speed;
  end;
end;

procedure TLinuxMonitor.Work(Thread: TSimpleThread);
var
  Data, Prev: TLinuxCoreData;
  Idled, Totaled: Int64;
  S: string;
  I: Integer;
begin
  I := -1;
  for S in FileReadStr('/proc/stat').Split(#10) do
    if S.BeginsWith('cpu') then
    begin
      if I > -1 then
      begin
        Prev := FCoreData[I];
        IdParse(S);
        Data.Idle := IdIdle + IdIowait;
        Data.Total := Data.Idle + IdUser + IdNice + IdSystem + IdIrq + IdSoftirq + IdSteal;
        Idled := Data.Idle - Prev.Idle;
        Totaled := Data.Total - Prev.Total;
        if Totaled < 1 then
          FUsage.Items[I].Utilization := 0
        else
          FUsage.Items[I].Utilization := (Totaled - Idled) / Totaled;
        FCoreData[I] := Data;
      end;
      Inc(I);
    end
    else
      Break;
  I := 0;
  for S in FileReadStr('/proc/cpuinfo').Split(#10) do
    if S.BeginsWith('cpu MHz') then
    begin
      FUsage.Items[I].Speed := StrToFloat(S.SecondOf(':').Trim);
      Inc(I);
      if I = FCores.Length then
        Break;
    end;
  Thread.Synchronize(CopyUsage);
end;
{$endif}

{ The global ProcessorMonitor object }

var
  InternalProcessorMonitor: TObject;

{ Usage for one hour oof data given a poll every 0.25 seconds }

const
  CoreUsageCount = 4 * 60 * 61;

{ TProcessorCore }

constructor TProcessorCore.Create;
begin
  inherited Create;
  FUsage.Length := CoreUsageCount;
  FIndex := -1;
end;

function TProcessorCore.Average(Index, Range: Integer; out Usage: TProcessorUsage): Boolean;
var
  U: PProcessorUsage;
  I, J: Integer;
begin
  Result := False;
  Usage.Speed := 0;
  Usage.Time := 0;
  Usage.Utilization := 0;
  if Range < 1 then
    Exit;
  if Index + Range > ProcessorMonitor.Ticks then
    Exit;
  for I := 0 to Range - 1 do
  begin
    J := Modulus(Index + I, CoreUsageCount);
    U := GetUsage(J);
    Usage.Utilization := Usage.Utilization + U.Utilization;
    Usage.Time := Usage.Time + U.Time;
    Usage.Speed := Usage.Speed + U.Speed;
  end;
  Usage.Utilization := Usage.Utilization / Range;
  Usage.Time := Usage.Time / Range;
  Usage.Speed := Usage.Speed / Range;
  Result := True;
end;

procedure TProcessorCore.Next;
begin
  FIndex := Modulus(FIndex + 1, CoreUsageCount);
end;

function TProcessorCore.GetUsage(Index: Integer): PProcessorUsage;
var
  I: Integer;
begin
  Result := nil;
  if Index < 0 then
    Exit;
  if Index > ProcessorMonitor.Ticks - 1 then
    Exit;
  I := Modulus(FIndex - Index, CoreUsageCount);
  Result := @FUsage.Items[I];
end;

{ TProcessorMonitor }

constructor TProcessorMonitor.Create;
begin
  inherited Create;
  Initialize;
end;

destructor TProcessorMonitor.Destroy;
var
  C: TProcessorCore;
begin
  Active := False;
  for C in FCores do
    C.Free;
  inherited Destroy;
end;

procedure TProcessorMonitor.Execute(Thread: TSimpleThread);
const
  Step = 250;
var
  A, B, C: Double;
begin
  A := TimeQuery;
  while not Thread.Terminated do
  begin
    Work(Thread);
    Sleep(10);
    B := TimeQuery;
    C := B - A;
    while C < Step / 1000 do
    begin
      Sleep(10);
      B := TimeQuery;
      C := B - A;
    end;
    A := B;
  end;
end;

procedure TProcessorMonitor.SetActive(Value: Boolean);
begin
  if Value = FActive then
    Exit;
  FTicks := 0;
  FActive := Value;
  if FActive then
    FThread := TSimpleThread.Create(Execute)
  else if FThread <> nil then
  begin
    FThread.Terminate;
    FThread := nil;
  end;
end;

function TProcessorMonitor.GetCore(Index: Integer): TProcessorCore;
begin
  Result := FCores[Index];
end;

function TProcessorMonitor.GetCoreCount: Integer;
begin
  Result := Length(FCores.Items);
end;

{ The global ProcessorMonitor function }

function ProcessorMonitor: TProcessorMonitor;
begin
  if InternalProcessorMonitor = nil then
    InternalProcessorMonitor := TProcessorMontiorImpl.Create;
  Result := TProcessorMonitor(InternalProcessorMonitor);
end;

initialization
  InternalProcessorMonitor := nil;
finalization
  InternalProcessorMonitor.Free;
end.

