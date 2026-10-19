import SwiftUI
import AppKit
import Photos
import ImageIO
import UniformTypeIdentifiers

private let thumbSize: CGFloat = 52
private let railThumbSize: CGFloat = 76
private let railWidth: CGFloat = 108

// MARK: - Root (three-pane: library rail | preview | scrollable inspector, on one blurred surface)

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    var body: some View {
        HStack(spacing: 0) {
            LibraryRail()
                .frame(width: railWidth)
            PreviewPane()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            InspectorPane()
                .frame(width: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectView().ignoresSafeArea())
        .background(WindowAccessor())
        .task { model.loadInitialPhotosIfNeeded() }
        .alert("Fehler", isPresented: errorBinding) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - Library rail (far left): every project, newest first

/// Every creation is a project that keeps its recipe, so the rail is both the history
/// and the way back into a piece of work. The selected tile *is* what the editor is
/// showing; edits autosave into it, and "+" branches off a copy.
private struct LibraryRail: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(model.projects) { project in
                        ProjectTile(project: project)
                    }
                }
                .padding(.vertical, 14)
            }

            Button {
                model.duplicateSelected()
            } label: {
                Image(systemName: "plus")
                    .font(.body)
                    .frame(width: 20, height: 20)
                    .padding(9)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .help("Projekt duplizieren")
            .accessibilityLabel(L("Projekt duplizieren"))
            .padding(.bottom, 14)
        }
        .frame(maxHeight: .infinity)
        .onAppear { model.refreshProjects() }
    }
}

private struct ProjectTile: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    @State private var thumbnail: NSImage?

    private var isSelected: Bool { model.selectedProjectID == project.id }
    private var isActive: Bool { model.activeProjectID == project.id }

    private var tooltip: String {
        let date = project.createdAt.formatted(date: .abbreviated, time: .shortened)
        return [project.displayName, project.style?.label, date].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        Button {
            model.open(project)
        } label: {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.2).overlay(ProgressView().controlSize(.small))
                }
            }
            .railChrome(isSelected: isSelected)
            .overlay(alignment: .bottomTrailing) {
                // Applying and editing are separate now, so mark which project is
                // actually on the desktop.
                if isActive {
                    Image(systemName: "macwindow")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(3)
                        .background(.thinMaterial, in: Circle())
                        .padding(4)
                        .help("Aktives Wallpaper")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tooltip)
        .help(tooltip)
        .contextMenu {
            Button("Als Schreibtisch setzen") { model.applyProject(project) }
            Button("Projekt duplizieren") { model.open(project); model.duplicateSelected() }
            Divider()
            Button("Als HEIC exportieren…") { model.exportProject(project) }
            Button("In Fotos sichern") { model.saveProjectToPhotosLibrary(project) }
            Button("Im Finder zeigen") { model.revealInFinder(project) }
            Divider()
            Button("Neues Projekt") { model.newProject() }
            Button("Löschen", role: .destructive) { model.deleteProject(project) }
        }
        // The live editor preview is fresher than the file on disk, so the selected
        // tile follows the editor instead of waiting for the next autosave.
        .task(id: thumbnailKey) {
            if isSelected, let preview = model.preview {
                thumbnail = preview
                return
            }
            let url = project.thumbnailURL
            // The collection may live in iCloud Drive, where the local copy can be
            // evicted — pull it back before asking ImageIO for a thumbnail.
            guard await WallpaperLibrary.ensureDownloaded(url) else { return }
            thumbnail = await loadImageThumbnail(url: url, maxPixelSize: 320)
        }
    }

    /// Re-runs the thumbnail task when the project changes, when it becomes the
    /// selected one, and on every editor re-render while it is selected.
    private var thumbnailKey: String {
        "\(project.id)|\(project.updatedAt.timeIntervalSince1970)|\(isSelected)|\(model.previewGeneration)"
    }
}

