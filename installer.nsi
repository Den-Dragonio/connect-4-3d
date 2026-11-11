; NSIS Installer Script for Connect 4 — 3D
; Supports Windows 7, Windows 8, Windows 8.1, Windows 10, and Windows 11 (both 32-bit and 64-bit)

Unicode true
Name "Connect 4 — 3D"
OutFile "dist/Connect4_3D_Setup.exe"
InstallDir "$LOCALAPPDATA\Connect4_3D"
RequestExecutionLevel user
SetCompressor /SOLID lzma

Page directory
Page instfiles

UninstPage uninstConfirm
UninstPage instfiles

Section "Install Connect 4 — 3D"
  SetOutPath "$INSTDIR"

  ; Copy universal Windows 7/8/10/11 game executable and required SDL2/OpenGL/LuaJIT DLLs
  File /r ".build_cache\win_universal\*.*"

  ; Create Uninstaller
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  ; Create Start Menu & Desktop Shortcuts
  CreateDirectory "$SMPROGRAMS\Connect 4 — 3D"
  CreateShortcut "$SMPROGRAMS\Connect 4 — 3D\Connect 4 — 3D.lnk" "$INSTDIR\Connect4_3D.exe"
  CreateShortcut "$SMPROGRAMS\Connect 4 — 3D\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortcut "$DESKTOP\Connect 4 — 3D.lnk" "$INSTDIR\Connect4_3D.exe"
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\Connect 4 — 3D.lnk"
  Delete "$SMPROGRAMS\Connect 4 — 3D\Connect 4 — 3D.lnk"
  Delete "$SMPROGRAMS\Connect 4 — 3D\Uninstall.lnk"
  RMDir "$SMPROGRAMS\Connect 4 — 3D"
  RMDir /r "$INSTDIR"
SectionEnd

