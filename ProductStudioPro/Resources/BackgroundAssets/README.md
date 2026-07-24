# Background Assets (Essentials)

Built-in Product Studio backgrounds live in `essentials/`. Online search (Pexels) is the primary library in **Format Background → Image**; this folder is a small offline fallback.

## Layout

```
Resources/BackgroundAssets/
  essentials/          ← shipped presets (JPEG + `_thumb.jpg`)
  studio/              ← empty placeholder (legacy)
  staging/
  …
```

Only image files in category folders are discovered. Files named `*_thumb.jpg` are thumbnails only and are **not** listed as presets.

## Essentials specs

- **Full:** JPEG, long edge ≈ 1600, ~40–300KB
- **Thumb:** `name_thumb.jpg`, long edge ≈ 256
- **Naming:** `01-white-seamless.jpg` → title “White Seamless”

## Online backgrounds

Search uses **Pexels** and **Pixabay** in parallel (whichever keys are set). Results are interleaved in one grid.

Set keys via `ProductStudioPro/Config/Secrets.local.xcconfig` (see `Secrets.local.xcconfig.example`):
- `PEXELS_API_KEY` — https://www.pexels.com/api/
- `PIXABAY_API_KEY` — https://pixabay.com/api/docs/

Those build settings are injected into `Info.plist` as `PexelsAPIKey` / `PixabayAPIKey`. Never commit live keys.

Downloads are saved into the on-device library with photographer/license provenance — not rebundled into the app.

## Technical notes

- Discovery: `ImageBackgroundFolderCatalog` scans `BackgroundAssets/`
- Thumbs: prefer sibling `*_thumb.jpg` via `ImageBackgroundAssetLoader`
- Custom / online: `ImageBackgroundStore` in Application Support
