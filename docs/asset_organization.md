# Asset Organization

This note records the current asset layout and the files moved out of the runtime asset tree.

## Runtime Assets

- `assets/images/`: images bundled into the Flutter app.
- `assets/images/HomeNav/`: bottom navigation icons.
- `assets/images/HomeActions/`: home action icons.
- `assets/images/HomeModes/`: game mode icons.
- `assets/images/PlayerIcons/`: player icon images.
- `assets/images/ResultWaza/`: result formation icons.
- `assets/images/BattleStamps/`: battle stamp icons.
- `assets/images/Badge/`: ranking and badge images.
- `assets/audio/`: audio bundled into the Flutter app.
- `assets/rl_model.json`: CPU/AI model data.

## Archived Files

- `_archive/unused_assets_2026-08-14/imported_file_duplicates/`
  - Temporary upload files that were already copied into `assets/images/...`.
- `_archive/unused_assets_2026-08-14/root_duplicates/`
  - Root-level duplicate image/audio files. Runtime code uses the copies under `assets/`.
- `_archive/source_assets_2026-08-14/raw_images/`
  - Large source/original images. These are kept for future editing, but are not bundled directly.

## Notes

- Keep new runtime images under the matching `assets/images/...` subdirectory.
- Use `imported_file/` only as a temporary drop zone. After applying an image, move or remove the temporary file.
- Do not put source/original large images under `assets/images/` unless the app loads them directly.
