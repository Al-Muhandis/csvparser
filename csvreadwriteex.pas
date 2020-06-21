{
  Based on CSV Parser from fcl-base
  ... ...
  CSV Parser, Builder classes.
  Version 0.5 2014-10-25

  Copyright (C) 2010-2014 Vladimir Zhirov <vvzh.home@gmail.com>

  Contributors:
    Luiz Americo Pereira Camara
    Mattias Gaertner
    Reinier Olislagers

  This library is free software; you can redistribute it and/or modify it
  under the terms of the GNU Library General Public License as published by
  the Free Software Foundation; either version 2 of the License, or (at your
  option) any later version with the following modification:

  As a special exception, the copyright holders of this library give you
  permission to link this library with independent modules to produce an
  executable, regardless of the license terms of these independent modules,and
  to copy and distribute the resulting executable under terms of your choice,
  provided that you also meet, for each linked independent module, the terms
  and conditions of the license of that module. An independent module is a
  module which is not derived from or based on this library. If you modify
  this library, you may extend this exception to your version of the library,
  but you are not obligated to do so. If you do not wish to do so, delete this
  exception statement from your version.

  This program is distributed in the hope that it will be useful, but WITHOUT
  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE. See the GNU Library General Public License
  for more details.

  You should have received a copy of the GNU Library General Public License
  along with this library; if not, write to the Free Software Foundation,
  Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
}

unit csvreadwriteex;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, csvreadwrite
  ;

type

  { TCSVParserEx }

  TCSVParserEx = class(TCSVHandler)
  private
    FFreeStream: Boolean;
    // fields
    FSourceStream: TStream;
    FStrStreamWrapper: TStringStream;
    FBOM: TCSVByteOrderMark;
    FDetectBOM: Boolean;
    // parser state
    EndOfFile: Boolean;
    EndOfLine: Boolean;
    FCurrentChar: TCSVChar;
    FCurrentRow: Integer;
    FCurrentCol: Integer;
    FMaxColCount: Integer;
    // output buffers
    FCellBuffer: String;
    FWhitespaceBuffer: String;
    procedure ClearOutput;
    function GetPosition: Int64;
    procedure SetPosition(AValue: Int64);
    // basic parsing
    procedure SkipEndOfLine;
    procedure SkipDelimiter;
    procedure SkipWhitespace;
    procedure NextChar;
    // complex parsing
    procedure ParseCell;
    procedure ParseCellJump;
    procedure ParseQuotedValue;
    // simple parsing
    procedure ParseValue;
  public
    constructor Create; override;
    destructor Destroy; override;
    // Source data stream
    procedure SetSource(AStream: TStream); overload;
    // Source data string.
    procedure SetSource(const AString: String); overload;
    // Rewind to beginning of data
    procedure ResetParser;
    // Read next cell data; return false if end of file reached
    function  ParseNextCell: Boolean;                       
    function  ParseNextCellJump: Boolean;
    // Must be called after the setting of raw stream position
    function JumpToEndOfLine: Boolean;
    // Current row (0 based)
    property CurrentRow: Integer read FCurrentRow;
    // Current column (0 based); -1 if invalid/before beginning of file
    property CurrentCol: Integer read FCurrentCol;
    // Data in current cell
    property CurrentCellText: String read FCellBuffer;
    // The maximum number of columns found in the stream:
    property MaxColCount: Integer read FMaxColCount;
    // Does the parser own the stream ? If true, a previous stream is freed when set or when parser is destroyed.
    Property FreeStream : Boolean Read FFreeStream Write FFreeStream;
    // Return BOM found in file
    property BOM: TCSVByteOrderMark read FBOM;
    // Detect whether a BOM marker is present. If set to True, then BOM can be used to see what BOM marker there was.
    property DetectBOM: Boolean read FDetectBOM write FDetectBOM default false;
    //  be careful while set the raw position
    property Position: Int64 read GetPosition write SetPosition;
  end;

implementation

