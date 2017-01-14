unit ViBindings;

interface

uses
  Classes,
  ToolsAPI,
  Winapi.Windows;

type
  TDirection = (dForward, dBack);
  TBlockAction = (baDelete, baYank);
  TViRegister = record
    IsLine: Boolean;
    Text: String;
  end;

  TViAction = record
    ActionChar: Char;
    FInDelete, FInChange: Boolean;
    FEditCount, FCount: Integer;
    FInsertText: string;
  end;

  TViBindings = class(TObject)
  private
    FInsertMode: Boolean;
    FActive: Boolean;
    FParsingNumber: Boolean;
    FInDelete: Boolean;
    FInChange: Boolean;
    FInGo: Boolean;
    FInMark: Boolean;
    FInGotoMark: Boolean;
    FInRepeatChange: Boolean;
    FEditCount: Integer;
    FCount: Integer;
    FSelectedRegister: Integer;
    FPreviousAction: TViAction;
    FInsertText: String;
    FMarkArray: array[0..255] of TOTAEditPos;
    FRegisterArray: array[0..255] of TViRegister;
    FInYank: Boolean;
    FChar: Char;
    FShift: TShiftState;
    FEditPosition: IOTAEditPosition;
    FBuffer: IOTAEditBuffer;
    procedure ChangeIndentation(Direction: TDirection);
    function DeleteSelection: Boolean;
    function GetCount: Integer;
    function GetEditCount: Integer;
    procedure ResetCount;
    procedure UpdateCount;
    function GetPositionForMove(key: Char; count: Integer = 0): TOTAEditPos;
    procedure ProcessMovement;
    function IsMovementKey: Boolean;
    procedure MoveToMarkPosition;
    procedure Paste(const EditPosition: IOTAEditPosition; const Buffer: IOTAEditBuffer; Direction: TDirection);
    procedure SaveMarkPosition;
    procedure SetInsertMode(const Value: Boolean);
    function YankSelection: Boolean;
    procedure ApplyActionToBlock(Action: TBlockAction; IsLine: Boolean);
    procedure ProcessChar(const c: Char);
    procedure ProcessChange;
    procedure ProcessDeletion;
    procedure HandleKeyPress;
    procedure ProcessLineDeletion;
    procedure ProcessLineYanking;
    procedure ProcessYanking;
    procedure SavePreviousAction;
    procedure SwitchToInsertModeOrDoPreviousAction;
  public
    constructor Create;
    procedure EditKeyDown(Key, ScanCode: Word; Shift: TShiftState; Msg: TMsg; var Handled: Boolean);
    procedure EditChar(Key, ScanCode: Word; Shift: TShiftState; Msg: TMsg; var Handled: Boolean);
    procedure ConfigureCursor;
    property Count: Integer read GetCount;
    // Are we in insert mode?
    property InsertMode: Boolean read FInsertMode write SetInsertMode;
    // Are the vi bindings active?
    property Active: Boolean read FActive write FActive;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

function QuerySvcs(const Instance: IUnknown; const Intf: TGUID; out Inst): Boolean;
begin
  Result := (Instance <> nil) and Supports(Instance, Intf, Inst);
end;

function GetEditBuffer: IOTAEditBuffer;
var
  iEditorServices: IOTAEditorServices;
begin
  QuerySvcs(BorlandIDEServices, IOTAEditorServices, iEditorServices);
  if iEditorServices <> nil then
  begin
    Result := iEditorServices.GetTopBuffer;
    Exit;
  end;
  Result := nil;
end;

function GetTopMostEditView: IOTAEditView;
var
  iEditBuffer: IOTAEditBuffer;
begin
  iEditBuffer := GetEditBuffer;
  if iEditBuffer <> nil then
  begin
    Result := iEditBuffer.GetTopView;
    Exit;
  end;
  Result := nil;
end;

function GetEditPosition(Buffer: IOTAEditBuffer): IOTAEditPosition;
begin
  Result := nil;
  if Buffer <> nil then
    Result := Buffer.GetEditPosition;
end;

procedure TViBindings.ConfigureCursor;
var
  EditBuffer: IOTAEditBuffer;
