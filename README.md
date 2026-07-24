# Product Studio Pro

Capture, enhance, and export catalog-grade product photos entirely on-device. Vision
foreground masking, Core Image polish, a PowerPoint-style background engine, and
layered photo styles all run locally — photos never leave the phone.

## Highlights

### Capture & import

- **Single & batch capture** with optional multi-angle shots (front, back, side 1,
  side 2) and a live **Capture Quality Assistant** that flags blur, low light, and
  framing issues before you queue the shot.
- **Barcode / UPC scanning** for automatic filenames (`AVCaptureSession` scanner).
- **Import from Photos**, **Files**, or **paste / URL** (`PasteOrURLImportSheet`,
  `ClipboardURLImageImport`) — new items land at the top of the queue.
- **Automatic filenames** for Random / fallback naming:
  `SanitizedAppDisplayName_yyyyMMdd_HHmmss_SSS`. UPC scan and manual rename are
  supported; legacy `IMG_*` names stay stable until renamed.

### Polish & upscale

- **Standard Clean** and **Studio AI** (Natural, Strong, Ultra) with white balance,
  shadow/highlight recovery, local clarity, denoise, sharpening, and **Smart Color
  Accuracy**.
- **Smart Upscale** doubles canvas resolution with super-sampled Lanczos resizing
  plus an unsharp-mask pass. The app reports before/after resolution and edge-sharpness
  delta.
- **Fix edges (de-fringe)** and **Standard Clean / Studio AI quick applies** from
  preview overflow menus.

### Backgrounds & canvas

- **Format Background** sheet: PowerPoint-style fills — solid or gradient with
  linear, radial, angular, and mesh types; unlimited color stops; direction and
  angle controls.
- **Premium background presets** (Marketplace, Premium, Hero, Studio, Bold) plus a
  large **gradient catalog** (`GradientPresetCatalog.swift`, generated from
  `scripts/generate_gradient_catalog.py`) with grouped palettes (Luxury Automotive,
  Ultra AMOLED, Medical, etc.).
- **Match product colors** samples the subject and updates background stops in place
  (`ProductColorPaletteExtractor`, `BackgroundFillEditorViews`).
- **Canvas presets** (Amazon, Etsy, Instagram, custom size) via liquid-glass dropdown
  menus anchored to the trigger (`DSDropdownSystem`, `CanvasPresetCatalog`).
- **Grouped cover composites** — multi-product layouts with a UIKit editor
  (`GroupedCoverEditorViewController`, `CompositeBundleRenderer`).

### Styles (Edit & Polish)

Curated **51 photo styles** in the horizontal **Adjustments** strip
(`PhotosStyleFilterStrip`, `StylePreviewThumbnailRenderer`), organized as:

| Collection | Examples |
| --- | --- |
| Product Studio | Original, Auto, True White Backdrop, Premium Retail, Jewelry Shine, Watch Studio |
| Social Media | Social Media, Instagram Pop, TikTok Bright, Creator Mode |
| Modern Looks | Photos Natural, Photos Vibrant, Warm Luxury, eCommerce Vivid |
| Dramatic | Dramatic, Dramatic Cool, Vantage, Chrome |
| Film | Kodachrome, Portra 400, Fuji Classic, CineStill |
| Monochrome | Noir, High Key Mono, Stage Light Mono |
| Creative | Photos Cozy, Gotham, Thermal, Invert, Posterize, Negative |

- Thumbnails are pre-warmed on a 96 px proxy (Lanczos downsample) for responsive
  scrolling through long lists.
- **Auto enhance** uses `CIImage.autoAdjustmentFilters` before style blending — the
  closest public analogue to a Photos “magic wand,” not identical color science.
- Retired filter names in saved sessions map forward via `ExportPhotoFilter.resolved`
  (e.g. Vivid Warm → Warm Luxury, Technicolor → Photos Vibrant).
- **Default style filter** lives in Settings (default **Original**). Applied to new
  captures and imports only. Home templates do not sticky this — **App Defaults**
  resets it to Original.

### Home templates

- Horizontal packs on Home set **canvas, polish, and background** for new work.
- **App Defaults** is pinned first and restores the app baseline.
- Active pack shows **In use** and stays at the front of the strip.
- Design fills in **Preview → Format Background**; Settings only holds the session
  starting-point controls (reset to white / reset on launch).

