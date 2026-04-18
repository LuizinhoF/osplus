=====================================
 OSPlus - Omega Strikers Mod Platform
=====================================

OSPlus is a community mod platform for Omega Strikers.

This installer ships the FIRST feature: in-match team text chat,
synced in real-time between all OSPlus users on the same team.

More features (player profiles, currency, social, analytics) are on
the roadmap. One install, growing capabilities over time.


INSTALL
-------

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


USAGE
-----

  1. Launch Omega Strikers normally (from Steam)
  2. Join a match
  3. Press ENTER to open the chat box
  4. Type your message and press ENTER to send
  5. Press ESCAPE to close the chat without sending

Chat only appears during matches and only sends messages to teammates.
The sidecar (relay client) starts automatically with the game and shuts
down when you close the game.


CONFIG
------

OSPlus ships pointing at the public OSPlus relay:

  wss://play-osplus.duckdns.org

You don't need to change anything to chat with other OSPlus users.

If you want to run your own relay (closed group, LAN, dev), edit:

  <game>\Binaries\Win64\Mods\OSPlus\sidecar\config.json

  {
    "relay_url": "wss://your-server.example.com"
  }

Use wss:// (TLS) for anything reachable over the internet. ws:// is
fine for localhost / LAN testing only.


TROUBLESHOOTING
---------------

Chat not appearing?
  - Re-run install.bat (make sure it says "Installation complete!")
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


UNINSTALL
---------

  1. Delete: <game>\Binaries\Win64\Mods\OSPlus\
  2. Delete: <game>\OmegaStrikers\Content\Paks\LogicMods\OSPlus.pak
  3. (Optional) Remove the "OSPlus : 1" line from
     <game>\Binaries\Win64\Mods\mods.txt

To remove UE4SS entirely, delete these from <game>\Binaries\Win64\:
  dwmapi.dll, UE4SS.dll, UE4SS-settings.ini, UE4SS-LICENSE.txt, Mods\, ue4ss\


CREDITS
-------

OSPlus ships UE4SS v3.0.1 (https://github.com/UE4SS-RE/RE-UE4SS)
under its MIT license. See UE4SS-LICENSE.txt (deployed alongside UE4SS.dll).