private extension View {
    /// Square framing + rounded clip + selection ring for the rail's larger tiles.
    ///
    /// Heavier than a hairline on purpose: the system draws its own focus ring in the
    /// same accent colour, and focus and selection can sit on different tiles (pressing
    /// "+" moves the selection but not the focus). The glow is what tells them apart.
    func railChrome(isSelected: Bool) -> some View {
        self
            .frame(width: railThumbSize, height: railThumbSize)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            )
            .shadow(color: isSelected ? Color.accentColor.opacity(0.45) : .clear, radius: 6)
    }
}

// MARK: - Preview pane (centre)

private struct PreviewPane: View {
    @EnvironmentObject var model: AppModel

    private var aspect: CGFloat {
        let s = model.pixelSize
        return CGFloat(s.width) / CGFloat(max(1, s.height))
    }

    /// A project from before the project format has no recipe to edit — it can only
    /// be shown as the finished file it is.
    private var legacyProject: Project? {
        guard let p = model.selectedProject, !p.isEditable else { return nil }
        return p
    }

    var body: some View {
        ZStack {
            if let legacy = legacyProject {
                RenderedPreview(project: legacy, aspect: aspect)
            } else if let preview = model.preview {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(aspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 20, y: 10)
                    .padding(40)
                    .onDrag { model.makeDragProvider() }
                    .help("Zum Exportieren in den Finder / auf den Schreibtisch ziehen")
            } else {
                ContentUnavailableView {
                    Label(L("Kein Bild für „%@“", model.editing.label), systemImage: "photo.badge.plus")
                } description: {
                    Text("Wähle rechts ein Foto, ein Bild aus Fotos oder eine Datei.")
                }
            }

            if model.isLoadingSource { ProgressView().controlSize(.large) }

            VStack {
                if legacyProject == nil {
                    AppearanceSwitcher()
                        .padding(.top, 18)
                }
                Spacer()
                if model.statusMessage != nil {
                    StatusCapsule()
                        .padding(.bottom, 22)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(duration: 0.3), value: model.statusMessage)
    }
}

/// A finished wallpaper straight off disk. Only the Light frame of the dynamic HEIC
/// is shown — this is a finished file, not something being edited.
private struct RenderedPreview: View {
    let project: Project
    let aspect: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(aspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 20, y: 10)
                    .padding(40)
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task(id: project.id) {
            image = nil
            let url = project.wallpaperURL
            guard await WallpaperLibrary.ensureDownloaded(url) else { return }
            image = await loadImageThumbnail(url: url, maxPixelSize: 1600)
        }
    }
}

/// Floating Hell/Dunkel switch + "auf andere Ansicht übernehmen" button, rendered
/// as one Liquid Glass cluster (macOS 26) that floats above the preview. A system
/// segmented picker stays flat at rest, so the two appearances are custom glass
/// segments (selected = accent-tinted) to match the copy button's glass.
private struct AppearanceSwitcher: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Appearance.allCases) { segment($0) }

                Button {
                    model.copyCurrentLookToOther()
                } label: {
                    Image(systemName: "square.on.square")
                        .font(.body)
                        .frame(width: 20, height: 20)
                        .padding(11)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .disabled(!model.lookHasContent(model.currentLook))
                .help(L("Auf „%@“ übernehmen", model.editing.other.label))
            }
        }
    }

    private func segment(_ appearance: Appearance) -> some View {
        let selected = model.editing == appearance
        return Button {
            model.editing = appearance
        } label: {
            Text(appearance.label)
                .font(.callout.weight(.medium))
                .foregroundStyle(selected ? .white : .primary)
                .frame(minWidth: 54)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(.accentColor).interactive()
                              : .regular.interactive(), in: Capsule())
    }
}

private struct StatusCapsule: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Label(model.statusMessage ?? "", systemImage: "checkmark.circle")
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Inspector pane (right): grouped form + pinned action bar