uses StrUtils
  ;

const
  CsvCharSize = SizeOf(TCSVChar);
  CR    = #13;
  LF    = #10;
  HTAB  = #9;
  SPACE = #32;
  WhitespaceChars = [HTAB, SPACE];
  LineEndingChars = [CR, LF];


{ TCSVParserEx }

procedure TCSVParserEx.ClearOutput;
begin
  FCellBuffer := '';
  FWhitespaceBuffer := '';
  FCurrentRow := 0;
  FCurrentCol := -1;
  FMaxColCount := 0;
end;

function TCSVParserEx.GetPosition: Int64;
begin
  Result := FSourceStream.Position;
end;

procedure TCSVParserEx.SetPosition(AValue: Int64);
begin
  FSourceStream.Position:=AValue;
end;

procedure TCSVParserEx.SkipEndOfLine;
begin
  // treat LF+CR as two linebreaks, not one
  if (FCurrentChar = CR) then
    NextChar;
  if (FCurrentChar = LF) then
    NextChar;
end;

procedure TCSVParserEx.SkipDelimiter;
begin
  if FCurrentChar = FDelimiter then
    NextChar;
end;

procedure TCSVParserEx.SkipWhitespace;
begin
  while FCurrentChar = SPACE do
    NextChar;
end;

procedure TCSVParserEx.NextChar;
begin
  if FSourceStream.Read(FCurrentChar, CsvCharSize) < CsvCharSize then
  begin
    FCurrentChar := #0;
    EndOfFile := True;
  end;
  EndOfLine := FCurrentChar in LineEndingChars;
end;

procedure TCSVParserEx.ParseCell;
begin
  FCellBuffer := '';
  if FIgnoreOuterWhitespace then
    SkipWhitespace;
  if FCurrentChar = FQuoteChar then
    ParseQuotedValue
  else
    ParseValue;
end;

procedure TCSVParserEx.ParseCellJump;
begin
  FCellBuffer := '';
  if FIgnoreOuterWhitespace then
    SkipWhitespace;
  ParseValue;
end;

procedure TCSVParserEx.ParseQuotedValue;
var
  QuotationEnd: Boolean;
begin
  NextChar; // skip opening quotation char
  repeat
    // read value up to next quotation char
    while not ((FCurrentChar = FQuoteChar) or EndOfFile) do
    begin
      if EndOfLine then
      begin
        AppendStr(FCellBuffer, FLineEnding);
        SkipEndOfLine;
      end else
      begin
        AppendStr(FCellBuffer, FCurrentChar);
        NextChar;
      end;
    end;
    // skip quotation char (closing or escaping)
    if not EndOfFile then
      NextChar;
    // check if it was escaping
    if FCurrentChar = FQuoteChar then
    begin
      AppendStr(FCellBuffer, FCurrentChar);
      QuotationEnd := False;
      NextChar;
    end else
      QuotationEnd := True;
  until QuotationEnd;
  // read the rest of the value until separator or new line
  ParseValue;
end;

procedure TCSVParserEx.ParseValue;
begin
  while not ((FCurrentChar = FDelimiter) or EndOfLine or EndOfFile or (FCurrentChar = FQuoteChar)) do
  begin
    AppendStr(FCellBuffer, FCurrentChar);
    NextChar;
  end;
  if FCurrentChar = FQuoteChar then
    ParseQuotedValue;
  // merge whitespace buffer
  if FIgnoreOuterWhitespace then
    RemoveTrailingChars(FWhitespaceBuffer, WhitespaceChars);
  AppendStr(FWhitespaceBuffer,FCellBuffer);
  FWhitespaceBuffer := '';
end;

constructor TCSVParserEx.Create;
begin
  inherited Create;
  ClearOutput;
  FStrStreamWrapper := nil;
  EndOfFile := True;
end;

destructor TCSVParserEx.Destroy;
begin
  if FFreeStream and (FSourceStream<>FStrStreamWrapper) then
     FreeAndNil(FSourceStream);
  FreeAndNil(FStrStreamWrapper);
  inherited Destroy;
