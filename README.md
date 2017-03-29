vide
====

VI for Delphi IDE

This package provides a very minimal set of key bindings to allow one to do some vi actions inside the delphi editor.

## Supported commands and motions


### Cursor movement

| Command | Description | Status |
|----|----|----|
| h | move cursor left | implemented |
| j | move cursor down | implemented |
| k | move cursor up| implemented |
| l | move cursor right| implemented |
| H | move to top of screen| implemented |
| M | move to middle of screen| implemented |
| L | move to bottom of screen| implemented |
| w | jump forwards to the start of a word| implemented |
| W | jump forwards to the start of a word (words can contain punctuation)| implemented |
| e | jump forwards to the end of a word| implemented |
| E | jump forwards to the end of a word (words can contain punctuation)| implemented |
| b | jump backwards to the start of a word| implemented |
| B | jump backwards to the start of a word (words can contain punctuation)| implemented |
| 0 | jump to the start of the line| implemented |
| ^ | jump to the first non-blank character of the line | planned |
| $ | jump to the end of the line| implemented |
| g_ | jump to the last non-blank character of the line | planned |
| gg | go to the first line of the document| implemented |
| G | go to the last line of the document| implemented |
| 5G | go to line 5| implemented |
| fx | jump to next occurrence of character x | planned |
| tx | jump to before next occurrence of character x | planned |
| } | jump to next paragraph (or function/block, when editing code) | planned |
| { | jump to previous paragraph (or function/block, when editing code) | planned |
| % | find closing block | planned (maybe for begin/end too) |
| Ctrl + b | move back one full screen | conflicting |
| Ctrl + f | move forward one full screen | conflicting |
| Ctrl + d | move forward 1/2 a screen | conflicting |
| Ctrl + u | move back 1/2 a screen | conflicting |

### Searching

| Command | Description | Status |
|----|----|----|
| * | search forward word at cursor | implemented |
| n | move cursor forward after search | implemented |
| N | move cursor backwards after search | implemented |

### Insert mode - inserting/appending text

| Command | Description | Status |
|----|----|----|
i | insert before the cursor| implemented |
I | insert at the beginning of the line| implemented |
a | insert (append) after the cursor| implemented |
A | insert (append) at the end of the line| implemented |
o | append (open) a new line below the current line| implemented |
O | append (open) a new line above the current line| implemented |
Esc | exit insert mode| implemented |

### Editing

| Command | Description | Status |
|----|----|----|
r | replace a single character | planned |
J | join line below to the current one | implemented |
cc | change (replace) entire line | implemented |
cw | change (replace) to the end of the word | implemented |
c$ | change (replace) to the end of the lin e| implemented |
s | delete character and substitute text | implemented |
S | delete line and substitute text (same as cc) | implemented |
xp | transpose two letters (delete and paste) | implemented |
u | undo| implemented |
Ctrl + r | redo | conflicting |
\> | Indent | implemented |
\< | Unindent | implemented |
~ | Switch case | planned |
gu | Changed case to lowercase | planned |
gU | Change case to uppercase | planned |
. | repeat last command | needs testing |

### Copy, Cut and paste

| Command | Description | Status |
|----|----|----|
| yy | yank (copy) a line| implemented |
| Y | yank (copy) a line| implemented |
| 2yy | yank (copy) 2 lines| implemented |
| yw | yank (copy) the characters of the word from the cursor position to the start of the next word| implemented |
| Y$ | yank (copy) to end of line| implemented |
| P | put (paste) the clipboard after cursor| implemented |
| P | put (paste) before cursor| implemented |
| dd | delete (cut) a line| implemented |
| 2dd | delete (cut) 2 lines| implemented |
| Dw | delete (cut) the characters of the word from the cursor position to the start of the next word| implemented |
| D | delete (cut) to the end of the line| implemented |
| d$ | delete (cut) to the end of the line| implemented |
| x | delete (cut) character left of the cursor| implemented |
| X | delete (cut) character left of the cursor| implemented |

### Marking text (visual mode)

| Command | Description | Status |
|----|----|----|
| v | start visual mode, mark lines, then do a command (like y-yank) | maybe |
| V | start linewise visual mode | maybe |
| Ctrl + v | start visual block mode | maybe |

**conflicting** means that the shortcut conflicts with some Delphi builtin command, still didn't think of a solution, maybe override when on normal mode.

Installation
============

- Open the relevant .dproj file for your version of Delphi.
- Select "Release"
- Build the project
- Copy the resulting DLL to your selected install location, eg C:\location
- Set the registry entry [HKEY_CURRENT_USER\Software\Embarcadero\BDS\9.0\Experts] to VIDE_XE2="C:\location\VIDE_XE2.dll"

Debugging
==========

- Open the relevant .dproj file for your version of Delphi.
- Select "Release"
- Build the project
- Select Run Parameters and set the Host Application to be the IDE.
- Set the registry entry [HKEY_CURRENT_USER\Software\Embarcadero\BDS\9.0\Experts] to VIDE_XE2="C:\location_of_debug_dll\VIDE_XE2.dll"
- Start Debugging

DON'T FORGET AFTERWARDS TO RESET THE REGISTRY ENTRY TO THE INSTALLED VERSION OF THE DLL.

Updating to a new version of Delphi
===================================

- Create a DLL project and name it VIDE_DELPHIVER.dll
- Edit runtime packages and add designide
- Check Link runtime packages
