# OSPlus

OSPlus is a community-maintained mod for Omega Strikers. It adds community
features that install alongside the game and can be updated without replacing
your whole game install.

## Install

Download the latest OSPlus release:

https://github.com/LuizinhoF/osplus/releases/latest

Extract `OSPlus.zip`, then run:

- Windows: `install.bat`
- Linux / Steam Deck: `bash install.sh`

Linux / Steam Deck users must also set this Omega Strikers Steam Launch Option:

```text
WINEDLLOVERRIDES="dwmapi=n,b" %command%
```

## In-match chat

Press `Enter` during a match to open chat. The selected recipient appears
beside the input:

- Players can switch between **Team** and **All** with `Tab` or `Shift+Tab`.
- Spectators can switch between **All**, **Team 1**, and **Team 2**.
- Press `Escape`, or click outside the chat, to close it without sending.

The expanded chat also shows which players are currently connected to OSPlus.

## Update

From an extracted OSPlus package, run:

- Windows: `update.bat`
- Linux / Steam Deck: `bash update.sh`

The updater downloads the latest `OSPlus.zip` from GitHub Releases and reruns
the installer.

## Uninstall

From an extracted OSPlus package, run:

- Windows: `uninstall.bat`
- Linux / Steam Deck: `bash uninstall.sh`

The uninstaller removes OSPlus files and asks before removing shared UE4SS
files, because another mod may also be using them.

## Troubleshooting

If OSPlus does not load:

- Re-run the installer from the latest release.
- On Linux / Steam Deck, confirm the launch option is set exactly as shown
  above.
- Restart Omega Strikers after installing or updating.
