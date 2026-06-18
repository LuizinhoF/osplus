# OSPlus UI SFX Source

These WAV files are the source audio for the cooked Unreal SoundWave assets at:

- `/Game/Mods/OSPlus/UI/Sounds/SFX_OSPlus_UI_Hover`
- `/Game/Mods/OSPlus/UI/Sounds/SFX_OSPlus_UI_Click`
- `/Game/Mods/OSPlus/UI/Sounds/SFX_OSPlus_UI_Open`
- `/Game/Mods/OSPlus/UI/Sounds/SFX_OSPlus_UI_Equip`

They are short synthesized UI cues for the emote loadout screen. Import them into the UE project's
`Content/Mods/OSPlus/UI/Sounds` folder with the same base filenames.

The current tuning aims for bright, quick, low-fatigue arcade-sports menu sounds. `Hover` is
intentionally very short and quiet because it may play repeatedly while the player moves through
tiles.

Regenerate the WAV files with:

```powershell
node ue-assets/sounds/ui/generate_ui_sfx.mjs
```