end;

procedure TCSVParserEx.SetSource(AStream: TStream);
begin
  If FSourceStream=AStream then exit;
  if FFreeStream and (FSourceStream<>FStrStreamWrapper) then
     FreeAndNil(FSourceStream);
  FSourceStream := AStream;
  ResetParser;
end;

procedure TCSVParserEx.SetSource(const AString: String); overload;
begin
  FreeAndNil(FStrStreamWrapper);
  FStrStreamWrapper := TStringStream.Create(AString);
  SetSource(FStrStreamWrapper);
end;

procedure TCSVParserEx.ResetParser;
var
  b: packed array[0..2] of byte;
  n: Integer;
begin
  B[0]:=0; B[1]:=0; B[2]:=0;
  ClearOutput;
  FSourceStream.Seek(0, soFromBeginning);
  if FDetectBOM then
  begin
    if FSourceStream.Read(b[0], 3)<3 then
      begin
      n:=0;
      FBOM:=bomNone;
      end
    else if (b[0] = $EF) and (b[1] = $BB) and (b[2] = $BF) then begin
      FBOM := bomUTF8;
      n := 3;
    end else
    if (b[0] = $FE) and (b[1] = $FF) then begin
      FBOM := bomUTF16BE;
      n := 2;
    end else
    if (b[0] = $FF) and (b[1] = $FE) then begin
      FBOM := bomUTF16LE;
      n := 2;
    end else begin
      FBOM := bomNone;
      n := 0;
    end;
    FSourceStream.Seek(n, soFromBeginning);
  end;
  EndOfFile := False;
  NextChar;
end;

// Parses next cell; returns True if there are more cells in the input stream.
function TCSVParserEx.ParseNextCell: Boolean;
var
  LineColCount: Integer;
begin
  if EndOfLine or EndOfFile then
  begin
    // Having read the previous line, adjust column count if necessary:
    LineColCount := FCurrentCol + 1;
    if LineColCount > FMaxColCount then
      FMaxColCount := LineColCount;
  end;

  if EndOfFile then
    Exit(False);

  // Handle line ending
  if EndOfLine then
  begin
    SkipEndOfLine;
    if EndOfFile then
      Exit(False);
    FCurrentCol := 0;
    Inc(FCurrentRow);
  end else
    Inc(FCurrentCol);

  // Skipping a delimiter should be immediately followed by parsing a cell
  // without checking for line break first, otherwise we miss last empty cell.
  // But 0th cell does not start with delimiter unlike other cells, so
  // the following check is required not to miss the first empty cell:
  if FCurrentCol > 0 then
    SkipDelimiter;
  ParseCell;
  Result := True;
end;

function TCSVParserEx.ParseNextCellJump: Boolean;
var
  LineColCount: Integer;
begin
  if EndOfLine or EndOfFile then
  begin
    // Having read the previous line, adjust column count if necessary:
    LineColCount := FCurrentCol + 1;
    if LineColCount > FMaxColCount then
      FMaxColCount := LineColCount;
  end;

  if EndOfFile then
    Exit(False);

  // Handle line ending
  if EndOfLine then
  begin
    SkipEndOfLine;
    if EndOfFile then
      Exit(False);
    FCurrentCol := 0;
    Inc(FCurrentRow);
  end else
    Inc(FCurrentCol);

  // Skipping a delimiter should be immediately followed by parsing a cell
  // without checking for line break first, otherwise we miss last empty cell.
  // But 0th cell does not start with delimiter unlike other cells, so
  // the following check is required not to miss the first empty cell:
  if FCurrentCol > 0 then
    SkipDelimiter;
  ParseCellJump;
  Result := True;
end;

function TCSVParserEx.JumpToEndOfLine: Boolean;
begin
  repeat
    if not ParseNextCell then
      Exit(False);
  until EndOfLine;
  Result:=True;
end;

end.

