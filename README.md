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
