# Linux zip executable metadata

| Field | Value |
|---|---|
| Date | 2026-06-18 |
| Area | build |
| Tags | zip, linux, installer, permissions, powershell |
| Status | confirmed |

## Symptom

The Windows-built distribution zip extracted awkwardly on Linux: the shell
installers were regular read/write files instead of executable scripts. A user
could still run `bash install.sh`, but `./install.sh` failed unless they first
ran `chmod +x install.sh`.

## Root cause

`Compress-Archive` creates Windows-hosted zip entries. Even if a script's
content is LF-only, Linux archive tools decide extracted executable permissions
from the zip entry metadata. Windows-hosted entries do not carry the Unix
`0755` mode in the form that `unzip` honors.

## Fix

`build_dist.ps1` now writes the final zip with `System.IO.Compression`, stores
Unix mode bits for directories, ordinary files, shell scripts, and executables,
then patches central-directory entries to mark them as Unix-hosted. It also
normalizes copied `.sh` installers to LF immediately before packaging.

## Lesson

For cross-platform zip releases built on Windows, file contents and
`.gitattributes` are not enough. Verify the archive metadata itself with a
tool that prints permissions, and do not rely on `Compress-Archive` for files
that Linux users should execute directly.

## Related

- Files: `build_dist.ps1`, `dist/install.sh`, `dist/uninstall.sh`
- Prior learnings: `docs/learnings/oci-relay-deploy-gotchas.md`
