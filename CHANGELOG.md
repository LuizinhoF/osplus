# Changelog

## 0.4.1 - 2026-09-05

- Add a small, non-blocking update notice above the Home Hub's queue selector,
  with a gentle sound/animation and a link to the matching GitHub release.
- Check for updates at startup, after a match, and when entering queue;
  keep the notice within the Home Hub and beneath native transitions.
- Support English and Brazilian Portuguese, fit longer translated text, and
  use an inline hover hint to avoid stranded floating tooltips.
- Hide opponent names from chat presence until gameplay is detected, retaining
  the full list through goals and between-set selections afterward.
- Reject stale player lists across room/team changes and reconnects; keep
  unknown-team players and spectators restricted until gameplay is confirmed.
- Record the installed release version so update checks compare the right build.
- Older clients remain teammate-only (spectators: self-only) until upgraded.
- Automated chat privacy checks pass; in-game phase validation remains pending
  with the maintainer, who explicitly deferred it for this release.

Full English and pt-BR notes: [v0.4.1](docs/releases/0.4.1-patch-notes.md).

## 0.3.0 - 2026-07-24

- Redesign the in-match chat as a compact passive feed with a focused,
  vertically resizable history.
- Add an always-visible recipient selector while typing: players can choose
  Team or All, while spectators can choose All, Team 1, or Team 2.
- Keep connected-player presence visible in the focused chat.
- Close chat with Escape or an outside click, and suppress it while the native
  settings menu is open.
- Add a short notification sound for messages received from another player.
- Fix team audience routing, spectator permissions, and spectator friendly
  names.

## 0.2.1 - 2026-06-18

- Move public distribution to GitHub Releases.
- Add `dist/version.json` as repo-side release metadata.
- Add Windows and Linux update scripts that download the latest GitHub Release.
- Fix the distribution zip for Linux path separators and executable metadata.

## 0.2.0 - 2026-06-18

- Ship emote loadout UI replacement.
- Ship runtime emote metadata and localization data.
- Ship Windows/Linux install and uninstall scripts.
