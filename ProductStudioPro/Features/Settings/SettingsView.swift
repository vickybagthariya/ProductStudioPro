import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: CaptureSessionStore

    var body: some View {
        AppScreenScaffold(
            title: "Settings",
            subtitle: "Defaults for capture, polish, backgrounds, and export",
            showsHome: false,
            onBack: { session.popNavigation() },
            onHome: { session.goHome() },
            layout: .scroll
        ) {
            // 1. Capture
            DSSectionCard(title: "Capture Settings", icon: "camera.fill") {
                Toggle("Vibrate", isOn: $session.vibrateEnabled)
                    .tint(DS.ColorToken.accent)
                DSDivider()
                Toggle("Beep", isOn: $session.beepEnabled)
                    .tint(DS.ColorToken.accent)
                DSDivider()
                Picker("Batch Mode camera", selection: Binding(
                    get: { session.batchAutoOpenCamera ? BatchAutoOpenCameraPreference.automatic : BatchAutoOpenCameraPreference.manual },
                    set: { session.setBatchAutoOpenPreference($0) }
                )) {
                    ForEach(BatchAutoOpenCameraPreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                .tint(DS.ColorToken.accent)
                DSHelperText(BatchAutoOpenCameraPreference.automatic.settingsDescription + " Uses the system camera; flash and front/back settings are remembered between batch captures.")
            }

            // 2. Naming
            DSSectionCard(title: "Barcode & Naming", icon: "barcode.viewfinder") {
                HStack {
                    Text("Save image name by")
                        .font(DS.TypeScale.body)
                        .foregroundStyle(DS.ColorToken.label)
                    Spacer()
                    Picker("", selection: $session.imageNamingMode) {
                        ForEach(ImageNamingMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .tint(DS.ColorToken.accent)
                }
                DSHelperText("Recommended: Scan UPC. Random and auto-generated names use your app display name as a prefix plus a date-time stamp. Use Manual when barcode is missing.")
            }

            // 3. Multi-angle
            DSSectionCard(title: "Multi-Angle Photos", icon: "square.stack.3d.up.fill") {
                Toggle("Multi-Angle Mode", isOn: $session.multiAngleEnabled)
                    .tint(DS.ColorToken.accent)
                if session.multiAngleEnabled {
                    DSDivider()
                    DSHelperText("Captures each selected angle first, then one UPC names the set as UPC-1, UPC-2, …. Badges still show Front / Back / Side. Toggle also available on the capture screen.")
                    ForEach(ProductAngle.captureAngles) { angle in
                        Toggle(angle.rawValue, isOn: Binding(
                            get: { session.enabledAngles.contains(angle) },
                            set: { session.toggleAngle(angle, enabled: $0) }
                        ))
                        .tint(DS.ColorToken.accent)
                    }
                }
            }

            // 4. Photo Quality — session defaults for new captures / imports
            DSSectionCard(title: "Photo Quality", icon: "wand.and.stars") {
                DSHelperText("Defaults for new captures and imports. Standard Clean is fast and memory-light — tuned for smooth performance on large sessions.")

                Toggle("Auto Background Removal", isOn: $session.autoBackgroundRemoval)
                    .tint(DS.ColorToken.accent)
                DSDivider()
                Toggle("AI Polish on new photos", isOn: $session.productPolishEnabled)
                    .tint(DS.ColorToken.accent)
                DSHelperText("When on, new captures and imports get one-tap Enhance automatically. Tap Enhance in Preview to re-run polish anytime.")
                DSDivider()
                Toggle("Subject Lift (Preview)", isOn: $session.subjectLiftEnabledInPreview)
                    .tint(DS.ColorToken.accent)
                DSHelperText("Optional Photos-style long-press subject lift in Preview (after background removal). Off by default. Automatically pauses under high memory pressure, Low Power Mode, or when the phone is hot.")

                DSDivider()
                DSDropdownActionMenu(
                    label: {
                        HStack {
                            Text("Default style filter")
                                .foregroundStyle(DS.ColorToken.label)
                            Spacer()
                            Text(session.preferredExportPhotoFilter == .none || session.preferredExportPhotoFilter == .standard
                                  ? "Original"
                                  : session.preferredExportPhotoFilter.rawValue)
                                .foregroundStyle(DS.ColorToken.secondaryLabel)
                                .lineLimit(1)
                        }
                    },
                    items: ExportPhotoFilter.pickerCases.map { filter in
                        let title = (filter == .none || filter == .standard) ? "Original" : filter.rawValue
                        let selected = session.preferredExportPhotoFilter == filter
                            || (filter == .none && session.preferredExportPhotoFilter == .standard)
                        return DSDropdownActionItem.action(filter.rawValue, title, isSelected: selected)
                    },
                    prefersFullWidth: true
                ) { item in
                    if let filter = ExportPhotoFilter(rawValue: item.id) {
                        session.preferredExportPhotoFilter = filter == .standard ? .none : filter
                    }
                }
                DSHelperText("Applied to new captures and imports only. Home templates do not change this (App Defaults resets it to Original).")

                DSDivider()
                Button("Reset polish & filter to defaults") {
                    session.productPolishEnabled = true
                    session.preferredExportPhotoFilter = .none
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(maxWidth: .infinity)
                DSHelperText("Sets Product Polish on and the style filter back to Original (the app baseline). Does not change photos already in the queue.")
            }

            // Performance tips — fast+good profile guidance for large sessions.
            DSSectionCard(title: "Performance Tips", icon: "gauge.with.dots.needle.67percent") {
                DSHelperText("This app favors speed and lower memory pressure over maximum resolution:")
                VStack(alignment: .leading, spacing: DS.Space.stack - 2) {
                    Label("Keep sessions smaller — export finished photos, then clear or start a new session folder.", systemImage: "folder.badge.minus")
                    Label("Close Preview / Markup when done editing, especially during bulk import.", systemImage: "xmark.circle")
                    Label("Avoid Low Power Mode during heavy capture or export — it slows processing further.", systemImage: "battery.100")
                }
                .font(DS.TypeScale.caption)
                .foregroundStyle(DS.ColorToken.secondaryLabel)
            }

            // 5. Background defaults (designer lives in Format Background / Home templates)
            DSSectionCard(title: "Background Defaults", icon: "paintpalette.fill") {
                DSHelperText("Design backgrounds in Preview → Format Background, or apply a Home template. Settings only control the session starting point.")

                Button("Reset default background to White") {
                    session.resetBackgroundStyleToDefaultWhite()
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(maxWidth: .infinity)

                DSDivider()
                Toggle("Reset background to white on launch", isOn: $session.resetBackgroundToWhiteOnLaunch)
                    .tint(DS.ColorToken.accent)
                DSHelperText("Off (recommended): keep your last background when the app reopens. On: every cold launch starts from white.")
            }

            // 6. Export & canvas
            DSSectionCard(title: "Export & Canvas", icon: "square.and.arrow.down.fill") {
                Picker("Export profile", selection: Binding(
                    get: { session.exportChannelProfile },
                    set: { session.applyExportChannelProfile($0) }
                )) {
                    ForEach(ExportChannelProfile.allCases) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
                .tint(DS.ColorToken.accent)
                DSHelperText(session.exportChannelProfile.settingsGuidanceText)

                DSDivider()

                DSDropdownActionMenu(
                    label: {
                        Label("Canvas presets", systemImage: "aspectratio")
                            .foregroundStyle(DS.ColorToken.label)
                    },
                    items: CanvasPresetCatalog.settingsActionItems(
                        currentWidth: session.outputCanvasWidth,
                        currentHeight: session.outputCanvasHeight
                    ),
                    prefersFullWidth: true
                ) { item in
                    if let preset = CanvasPresetCatalog.all.first(where: { $0.id == item.id }) {
                        session.markExportChannelProfileCustom()
                        let clamped = CanvasPresetCatalog.clampDimensions(width: preset.width, height: preset.height)
                        session.outputCanvasWidth = clamped.width
                        session.outputCanvasHeight = clamped.height
                    }
                }

                HStack(spacing: DS.Space.stack) {
                    Stepper(
                        "Width \(session.outputCanvasWidth)",
                        value: Binding(
                            get: { session.outputCanvasWidth },
                            set: {
                                session.markExportChannelProfileCustom()
                                session.outputCanvasWidth = $0
                            }
                        ),
                        in: CanvasPresetCatalog.dimensionBounds,
                        step: 100
                    )
                    Stepper(
                        "Height \(session.outputCanvasHeight)",
                        value: Binding(
                            get: { session.outputCanvasHeight },
                            set: {
                                session.markExportChannelProfileCustom()
                                session.outputCanvasHeight = $0
                            }
                        ),
                        in: CanvasPresetCatalog.dimensionBounds,
                        step: 100
                    )
                }
                .font(DS.TypeScale.caption)

                VStack(alignment: .leading, spacing: DS.Space.stack - 2) {
                    HStack {
                        Text("Canvas Fill")
                            .font(DS.TypeScale.body)
                            .foregroundStyle(DS.ColorToken.label)
                        Spacer()
                        Text("\(Int(session.outputFillRatio * 100))%")
                            .font(DS.TypeScale.caption)
                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                    }
                    Slider(
                        value: Binding(
                            get: { session.outputFillRatio },
                            set: {
                                session.markExportChannelProfileCustom()
                                session.outputFillRatio = $0
                            }
                        ),
                        in: 0.80...1.0,
                        step: 0.01
                    )
                    .tint(DS.ColorToken.accent)
                }

                DSHelperText("Recommended: auto background removal on, 1200 × 1200 (or your channel’s aspect), ~95% fill for catalog-ready shots. Raise fill up to 100% for tighter framing (may crop soft shadows slightly).")
            }

            // 7. Compression / Sharing
            DSSectionCard(title: "Compression / Sharing", icon: "square.and.arrow.up.fill") {
                Toggle("Compress Before Sharing", isOn: Binding(
                    get: { session.compressBeforeShare },
                    set: {
                        session.markExportChannelProfileCustom()
                        session.compressBeforeShare = $0
                    }
                ))
                .tint(DS.ColorToken.accent)
                DSDivider()

                VStack(alignment: .leading, spacing: DS.Space.stack - 2) {
                    HStack {
                        Text("JPG Quality")
                            .font(DS.TypeScale.body)
                            .foregroundStyle(session.compressBeforeShare ? DS.ColorToken.label : DS.ColorToken.tertiaryLabel)
                        Spacer()
                        Text(session.compressBeforeShare ? "\(Int(session.jpegQuality * 100))%" : "100%")
                            .font(DS.TypeScale.caption)
                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                    }
                    Slider(
                        value: Binding(
                            get: { session.jpegQuality },
                            set: {
                                session.markExportChannelProfileCustom()
                                session.jpegQuality = $0
                            }
                        ),
                        in: 0.85...1.00,
                        step: 0.01
                    )
                    .tint(DS.ColorToken.accent)
                    .disabled(!session.compressBeforeShare)
                    .opacity(session.compressBeforeShare ? 1 : DS.Motion.disabledOpacity)
                }

                DSHelperText("Channel profiles set ~86–90%. Raise toward 98% for sharper labels (larger files). When Compress is off, exports use maximum quality. Applies to JPG and ZIP (JPG + CSV) so Mail attachments stay predictable.")
                DSDivider()
                DSHelperText("From Queue, share ZIP (JPG + CSV), JPG, PNG cutouts, or CSV only via the iOS share sheet (Mail, Messages, AirDrop, Files). ZIP is best for 2+ items; JPG for a quick single share.")
            }

            // 8. Branding
            DSSectionCard(title: "Custom Branding", icon: "paintbrush.pointed.fill") {
                Toggle("Enable Custom Branding on Home Screen", isOn: $session.showBranding)
                    .tint(DS.ColorToken.accent)
                DSDivider()

                TextField("Your Business Name", text: $session.businessName)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)
                    .dsSemanticTextField()

                TextField("Your Tagline / Developer Line", text: $session.developerLine)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)
                    .dsSemanticTextField()

                DSHelperText("Shows on Home when enabled — not stamped on catalog images. Use Brand Kit on Home for image watermarks.")
                DSDivider()
                Button {
                    session.navigationPath.append(AppRoute.brandMark)
                } label: {
                    Label("Open Brand Kit", systemImage: "seal")
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(maxWidth: .infinity)
            }

            // Sessions soft-limit note
            DSSectionCard(title: "Sessions", icon: "folder") {
                DSHelperText("Queues are per named session (soft limit \(CaptureSessionStore.CatalogSessionLimits.softQueueCap) photos each). Capture and imports go into the active session. Manage sessions from Home or the folder control in Queue.")
            }
        }
        .navigationBarHidden(true)
    }
}