### Brand Kit

Optional on-device stamps (`BrandMarkEditorView`, `BrandMarkModels`,
`BrandMarkRenderer`):

- **Brand Mark** — company name and/or logo with position grid, font, size,
  caption-plate color/opacity, logo size (% of short edge) and opacity, edge
  padding, and optional line wrap.
- **Image Name** — stamps the file / UPC name independently (own style, position,
  and caption settings). Cannot share a slot with Brand Mark.
- Live preview on a sample photo; **Apply Brand Kit to queue** restamps existing
  items (respects per-photo Hide Brand Kit).
- Stamped on capture, import, Preview Apply, and Reprocess. Off by default.
- **Reset Brand Kit to defaults** restores layout/colors while keeping company name
  and logo file.

### Interactive preview

- **Photos-style preview**: horizontal filmstrip, bottom action bar (Share, Edit,
  Background, Markup, Aspect, Info, Fullscreen), pinch-to-zoom, pan, double-tap
  reset, swipe between items, before/after compare slider.
- **Slide-up sheets**: Edit & Polish (styles + straighten + object fill),
  Format Background, custom canvas size, photo info (`PreviewPhotoInfoSheet`).
- **Subject Lift** hint on background-removed items (`SubjectLiftInteraction`).
- **Markup** (PencilKit + rich text: bold, italic, underline, strikethrough, fonts,
  colors, free placement) in `MarkupEditorView`.
- **Save as duplicate** preserves the current on-screen look (styles, gradients,
  markup) as a new queue item.
- **Replace** re-captures or imports a new source for the selected queue item.

### Queue & export

- Search by filename or UPC; duplicate protection when adding; in-place rename.
- **Selection mode** with bulk Enhance, Smart Upscale, Match Look, and share.
- Share dialog: individual JPGs, CSV manifest, or zipped archive (`SessionDiskStore`).
- **Persistent session** survives app restarts: lossless **PNG originals**, JPEG
  display bitmaps, generation-token disk writes, and `flushPersistenceToDisk()` when
  the app backgrounds.

### Memory safety

- Soft queue cap (**200** per session) plus a live **memory budget**
  (`MemoryPressureMonitor`) based on device RAM, free memory, and thermal state.
- Capture/import are gated before work starts; under pressure the app streams
  decode→process→append (never holds a full import batch), drops concurrency to
  one-at-a-time, and shrinks Vision / Studio AI long-edge caps.
- Purge ladder on memory warnings: background caches → cutout cache → originals →
  off-screen processed bitmaps (reload from disk) → cancel bulk jobs.
- **MemoryGuidanceSheet** shows tips and recommended actions before the session
  becomes hard to use.

### Design & theming

- Shared **Design System** (`DesignSystem.swift`): semantic color tokens, spacing,
  typography, cards, dashboard chrome, preview dock tray.
- **Adaptive Light/Dark** branding (`Theme.swift`, `AppTheme`) with WCAG-friendly
  accents and **liquid-glass** chips, panels, and anchored dropdown menus.
- **App icons**: text-free gradient + lens motif. Regenerate with
  `scripts/generate_app_icons.py` (requires Pillow; see script header). Additional
  icon scripts live under `scripts/`.

## Build & Run

1. Open `ProductStudioPro.xcodeproj` in **Xcode 16** or newer.
2. Select an **iPhone running iOS 17+** (Vision foreground-instance mask requires
   iOS 17).
3. Trust your developer certificate on device the first time you install
   (Settings → General → VPN & Device Management).

Camera, photo-library, and file permissions are requested at runtime. Image processing
(cutout, polish, styles, export) runs entirely on-device. Optional network is used only
when you import an image from a URL or search online backgrounds (Pexels / Pixabay).
Stock API keys are loaded from `ProductStudioPro/Config/Secrets.local.xcconfig`
(see `Secrets.local.xcconfig.example`) — never commit live keys.

## Project Layout