begin
  EditBuffer := GetEditBuffer;
  if EditBuffer <> nil then
    EditBuffer.EditOptions.UseBriefCursorShapes := not FInsertMode;
end;

constructor TViBindings.Create;
begin
  Active := True;
  InsertMode := False;
end;

procedure TViBindings.EditChar(Key, ScanCode: Word; Shift: TShiftState; Msg: TMsg; var Handled: Boolean);
begin
  if not Active then
    Exit;

  if InsertMode then
    Exit;

  FShift := Shift;
  ProcessChar(Chr(Key));
  Handled := True;
  (BorlandIDEServices As IOTAEditorServices).TopView.Paint;
end;

procedure TViBindings.EditKeyDown(Key, ScanCode: Word; Shift: TShiftState; Msg: TMsg; var Handled: Boolean);
begin
  if not Active then Exit;

  if InsertMode then
  begin
    if (Key = VK_ESCAPE) then
    begin
      GetTopMostEditView.Buffer.BufferOptions.InsertMode := True;
      InsertMode := False;
      Handled := True;
      Self.FPreviousAction.FInsertText := FInsertText;
      FInsertText := '';
    end;
  end
  else
  begin
    if (((Key >= Ord('A')) and (Key <= Ord('Z'))) or
        ((Key >= Ord('0')) and (Key <= Ord('9'))) or
        ((Key >= 186) and (Key <= 192)) or
        ((Key >= 219) and (Key <= 222))) and
        not ((ssCtrl in Shift) or (ssAlt in Shift)) and
        not InsertMode then
    begin
      // If the keydown is a standard keyboard press not altered with a ctrl or alt key
      // then create a WM_CHAR message so we can do all the locale mapping of the keyboard
      // and then handle the resulting key in TViBindings.EditChar
      // XXX can we switch to using ToAscii like we do for setting FInsertText
      TranslateMessage(Msg);
      Handled := True;
    end;
  end;
end;

function TViBindings.IsMovementKey: Boolean;
begin
  if (FChar = '0') and FParsingNumber then
    Result:= False
  else
    Result := CharInSet(FChar, ['0', '$', 'b', 'B', 'e', 'E', 'h', 'j', 'k', 'l', 'w', 'W']);
end;

procedure TViBindings.ResetCount;
begin
  FCount := 0;
  FParsingNumber := False;
end;

procedure TViBindings.UpdateCount;
begin
  FParsingNumber := True;
  if CharInSet(FChar, ['0'..'9']) then
    FCount := 10 * FCount + (Ord(FChar) - Ord('0'));
end;

type TViCharClass = (viWhiteSpace, viWord, viSpecial);

procedure TViBindings.ApplyActionToBlock(Action: TBlockAction; IsLine: Boolean);
var
  Count: Integer;
  Pos: TOTAEditPos;
  EditBlock: IOTAEditBlock;
begin
  Count := GetCount * GetEditCount;
  ResetCount;
  Pos := GetPositionForMove(FChar, Count);
  if CharInSet(FChar, ['e', 'E']) then Pos.Col := Pos.Col + 1;

  EditBlock := FBuffer.EditBlock;
  EditBlock.Reset;
  EditBlock.BeginBlock;
  EditBlock.Extend(Pos.Line, Pos.Col);
  FRegisterArray[FSelectedRegister].IsLine := IsLine;
  FRegisterArray[FSelectedRegister].Text := EditBlock.Text;

  case Action of
    baDelete:
      EditBlock.Delete;
    baYank:
      EditBlock.Reset;
  end;

  EditBlock.EndBlock;
end;

procedure TViBindings.ChangeIndentation(Direction: TDirection);
var
  EditBlock: IOTAEditBlock;
  StartedBlock: Boolean;