private struct InspectorPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                // No project-name row: the title derives itself from the photo and
                // shows where it is useful — on the rail tile and as the file name in
                // the Finder. Repeating it here is a line the user never acts on.
                if let legacy = model.selectedProject, !legacy.isEditable {
                    LegacyProjectSection(project: legacy)
                } else {
                    BaseImageSection()
                    EffectSection()
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            ActionBar()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            // A dropped .lurent is a project to open; anything else is a source photo.
            for url in urls {
                if url.pathExtension.lowercased() == WallpaperLibrary.packageExtension {
                    model.importProject(at: url)
                } else if isImageFile(url) {
                    model.openLocalImage(url: url)
                }
            }
            return true
        }
    }
}

/// Inspector for a wallpaper made before projects existed: there is a finished file
/// but no recipe behind it, so there is nothing to put sliders on.
private struct LegacyProjectSection: View {
    let project: Project

    var body: some View {
        Section("Gesichertes Wallpaper") {
            LabeledContent(L("Erstellt"),
                           value: project.createdAt.formatted(date: .abbreviated, time: .shortened))
            Text("Dieses Wallpaper stammt aus einer früheren Version und lässt sich nicht mehr bearbeiten.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Base image section (source picker + browser)

private struct BaseImageSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section("Bild") {
            Picker("Quelle", selection: model.sourceKindBinding) {
                ForEach(SourceKind.allCases) { Text($0.label).tag($0) }
            }

            sourceBrowser
            SourceCredit(look: model.currentLook)
        }
        .task(id: model.selectedAlbumID) {
            let id = model.selectedAlbumID
            if !id.isEmpty { model.loadAlbumAssets(albumID: id) }
        }
        .onChange(of: model.photoAlbums) {
            if model.sourceKind == .photos, model.selectedAlbumID.isEmpty,
               let first = model.photoAlbums.first {
                model.selectedAlbumID = first.id
            }
        }
    }

    @ViewBuilder private var sourceBrowser: some View {
        switch model.sourceKind {
        case .commons:
            HStack(spacing: 8) {
                NativeSearchField(text: $model.query, placeholder: L("Wikimedia Commons durchsuchen")) {
                    model.runSearch()
                }
                .frame(height: 24)
                if model.isSearching { ProgressView().controlSize(.small) }
            }
            if let note = model.browserNote, model.results.isEmpty, !model.isSearching {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.results.isEmpty {
                ThumbGrid {
                    ForEach(model.results) { photo in
                        Button { model.select(photo) } label: {
                            CommonsThumbnail(photo: photo, isSelected: model.currentLook.photoID == String(photo.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        case .pexels:
            HStack(spacing: 8) {
                NativeSearchField(text: $model.query, placeholder: L("Pexels durchsuchen")) {
                    model.runSearch()
                }
                .frame(height: 24)
                if model.isSearching { ProgressView().controlSize(.small) }
            }
            if let note = model.browserNote, model.pexelsResults.isEmpty, !model.isSearching {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.pexelsResults.isEmpty {
                ThumbGrid {
                    ForEach(model.pexelsResults) { photo in
                        Button { model.selectPexels(photo) } label: {
                            PexelsThumbnail(photo: photo, isSelected: model.currentLook.photoID == String(photo.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        case .files:
            Button {
                openImagePanel(model)
            } label: {
                Label("Datei öffnen…", systemImage: "folder")
            }
            if !model.recentFiles.isEmpty {
                ThumbGrid {
                    ForEach(model.recentFiles, id: \.path) { url in
                        Button { model.openLocalImage(url: url) } label: {
                            LocalFileThumbnail(url: url, isSelected: model.currentLook.photoID == url.path)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(url.lastPathComponent)
                    }
                }
            }

        case .photos:
            switch model.photosAuthStatus {
            case .notDetermined:
                Button {
                    model.requestPhotosAccess()
                } label: {
                    Label("Fotos-Mediathek verbinden…", systemImage: "photo.badge.plus")
                }
            case .denied, .restricted:
                Text("Kein Fotos-Zugriff — in den Systemeinstellungen erlauben.")
                    .font(.caption).foregroundStyle(.secondary)
            case .authorized, .limited:
                if !model.photoAlbums.isEmpty {
                    Picker("Album", selection: model.albumBinding) {
                        ForEach(model.photoAlbums) { album in
                            Text(album.title).tag(album.id)
                        }
                    }
                    if !model.albumAssets.isEmpty {
                        ThumbGrid {
                            ForEach(model.albumAssets, id: \.localIdentifier) { asset in
                                Button { model.selectAlbumAsset(asset) } label: {
                                    PhotoAssetThumbnail(asset: asset, isSelected: model.currentLook.photoID == asset.localIdentifier)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            @unknown default:
                EmptyView()
            }
        }
    }
}

/// The credit each photo source requires: the photographer, linking to where the
/// photo lives (Commons' file page states the exact CC licence; Pexels requires a
/// prominent link back to Pexels). Shown for whichever appearance is being edited —
/// sources from Files or Photos carry no URL and get no row.
private struct SourceCredit: View {
    let look: Look

    var body: some View {
        if let credit {
            Text(credit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var credit: AttributedString? {
        guard let raw = look.attributionURL,
              let page = URL(string: raw),
              let name = look.attribution, !name.isEmpty
        else { return nil }

        if CommonsAttribution.isCommons(raw) {
            let markdown = L("Foto von [%@](%@) auf [Wikimedia Commons](%@)",
                             name, page.absoluteString,
                             CommonsAttribution.homeURL.absoluteString)
            return try? AttributedString(markdown: markdown)
        }
        if PexelsAttribution.isPexels(raw) {
            let markdown = L("Foto von [%@](%@) auf [Pexels](%@)",
                             name, page.absoluteString,
                             PexelsAttribution.homeURL.absoluteString)
            return try? AttributedString(markdown: markdown)
        }
        return nil
    }
}

// MARK: - Effect section (style + parameters)

private struct EffectSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section("Effekt") {
            Picker("Stil", selection: model.bind(\.style)) {
                ForEach(WallpaperStyle.allCases) { Text($0.label).tag($0) }
            }

            styleControls

            Button("Zurücksetzen") { model.resetCurrentLook() }
        }
    }

    @ViewBuilder private var styleControls: some View {
        switch model.currentLook.style {
        case .blur:
            slider("Blur", model.bind(\.blur), 0...100)
            slider("Ausschnitt", model.bind(\.blurOffset), -1...1)

        case .mirror:
            slider("Blur", model.bind(\.blur), 0...100)
            slider("Spiegel-Linie", model.bind(\.mirrorLine), 0.15...0.85)
            slider("Amplitude", model.bind(\.mirrorAmplitude), 0...0.15)
            slider("Wellenlänge", wavelengthBinding, 0...1)
            slider("Unregelmässigkeit", model.bind(\.mirrorIrregularity), 0...1)
            slider("Tiefe", model.bind(\.mirrorDepth), 0...0.8)
            slider("Seiten-Fade", model.bind(\.mirrorSideFade), 0...1)

        case .slices:
            slider("Blur", model.bind(\.blur), 0...100)
            slider("Lamellen", model.bind(\.sliceCount), 2...40)
            slider("Winkel", model.bind(\.sliceAngle), 0...3.14159265)
            slider("Versatz", model.bind(\.sliceShift), 0...1)
            slider("Fächer", model.bind(\.sliceFan), 0...1)
            slider("Kurve", model.bind(\.sliceCurve), -1...1)
            slider("Variante", model.bind(\.sliceSeed), 0...12)

        case .liquid:
            Picker("Farben", selection: model.bind(\.liquidCount)) {
                Text("3").tag(3); Text("4").tag(4); Text("5").tag(5)
            }
            .pickerStyle(.segmented)

            paletteEditor {
                HStack {
                    // Shown dark → bright; reducing the count drops the darker stops (left).
                    if model.currentLook.liquidCount >= 5 {
                        ColorPicker("Farbe 1", selection: model.bind(\.liquidColor0), supportsOpacity: false)
                    }
                    if model.currentLook.liquidCount >= 4 {
                        ColorPicker("Farbe 2", selection: model.bind(\.liquidColor1), supportsOpacity: false)
                    }
                    ColorPicker("Farbe 3", selection: model.bind(\.liquidColor2), supportsOpacity: false)
                    ColorPicker("Farbe 4", selection: model.bind(\.liquidColor3), supportsOpacity: false)
                    ColorPicker("Farbe 5", selection: model.bind(\.liquidColor4), supportsOpacity: false)
                }
                .labelsHidden()
            }

            slider("Frame", model.bind(\.liquidTime), 0...30)
            slider("Variante", model.bind(\.liquidSeed), 0...12)
            slider("Skalierung", model.bind(\.liquidScale), 0...1.0)
            slider("Turbulenz", model.bind(\.liquidTurb), 0...0.32)
            slider("Wellen", model.bind(\.liquidWave), 0.3...3)
            slider("Tonwert", model.bind(\.liquidBias), 0...0.8)
        }

        // Colour grade + grain — shared by every style.
        slider("Helligkeit", model.bind(\.brightness), -0.3...0.3)
        slider("Sättigung", model.bind(\.saturation), 0...2)
        slider("Kontrast", model.bind(\.contrast), 0.8...1.3)
        slider("Körnung", model.bind(\.dither), 0...1)
    }

    private func slider(_ title: LocalizedStringKey, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            Slider(value: value, in: range)
        }
    }

    /// "Wellenlänge" (0…1, right = longer) mapped onto the mirror's base frequency:
    /// L=0 → freq 1.5 (short waves), L=1 → freq 0.25 (long waves). Default freq 0.75 → L≈0.6.
    private var wavelengthBinding: Binding<Double> {
        let f = model.bind(\.mirrorFrequency)
        return Binding(
            get: { max(0, min(1, (1.5 - f.wrappedValue) / 1.25)) },
            set: { f.wrappedValue = 1.5 - $0 * 1.25 }
        )
    }

    /// Palette colour editor: the source photo with a draggable pointer per stop
    /// when a photo is loaded, otherwise the manual colour swatches (`fallback`).
    @ViewBuilder private func paletteEditor<Fallback: View>(
        @ViewBuilder fallback: () -> Fallback) -> some View {
        if let src = model.currentLook.source {
            VStack(alignment: .leading, spacing: 5) {
                SourceColorPicker(image: src, stops: model.activePaletteStops) { slot, point in
                    model.movePalettePoint(slot: slot, to: point)
                }
                Text("Ziehe die Punkte aufs Foto — jeder nimmt die Farbe an seiner Stelle.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            fallback()
        }
    }
}

/// The source photo with one draggable pointer per active palette stop. Drag a
/// pointer onto the region whose colour you want — that stop then samples straight
/// from the photo. Replaces the abstract colour swatches for photo-driven styles.
private struct SourceColorPicker: View {
    let image: CGImage
    let stops: [PaletteStop]
    let onMove: (Int, CGPoint) -> Void

    private static let space = "sourceColorPicker"
    private var aspect: CGFloat { CGFloat(image.width) / CGFloat(max(1, image.height)) }

    var body: some View {
        GeometryReader { geo in
            let rect = fittedRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                    .resizable()
                    .frame(width: rect.width, height: rect.height)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
                    .position(x: rect.midX, y: rect.midY)
                ForEach(stops) { stop in
                    handle(stop, in: rect)
                }
            }
            .coordinateSpace(name: Self.space)
        }
        .frame(height: 168)
    }

    /// The photo's aspect-fit rectangle within the available box (letterboxed).
    private func fittedRect(in size: CGSize) -> CGRect {
        var w = size.width, h = size.width / aspect
        if h > size.height { h = size.height; w = size.height * aspect }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func handle(_ stop: PaletteStop, in rect: CGRect) -> some View {
        let pos = CGPoint(x: rect.minX + stop.point.x * rect.width,
                          y: rect.minY + stop.point.y * rect.height)
        return Circle()
            .fill(stop.color)
            .frame(width: 28, height: 28)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
            .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 0.5))
            .overlay(Text(stop.label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 1))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .contentShape(Circle())
            .position(pos)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { g in
                        onMove(stop.id, CGPoint(x: (g.location.x - rect.minX) / rect.width,
                                                y: (g.location.y - rect.minY) / rect.height))
                    }
            )
    }
}

// MARK: - Action bar (pinned bottom): project actions + set-as-desktop

/// There is no save button: edits persist on their own. Setting the desktop is the
/// only deliberate action left, which is why it gets the whole prominent button.
private struct ActionBar: View {
    @EnvironmentObject var model: AppModel

    /// Legacy projects have a finished file but no live looks, so the editor-based
    /// exports don't apply to them — the project-based ones do.
    private var isLegacy: Bool {
        model.selectedProject.map { !$0.isEditable } ?? false
    }

    private var canAct: Bool { isLegacy || model.canExport }

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Button {
                    if let p = model.selectedProject, isLegacy {
                        model.saveProjectToPhotosLibrary(p)
                    } else {
                        model.saveToPhotosLibrary()
                    }
                } label: {
                    Label("In Fotos sichern", systemImage: "photo.stack")
                }
                Button {
                    if let p = model.selectedProject, isLegacy {
                        model.exportProject(p)
                    } else {
                        model.exportWithPanel()
                    }
                } label: {
                    Label("Als HEIC exportieren…", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("s", modifiers: .command)

                if let project = model.selectedProject {
                    Button {
                        model.exportProjectPackage(project)
                    } label: {
                        Label("Projekt exportieren…", systemImage: "shippingbox")
                    }
                }
                Button {
                    model.importProjectWithPanel()
                } label: {
                    Label("Projekt importieren…", systemImage: "tray.and.arrow.down")
                }

                Divider()

                Button {
                    model.duplicateSelected()
                } label: {
                    Label("Projekt duplizieren", systemImage: "plus.square.on.square")
                }
                Button {
                    model.newProject()
                } label: {
                    Label("Neues Projekt", systemImage: "square.dashed")
                }

                Divider()

                if let project = model.selectedProject {
                    Button {
                        model.revealInFinder(project)
                    } label: {
                        Label("Im Finder zeigen", systemImage: "folder")
                    }
                    Button(role: .destructive) {
                        model.deleteProject(project)
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.glass)
            .controlSize(.large)
            .fixedSize()
            .help("Weitere Aktionen")

            Button {
                model.applySelected()
            } label: {
                Label("Als Schreibtisch setzen", systemImage: "macwindow.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!canAct)
        }
        .padding(14)
    }
}

// MARK: - Shared browser pieces

/// A single horizontally-scrolling row of small square thumbnails
/// (for palette / source picking) — keeps the inspector vertically compact.
private struct ThumbGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                content()
            }
            .padding(.vertical, 3)
        }
        .frame(height: thumbSize + 8)
    }
}

/// Native macOS search field (NSSearchField) — reliable focus/typing, built-in
/// magnifier and clear button. Fires `onSubmit` on Return; keeps `text` in sync live.
private struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        field.sendsWholeSearchString = true          // fire only on Return / clear
        field.sendsSearchStringImmediately = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onSubmit: onSubmit) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }

        @objc func submit(_ sender: NSSearchField) {
            text.wrappedValue = sender.stringValue
            onSubmit()
        }
    }
}

private func isImageFile(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .image) ?? false
}

@MainActor
private func openImagePanel(_ model: AppModel) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    if panel.runModal() == .OK, let url = panel.url {
        model.openLocalImage(url: url)
    }
}

private extension View {
    /// Shared square framing + rounded clip + selection ring for source thumbnails.
    func thumbnailChrome(isSelected: Bool) -> some View {
        self
            .frame(width: thumbSize, height: thumbSize)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
            )
    }
}

private struct LocalFileThumbnail: View {
    let url: URL
    let isSelected: Bool
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.2).overlay(ProgressView().controlSize(.small))
            }
        }
        .thumbnailChrome(isSelected: isSelected)
        .help(url.lastPathComponent)
        .task(id: url) {
            thumbnail = await loadImageThumbnail(url: url, maxPixelSize: 240)
        }
    }
}

/// Thumbnail for any image file on disk. For a dynamic wallpaper HEIC, index 0 is
/// the Light appearance — which is exactly the face we want to show.
private func loadImageThumbnail(url: URL, maxPixelSize: Int) async -> NSImage? {
    await Task.detached(priority: .utility) {
        // Recent files come back as security-scoped bookmarks and are only readable
        // while their scope is open. A no-op for everything else, including the
        // packages inside the app's own container.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }.value
}

private struct PhotoAssetThumbnail: View {
    let asset: PHAsset
    let isSelected: Bool
    @State private var image: NSImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .thumbnailChrome(isSelected: isSelected)
        .onAppear { requestThumbnail() }
        .onDisappear { cancelRequest() }
    }

    private func requestThumbnail() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        requestID = sharedPhotoImageManager.requestImage(
            for: asset, targetSize: CGSize(width: 240, height: 240),
            contentMode: .aspectFill, options: options
        ) { img, _ in
            if let img { image = img }
        }
    }

    private func cancelRequest() {
        if let requestID { sharedPhotoImageManager.cancelImageRequest(requestID) }
        requestID = nil
    }
}

private struct CommonsThumbnail: View {
    let photo: CommonsPhoto
    let isSelected: Bool

    var body: some View {
        AsyncImage(url: photo.thumbURL.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure:
                Color.gray.opacity(0.2).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            default:
                Color.gray.opacity(0.2)
            }
        }
        .thumbnailChrome(isSelected: isSelected)
        .help(label)
        .accessibilityLabel(label)
    }

    private var label: String { photo.displayTitle }
}

private struct PexelsThumbnail: View {
    let photo: PexelsPhoto
    let isSelected: Bool

    var body: some View {
        AsyncImage(url: URL(string: photo.thumbURL)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure:
                Color.gray.opacity(0.2).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            default:
                Color.gray.opacity(0.2)
            }
        }
        .thumbnailChrome(isSelected: isSelected)
        .help(label)
        .accessibilityLabel(label)
    }

    private var label: String { photo.displayTitle }
}

// MARK: - Window chrome (whole-window behind-window material)

/// Full-bleed behind-window material (the same the system uses for sidebars)
/// so the desktop shows through, blurred.
private struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Makes the hosting window non-opaque so the behind-window blur reveals the
/// desktop instead of a solid backing colour. Configures once, as soon as a
/// window is available — not on every SwiftUI render.
private struct WindowAccessor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { context.coordinator.configureIfNeeded(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !context.coordinator.configured else { return }
        DispatchQueue.main.async { context.coordinator.configureIfNeeded(nsView.window) }
    }

    final class Coordinator {
        private(set) var configured = false

        func configureIfNeeded(_ window: NSWindow?) {
            guard !configured, let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // Belt and braces next to NSWindow.allowsAutomaticWindowTabbing:
            // this window can never be tabbed or merged into another.
            window.tabbingMode = .disallowed
            configured = true
        }
    }
}