| Path | Responsibility |
| --- | --- |
| `ProductStudioProApp.swift` | App entry, session environment, background flush hook. |
| `Models.swift` | Data models, `CaptureSessionStore`, `ExportPhotoFilter`, naming, export helpers. |
| `ImageProcessor.swift` | Vision cutout + Core Image polish / styles / upscale pipeline. |
| `SessionDiskStore.swift` | Queue persistence (PNG originals, JPEG processed), generation-safe saves, ZIP export writer. |
| `HomeView.swift` | Dashboard, templates, import flows, How It Works, session status. |
| `MemoryPressureMonitor.swift` | Device memory budget, pressure levels, capacity gates. |
| `MemoryGuidanceSheet.swift` | Tips / recommended actions when memory is elevated. |
| `CaptureFlowView.swift` | Single/batch camera flow, Capture Quality Assistant. |
| `CameraCaptureView.swift` | AVFoundation camera wrapper. |
| `QueueView.swift` | Queue list, bulk actions, session/export chrome. |
| `ImagePreviewPagerView.swift` | Full-screen Photos-style preview, edit sheets, markup entry. |
| `BrandMarkEditorView.swift` | Brand Kit editor (text, logo, Image Name, live preview, queue apply). |
| `BrandMarkModels.swift` | Brand Kit settings, caption presets, font catalog, renderer. |
| `Config/Secrets.xcconfig` | Stock API key build settings (local overrides gitignored). |
| `PreviewPhotosChrome.swift` | Filmstrip + Photos-style bottom action bar. |
| `PreviewZoomGestures.swift` | Pinch/pan/double-tap zoom on preview canvas. |
| `PreviewPhotoInfoSheet.swift` | Metadata, dimensions, file sizes, EXIF-style details. |
| `PhotosStyleFilterStrip.swift` | Horizontal style picker with live thumbnails. |
| `StylePreviewThumbnailRenderer.swift` | Style cache, Lanczos proxy, pre-warm actor. |
| `BackgroundFillSystem.swift` | PowerPoint-style fill model + Core Image / SwiftUI rendering. |
| `BackgroundFillEditorViews.swift` | Format Background sheet UI, match-product-colors. |
| `GradientPresetCatalog.swift` | Generated multi-group gradient preset library. |
| `ProductColorPaletteExtractor.swift` | Samples product colors for background matching. |
| `CanvasPresetCatalog.swift` | Marketplace canvas sizes + dropdown preset menu. |
| `DSDropdownSystem.swift` | Anchored liquid-glass overlay menus (above sheets/modals). |
| `DesignSystem.swift` | Global DS tokens, forms, dashboard, preview dock components. |
| `Theme.swift` | Brand palette, adaptive tokens, `LiquidGlassChip`, button styles. |
| `MarkupEditorView.swift` | Full-screen PencilKit + attributed text markup. |
| `GroupedCoverEditorViewController.swift` | UIKit grouped-cover layout editor. |
| `CompositeBundleModels.swift` | `CompositeBundleLayout` JSON model. |
| `CompositeBundleRenderer.swift` | Renders multi-product cover composites. |
| `CompositeBundleCutoutLoader.swift` | Subject cutouts for bundle slots. |
| `CompositeLayoutEngine.swift` | Layout math for bundle arrangements. |
| `SettingsView.swift` | Capture, polish, default style filter, naming, branding, export profiles. |
| `BarcodeScannerView.swift` | UPC scanning UI. |
| `PasteOrURLImportSheet.swift` | Pasteboard / URL image import. |
| `ClipboardURLImageImport.swift` | URL fetch + decode helpers. |
| `ImageImportDecoder.swift` | Shared image decode utilities. |
| `Feedback.swift` | Haptics and lightweight UI feedback. |
| `scripts/` | App icon generators, gradient catalog generator. |

## Notes for App Store Submission

- Catalog processing runs on-device. No analytics or data collection.
- Optional network: URL image import and online background search only.
- `APP_STORE_PUBLISHING_GUIDE.txt` — metadata and screenshot guidance.
- `PRIVACY_POLICY_TEMPLATE.txt` — privacy policy template (update before App Store).
- Tested on iPhone 14 Pro and later. Async capture processing, memory ceilings, and
  serial disk I/O protect against ImageIO crashes during large batch captures.

## Platform Limits

- iOS provides **no public API** to host Apple’s full Photos Adjust / Styles editor
  for an arbitrary in-memory `UIImage`. Product Studio Pro implements its own
  styles and markup. For Apple’s native editing pipeline, export to the
  Photos library and edit in the system Photos app.