begin
  StartedBlock := False;
  EditBlock := FBuffer.EditBlock;
  EditBlock.Save;
  FEditPosition.Save;

  if EditBlock.Size = 0 then
  begin
    StartedBlock := True;
    FEditPosition.MoveBOL;
    EditBlock.Reset;
    EditBlock.BeginBlock;
    EditBlock.Extend(FEditPosition.Row, FEditPosition.Column + 1);
  end
  else
  begin
    // When selecting multiple lines, if the cursor is in the first column the last line doesn't get into the block
    // and the indent seems buggy, as the cursor is on the last line but it isn't indented, so we force
    // the selection of at least one char to correct this behavior
    EditBlock.ExtendRelative(0, 1);
  end;

  case Direction of
    dForward:
      EditBlock.Indent(FBuffer.EditOptions.BlockIndent);
    dBack:
      EditBlock.Indent(-FBuffer.EditOptions.BlockIndent);
  end;

  // If we don't call EndBlock, the selection gets buggy.
  if StartedBlock then
    EditBlock.EndBlock;

  FEditPosition.Restore;
  EditBlock.Restore;
end;

function TViBindings.DeleteSelection: Boolean;
var
  EditBlock: IOTAEditBlock;
begin
  EditBlock := FBuffer.EditBlock;
  if EditBlock.Size = 0 then
    Exit(False);

  FRegisterArray[FSelectedRegister].IsLine := False;
  FRegisterArray[FSelectedRegister].Text := EditBlock.Text;
  EditBlock.Delete;
  Result := True;
end;

// Given a movement key and a count return the position in the buffer where that movement would take you.
// TOTAEditPos
function TViBindings.GetCount: Integer;
begin
  if (FCount <= 0) then
    Result := 1
  else
    Result := FCount;
end;

function TViBindings.GetEditCount: Integer;
begin
  Result := IfThen(FEditCount > 0, FEditCount, 1);
end;

