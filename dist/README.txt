=====================================
 OSPlus - Omega Strikers Mod Platform
=====================================

OSPlus is a community mod platform for Omega Strikers. This package includes
in-match text chat shared between OSPlus users in the same match. When a newer
stable OSPlus release is available, the Home Hub also shows a small,
non-blocking update notice above the Competitive selector.


INSTALL - WINDOWS
-----------------

  1. Extract this zip somewhere (e.g. your Desktop)
  2. Double-click install.bat
  3. Done!

The installer auto-detects your Steam install of Omega Strikers and
deploys everything you need (UE4SS + the mod). If auto-detection fails,
it'll ask you to paste your game path.

If you already have UE4SS installed, the installer leaves it alone and
just adds OSPlus on top.

If you have an older "OmegaStrikersTest" install from a previous build,
this installer migrates it automatically.


INSTALL - LINUX / STEAM DECK
----------------------------

  1. Extract this zip somewhere
  2. Open a terminal in the extracted folder
  3. Run:

       bash install.sh

The Linux installer auto-detects normal Steam and Flatpak Steam library
locations, then installs the same UE4SS + OSPlus files into the Proton
game folder. If auto-detection fails, it asks for the OmegaStrikers path.

After installing, set this Steam Launch Option for Omega Strikers:

  WINEDLLOVERRIDES="dwmapi=n,b" %command%

This tells Proton to load OSPlus's local dwmapi.dll proxy so UE4SS starts,
instead of using Wine's builtin dwmapi implementation.

Omega Strikers runs as a Windows game under Proton, so OSPlus currently
launches the Windows sidecar inside that same compatibility layer. This
keeps the file-IPC path shared with the Lua mod. A native Linux sidecar is
a separate future packaging step, not required for this installer path.


USAGE
-----

  1. Launch Omega Strikers normally (from Steam)
  2. Join a match
  3. Press ENTER to open the chat box
  4. Press TAB or SHIFT+TAB to change who will receive the message
  5. Type your message and press ENTER to send
  6. Press ESCAPE, or click outside chat, to close without sending

Players can choose Team or All. Spectators can choose All, Team 1, or Team 2.
The expanded chat shows which players are currently connected to OSPlus.

Chat only appears during matches. The sidecar (relay client) starts
automatically with the game and shuts down when you close the game.


CONFIG
------

OSPlus ships pointing at the public OSPlus relay:

  wss://play-osplus.duckdns.org

You don't need to change anything to chat with other OSPlus users.

If you want to run your own relay (closed group, LAN, dev), edit:

  <game>\Binaries\Win64\Mods\OSPlus\sidecar\config.json

  {
    "relay_url": "wss://your-server.example.com",
    "update_url": "https://your-server.example.com/updates/latest"
  }

If update_url is omitted, OSPlus derives it from relay_url automatically.
Use wss:// (TLS) for anything reachable over the internet. ws:// is
fine for localhost / LAN testing only.


TROUBLESHOOTING
---------------

Chat not appearing?
  - Re-run install.bat or bash install.sh (make sure it says
    "Installation complete!")
  - On Linux/Steam Deck, confirm the launch option is set:
      WINEDLLOVERRIDES="dwmapi=n,b" %command%
  - Check that OSPlus is listed in:
      <game>\Binaries\Win64\Mods\mods.txt   with " : 1" at the end
  - Restart the game

Game won't launch / crashes on startup?
  - Some antivirus software flags UE4SS.dll. Add Win64\ to your exclusions.
  - Make sure Visual C++ Redistributable 2015-2022 (x64) is installed:
      https://aka.ms/vs/17/release/vc_redist.x64.exe

Messages not sending?
  - Check that config.json has the correct relay server address
  - Make sure the relay server is reachable
  - Check your firewall isn't blocking OSPlus.exe
  - On Linux/Steam Deck, check the Proton prefix logs under:
      <steam-library>/steamapps/compatdata/<appid>/pfx/drive_c/users/steamuser/AppData/Local/OSPlus


UNINSTALL
---------

Windows:

  Double-click uninstall.bat

Linux / Steam Deck:

  From the extracted folder, run:

    bash uninstall.sh

The uninstaller removes OSPlus files, removes the "OSPlus : 1" mods.txt
entry, and stops the sidecar if it is running. It asks before removing
UE4SS, because another mod may be using the same UE4SS install. It also
asks before deleting local OSPlus logs/config/token.

Manual uninstall is still:
  1. Delete: <game>\Binaries\Win64\Mods\OSPlus\
  2. Delete: <game>\OmegaStrikers\Content\Paks\LogicMods\OSPlus.pak
  3. Remove the "OSPlus : 1" line from:
     <game>\Binaries\Win64\Mods\mods.txt

Manual UE4SS removal, if no other UE4SS mods use it:
  dwmapi.dll, UE4SS.dll, UE4SS-settings.ini, UE4SS-LICENSE.txt, Mods\, ue4ss\


UPDATE
------

OSPlus releases now live on GitHub:

  https://github.com/LuizinhoF/osplus/releases/latest

When the game detects a newer stable release, it plays one quiet cue and shows
a compact notice in the Home Hub. The notice is informational only: it never
blocks play, downloads files, closes the game, or installs the update for you.

To update from an extracted OSPlus package:

Windows:

  Double-click update.bat

Linux / Steam Deck:

  From the extracted folder, run:

    bash update.sh

The updater downloads the latest OSPlus.zip from GitHub Releases and runs the
normal installer again. The installer is safe to rerun over an existing OSPlus
install.


CREDITS
-------

OSPlus ships UE4SS v3.0.1 (https://github.com/UE4SS-RE/RE-UE4SS)
under its MIT license. See UE4SS-LICENSE.txt (deployed alongside UE4SS.dll).