function TViBindings.GetPositionForMove(key: Char; count: Integer = 0): TOTAEditPos;
var
  Pos: TOTAEditPos;
  i: Integer;
  nextChar: TViCharClass;

  function CharAtRelativeLocation(col: Integer): TViCharClass;
  begin
    FEditPosition.Save;
    FEditPosition.MoveRelative(0, col);
    if FEditPosition.IsWhiteSpace or (FEditPosition.Character = #$D) then
    begin
      Result := viWhiteSpace
    end
    else if FEditPosition.IsWordCharacter then
    begin
      Result := viWord;
    end
    else
    begin
      Result := viSpecial;
    end;
    FEditPosition.Restore;
  end;
begin
  FEditPosition.Save;

  case Key of
    '0':
      begin
        FEditPosition.MoveBOL;
      end;
    '$':
      begin
        FEditPosition.MoveEOL;
        // When moving around, must stop at last char, not on line break.
        if (not FInDelete) and (not FInChange) and (not FInYank) then
          FEditPosition.MoveRelative(0, -1);
      end;
    'b':
      begin
        for i := 1 to count do
        begin
          nextChar := CharAtRelativeLocation(-1);
          if FEditPosition.IsWordCharacter and ((nextChar = viSpecial) or (nextChar = viWhiteSpace)) then
            FEditPosition.MoveRelative(0, -1);

          if FEditPosition.IsSpecialCharacter and ((nextChar = viWord) or (nextChar = viWhiteSpace)) then
            FEditPosition.MoveRelative(0, -1);

          if FEditPosition.IsWhiteSpace then
          begin
            FEditPosition.MoveCursor(mmSkipWhite or mmSkipLeft or mmSkipStream);
            FEditPosition.MoveRelative(0, -1);
          end;

          if FEditPosition.IsWordCharacter then
          begin
            // Skip to first non word character.
            FEditPosition.MoveCursor(mmSkipWord or mmSkipLeft);
          end
          else if FEditPosition.IsSpecialCharacter then
          begin
            // Skip to the first non special character
            FEditPosition.MoveCursor(mmSkipSpecial or mmSkipLeft);
          end;
        end;
      end;
    'B':
      begin
        for i := 1 to count do
        begin
          FEditPosition.MoveCursor(mmSkipWhite or mmSkipLeft or mmSkipStream);
          FEditPosition.MoveCursor(mmSkipNonWhite or mmSkipLeft);
        end;
      end;
    'e':
      begin
        for i := 1 to count do
        begin
          nextChar := CharAtRelativeLocation(1);
          if (FEditPosition.IsWordCharacter and (nextChar = viWhiteSpace) or (nextChar = viSpecial)) then
            FEditPosition.MoveRelative(0, 1);

          if (FEditPosition.IsSpecialCharacter and (nextChar = viWhiteSpace) or (nextChar = viWord)) then
            FEditPosition.MoveRelative(0, 1);

          if FEditPosition.IsWhiteSpace then
            FEditPosition.MoveCursor(mmSkipWhite or mmSkipRight or mmSkipStream);

          if FEditPosition.IsSpecialCharacter then
            FEditPosition.MoveCursor(mmSkipSpecial or mmSkipRight);

          if FEditPosition.IsWordCharacter then
            FEditPosition.MoveCursor(mmSkipWord or mmSkipRight);

          FEditPosition.MoveRelative(0, -1);
        end;
      end;
    'E':
      begin
        for i := 1 to count do
        begin
          if (FEditPosition.IsWordCharacter or FEditPosition.IsSpecialCharacter) and (CharAtRelativeLocation(1) = viWhiteSpace) then
            FEditPosition.MoveRelative(0, 1);

          if FEditPosition.IsWhiteSpace then
            FEditPosition.MoveCursor(mmSkipWhite or mmSkipRight or mmSkipStream);

          FEditPosition.MoveCursor(mmSkipNonWhite or mmSkipRight);
          FEditPosition.MoveRelative(0, -1);
        end;
      end;
    'h':
      begin
        FEditPosition.MoveRelative(0, -count);
      end;
    'j':
      begin
        FEditPosition.MoveRelative(+count, 0);
      end;
    'k':
      begin
        FEditPosition.MoveRelative(-count, 0);
      end;
    'l':
      begin
        FEditPosition.MoveRelative(0, +count);
      end;
    'w':
      begin
        for i := 1 to count do
        begin
          if FEditPosition.IsWordCharacter then
          begin
            // Skip to first non word character.
            FEditPosition.MoveCursor(mmSkipWord or mmSkipRight);
          end
          else if FEditPosition.IsSpecialCharacter then
          begin
            // Skip to the first non special character
            FEditPosition.MoveCursor(mmSkipSpecial or mmSkipRight or mmSkipStream);
          end;

          // If the character is whitespace or EOL then skip that whitespace
          if FEditPosition.IsWhiteSpace or (FEditPosition.Character = #$D) then
          begin
            FEditPosition.MoveCursor(mmSkipWhite or mmSkipRight or mmSkipStream);
          end;
        end;
      end;
    'W':
      begin
        for i := 1 to count do
        begin
          // Goto first white space after the end of the word.
          FEditPosition.MoveCursor(mmSkipNonWhite or mmSkipRight);
          // Now skip all the white space until we're at the start of a word again.
          FEditPosition.MoveCursor(mmSkipWhite or mmSkipRight or mmSkipStream);
        end;
      end;
  end;

  Pos.Col := FEditPosition.Column;
  Pos.Line := FEditPosition.Row;
  FEditPosition.Restore;

  Result := Pos;
end;

procedure TViBindings.ProcessChar(const c: Char);
begin
  FChar := c;
  FBuffer := GetEditBuffer;
  FEditPosition := GetEditPosition(FBuffer);
  try
    if FInMark then
      SaveMarkPosition
    else if FInGotoMark then
      MoveToMarkPosition
    else if IsMovementKey then
      ProcessMovement
    else if CharInSet(FChar, ['0'..'9']) then
      UpdateCount
    else if (FInDelete and (FChar = 'd')) then
      ProcessLineDeletion
    else if FInYank and (FChar = 'y') then
      ProcessLineYanking
    else
      HandleKeyPress;
  finally
    // Avoid dangling reference error when closing the IDE
    FBuffer := nil;
    FEditPosition := nil;
  end;
end;

procedure TViBindings.ProcessChange;
begin
  if FInRepeatChange then
  begin
    ApplyActionToBlock(baDelete, False);
    FEditPosition.InsertText(FPreviousAction.FInsertText)
  end
  else
  begin
    if (FChar = 'w') then FChar := 'e';
    if (FChar = 'W') then FChar := 'E';
    SavePreviousAction;
    ApplyActionToBlock(baDelete, False);
    InsertMode := True;
  end;
  FInChange := False;
end;

procedure TViBindings.ProcessDeletion;
begin
  if not FInRepeatChange then
    SavePreviousAction;

  ApplyActionToBlock(baDelete, False);
  FInDelete := False;
end;

procedure TViBindings.HandleKeyPress;
var
  EditBlock: IOTAEditBlock;
  View: IOTAEditView;
  Pos: TOTAEditPos;
  count: Integer;
  i: Integer;
begin
  count := GetCount;
  case FChar of
  'a':
    begin
      FEditPosition.MoveRelative(0, 1);
      SwitchToInsertModeOrDoPreviousAction;
    end;
  'A':
    begin
      FEditPosition.MoveEOL;
      SwitchToInsertModeOrDoPreviousAction;
    end;
  'c':
    begin
      if FInChange then
      begin
        FEditPosition.MoveBOL;
        ProcessChar('$');
      end
      else
      begin
        if DeleteSelection then
          SwitchToInsertModeOrDoPreviousAction
        else
        begin
          FInChange := True;
          FEditCount := count;
        end
      end;
    end;
  'C':
    begin
      FInChange := True;
      FEditCount := count;
      ProcessChar('$');
    end;
  'd':
    begin
      if not DeleteSelection then
      begin
        FInDelete := True;
        FEditCount := count;
      end;
    end;
  'D':
    begin
      FInDelete := True;
      ProcessChar('$');
    end;
  'g':
    begin
      if FInGo then
      begin
        FEditPosition.Move(1, 1);
        FInGo := False;
      end
      else
      begin
        FInGo := True;
        FEditCount := count;
     end
    end;
  'G':
    begin
      if FParsingNumber then
        FEditPosition.GotoLine(FCount)
      else
        FEditPosition.MoveEOF;
    end;
  'H':
    begin
      FEditPosition.Move(FBuffer.TopView.TopRow, 0);
      FEditPosition.MoveBOL;
    end;
  'i':
    begin
      SwitchToInsertModeOrDoPreviousAction;
    end;
  'I':
    begin
      FEditPosition.MoveBOL;
      SwitchToInsertModeOrDoPreviousAction;
    end;
  'J':
    begin
      FEditPosition.MoveEOL;
      FEditPosition.Delete(1);
    end;
  'L':
    begin
      FEditPosition.Move(GetTopMostEditView.BottomRow -1, 0);
      FEditPosition.MoveBOL;
    end;
  'm':
    begin
      FInMark := true;
    end;
  'M':
    begin
      View := GetTopMostEditView;
      FEditPosition.Move(View.TopRow + Trunc(((View.BottomRow -1) - View.TopRow)/2), 0);
      FEditPosition.MoveBOL;
    end;
  'n':
    begin
      EditBlock := FBuffer.EditBlock;
      EditBlock.Reset;
      EditBlock.BeginBlock;
      EditBlock.ExtendRelative(0, Length(FEditPosition.SearchOptions.SearchText));
      if AnsiSameText(FEditPosition.SearchOptions.SearchText, EditBlock.Text) then
        FEditPosition.MoveRelative(0, Length(FEditPosition.SearchOptions.SearchText));
      EditBlock.EndBlock;

      FEditPosition.SearchOptions.Direction := sdForward;

      for i := 1 to count do
        FEditPosition.SearchAgain;

      FEditPosition.MoveRelative(0, -Length(FEditPosition.SearchOptions.SearchText));
    end;
  'N':
    begin
      FEditPosition.SearchOptions.Direction := sdBackward;

      for i := 1 to count do
        FEditPosition.SearchAgain;
    end;
  'o':
    begin
      FEditPosition.MoveEOL;
      FEditPosition.InsertText(#13#10);
      SwitchToInsertModeOrDoPreviousAction;
      (BorlandIDEServices As IOTAEditorServices).TopView.MoveViewToCursor;
    end;
  'O':
    begin
      FEditPosition.MoveBOL;
      FEditPosition.InsertText(#13#10);
      FEditPosition.MoveCursor(mmSkipWhite or mmSkipRight);
      FEditPosition.MoveRelative(-1, 0);
      SwitchToInsertModeOrDoPreviousAction;
      (BorlandIDEServices As IOTAEditorServices).TopView.MoveViewToCursor;
    end;
  'p':
    begin
      SavePreviousAction;
      Paste(FEditPosition, FBuffer, dForward);
    end;
  'P':
    begin
      SavePreviousAction;
      Paste(FEditPosition, FBuffer, dBack);
    end;
  'R':
    begin
      // XXX Fix me for '.' command
      FBuffer.BufferOptions.InsertMode := False;
      InsertMode := True;
    end;
  's':
    begin
      if not DeleteSelection then
        FEditPosition.Delete(1);
      SwitchToInsertModeOrDoPreviousAction;
    end;
  'S':
    begin
      FInChange := True;
      FEditPosition.MoveBOL;
      ProcessChar('$');
    end;
  'u':
    begin
      GetEditBuffer.Undo;
    end;
  'x':
    begin
      if not DeleteSelection then
      begin
        FInDelete := True;
        FEditCount := count - 1;
        ProcessChar('l');
      end;
    end;
  'X':
    begin
      FInDelete := True;
      if DeleteSelection then
        ProcessChar('d')
      else
      begin
        FEditCount := count - 1;
        ProcessChar('h');
      end
    end;
  'y':
    begin
      FInYank := not YankSelection;
      if FInYank then
        FEditCount := count;
    end;
  'Y':
    begin
      FInYank := True;
      FEditCount := count;
      ProcessChar('y');
    end;
  '.':
    begin
      FInRepeatChange := True;
      FInDelete := FPreviousAction.FInDelete;
      FInChange := FPreviousAction.FInChange;
      FEditCount := FPreviousAction.FEditCount;
      FCount := FPreviousAction.FCount;
      ProcessChar(FPreviousAction.ActionChar);
      FInRepeatChange := False;
    end;
  '*':
    begin
      if FEditPosition.IsWordCharacter then
        FEditPosition.MoveCursor(mmSkipWord or mmSkipLeft)
      else
        FEditPosition.MoveCursor(mmSkipNonWord or mmSkipRight or mmSkipStream);

      Pos := GetPositionForMove('e', 1);

      EditBlock := FBuffer.EditBlock;
      EditBlock.Reset;
      EditBlock.BeginBlock;
      EditBlock.Extend(Pos.Line, Pos.Col + 1);
      FEditPosition.SearchOptions.SearchText := EditBlock.Text;
      EditBlock.EndBlock;

      // Move to one position after what we're searching for.
      FEditPosition.Move(Pos.Line, Pos.Col+1);

      FEditPosition.SearchOptions.CaseSensitive := False;
      FEditPosition.SearchOptions.Direction := sdForward;
      FEditPosition.SearchOptions.FromCursor := True;
      FEditPosition.SearchOptions.RegularExpression := False;
      FEditPosition.SearchOptions.WholeFile := True;
      FEditPosition.SearchOptions.WordBoundary := True;

      for i := 1 to count do
        FEditPosition.SearchAgain;

      // Move back to the start of the text we searched for.
      FEditPosition.MoveRelative(0, -Length(FEditPosition.SearchOptions.SearchText));

      (BorlandIDEServices As IOTAEditorServices).TopView.MoveViewToCursor;
    end;
  '''':
    begin
      FInGotoMark := True;
    end;
  '^':
    begin
      FEditPosition.MoveBOL;
      FEditPosition.MoveCursor(mmSkipWhite);
    end;
  '>':
    begin
      SavePreviousAction;
      ChangeIndentation(dForward);
    end;
  '<':
    begin
      SavePreviousAction;
      ChangeIndentation(dBack);
    end;
  end;
  ResetCount;
end;

procedure TViBindings.ProcessLineDeletion;
begin
  if not FInRepeatChange then
    SavePreviousAction;

  FEditPosition.MoveBOL;
  FChar := 'j';
  ApplyActionToBlock(baDelete, True);
  FInDelete := False;
end;

procedure TViBindings.ProcessLineYanking;
begin
  FEditPosition.Save;
  FEditPosition.MoveBOL;
  FChar := 'j';
  ApplyActionToBlock(baYank, True);
  FEditPosition.Restore;
  FInYank := False;
end;

procedure TViBindings.ProcessMovement;
var
  Pos: TOTAEditPos;
begin
  if FInDelete then
    ProcessDeletion
  else if FInChange then
    ProcessChange
  else if FInYank then
    ProcessYanking
  else
  begin
    Pos := GetPositionForMove(FChar, GetCount);
    FEditPosition.Move(Pos.Line, Pos.Col);
  end;
  ResetCount;
end;

procedure TViBindings.ProcessYanking;
begin
  FEditPosition.Save;
  ApplyActionToBlock(baYank, False);
  FEditPosition.Restore;
  FInYank := False;
end;

procedure TViBindings.MoveToMarkPosition;
begin
  FEditPosition.Move(FMarkArray[Ord(FChar)].Line, FMarkArray[Ord(FChar)].Col);
  FInGotoMark := False;
end;

procedure TViBindings.Paste(const EditPosition: IOTAEditPosition; const Buffer: IOTAEditBuffer; Direction: TDirection);
var
  AutoIdent, PastingInSelection: Boolean;
  EditBlock: IOTAEditBlock;
  Row, Col: Integer;

  function FixCursorPosition: Boolean;
  begin
    Result := (not PastingInSelection) and (Direction = dForward);
  end;

begin
  PastingInSelection := False;
  AutoIdent := Buffer.BufferOptions.AutoIndent;

  EditBlock := GetTopMostEditView.Block;
  if EditBlock.Size > 0 then
  begin
    PastingInSelection := True;
    Row := EditBlock.StartingRow;
    Col := EditBlock.StartingColumn;
    EditBlock.Delete;
    EditPosition.Move(Row, Col);
  end;

  if (FRegisterArray[FSelectedRegister].IsLine) then
  begin
    Buffer.BufferOptions.AutoIndent := False;
    EditPosition.MoveBOL;

    if FixCursorPosition then
      EditPosition.MoveRelative(1, 0);

    EditPosition.Save;
    EditPosition.InsertText(FRegisterArray[FSelectedRegister].Text);
    EditPosition.Restore;
    Buffer.BufferOptions.AutoIndent := AutoIdent;
  end
  else
  begin
    if FixCursorPosition then
      EditPosition.MoveRelative(0, 1);

    EditPosition.InsertText(FRegisterArray[FSelectedRegister].Text);
  end;
end;

procedure TViBindings.SaveMarkPosition;
begin
  FMarkArray[Ord(FChar)].Col := FEditPosition.Column;
  FMarkArray[Ord(FChar)].Line := FEditPosition.Row;
  FInMark := False;
end;

procedure TViBindings.SavePreviousAction;
begin
  // TODO: Save the new actions
 FPreviousAction.ActionChar := FChar;
 FPreviousAction.FInDelete := FInDelete;
 FPreviousAction.FInChange := FInChange;
 FPreviousAction.FEditCount := FEditCount;
 FPreviousAction.FCount := FCount;
  // self.FPreviousAction.FInsertText := FInsertText;
end;

procedure TViBindings.SetInsertMode(const Value: Boolean);
begin
  FInsertMode := Value;
  ConfigureCursor;
end;

procedure TViBindings.SwitchToInsertModeOrDoPreviousAction;
begin
  if (FInRepeatChange) then
    FEditPosition.InsertText(FPreviousAction.FInsertText)
  else
  begin
    SavePreviousAction;
    InsertMode := True;
  end;
end;

function TViBindings.YankSelection: Boolean;
var
  EditBlock: IOTAEditBlock;
begin
  EditBlock := GetTopMostEditView.Block;
  if EditBlock.Size = 0 then
    Exit(False);

  FRegisterArray[FSelectedRegister].IsLine := False;
  FRegisterArray[FSelectedRegister].Text := EditBlock.Text;
  EditBlock.Reset;
  Result := True;
end;

end.
