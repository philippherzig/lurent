import SwiftUI
import AppKit
import Photos
import ImageIO
import UniformTypeIdentifiers

private let thumbSize: CGFloat = 52

// MARK: - Root (two-pane: preview | scrollable inspector, on one blurred surface)

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    var body: some View {
        HStack(spacing: 0) {
            PreviewPane()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            InspectorPane()
                .frame(width: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectView().ignoresSafeArea())
        .background(WindowAccessor())
        .alert("Fehler", isPresented: errorBinding) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - Preview pane (left)

private struct PreviewPane: View {
    @EnvironmentObject var model: AppModel

    private var aspect: CGFloat {
        let s = model.pixelSize
        return CGFloat(s.width) / CGFloat(max(1, s.height))
    }

    var body: some View {
        ZStack {
            if let preview = model.preview {
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
                    Label("Kein Bild für „\(model.editing.label)“", systemImage: "photo.badge.plus")
                } description: {
                    Text("Wähle rechts ein Unsplash-Foto, ein Bild aus Fotos oder eine Datei.")
                }
            }

            if model.isLoadingSource { ProgressView().controlSize(.large) }

            VStack {
                AppearanceSwitcher()
                    .padding(.top, 18)
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
                .help("Auf „\(model.editing.other.label)“ übernehmen")
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
                BaseImageSection()
                EffectSection()
                OutputSection()
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            ActionBar()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls where isImageFile(url) { model.openLocalImage(url: url) }
            return true
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
        case .unsplash:
            HStack(spacing: 8) {
                NativeSearchField(text: $model.query, placeholder: "Unsplash durchsuchen") {
                    model.runSearch()
                }
                .frame(height: 24)
                if model.isSearching { ProgressView().controlSize(.small) }
            }
            if !model.results.isEmpty {
                ThumbGrid {
                    ForEach(model.results) { photo in
                        Thumbnail(photo: photo, isSelected: model.currentLook.photoID == photo.id)
                            .onTapGesture { model.select(photo) }
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
                        LocalFileThumbnail(url: url, isSelected: model.currentLook.photoID == url.path)
                            .onTapGesture { model.openLocalImage(url: url) }
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
                                PhotoAssetThumbnail(asset: asset, isSelected: model.currentLook.photoID == asset.localIdentifier)
                                    .onTapGesture { model.selectAlbumAsset(asset) }
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

        case .mirror:
            slider("Blur", model.bind(\.blur), 0...100)
            slider("Spiegel-Linie", model.bind(\.mirrorLine), 0.15...0.85)
            slider("Amplitude", model.bind(\.mirrorAmplitude), 0...0.15)
            slider("Frequenz", model.bind(\.mirrorFrequency), 0.3...3)
            slider("Kantenschärfe", model.bind(\.mirrorHardness), 0...1)
            slider("Tiefe", model.bind(\.mirrorDepth), 0...0.8)
            slider("Seiten-Fade", model.bind(\.mirrorSideFade), 0...1)

        case .flow:
            Picker("Farben", selection: model.bind(\.flowBands)) {
                Text("2 Farben").tag(2)
                Text("3 Farben").tag(3)
            }
            .pickerStyle(.segmented)

            HStack {
                ColorPicker("Farbe 1", selection: model.bind(\.flowColor0), supportsOpacity: false)
                ColorPicker("Farbe 2", selection: model.bind(\.flowColor1), supportsOpacity: false)
                if model.currentLook.flowBands >= 3 {
                    ColorPicker("Farbe 3", selection: model.bind(\.flowColor2), supportsOpacity: false)
                }
            }
            .labelsHidden()

            Button {
                model.reloadPaletteFromPhoto()
            } label: {
                Label("Aus Foto", systemImage: "eyedropper")
            }
            .disabled(model.currentLook.source == nil)

            slider("Amplitude", model.bind(\.flowAmplitude), 0...0.25)
            slider("Frequenz", model.bind(\.flowFrequency), 0.3...3)
            slider("Kantenschärfe", model.bind(\.flowSharpness), 0...1)
            slider("Rand-Weichheit", model.bind(\.flowEdgeSoftness), 0...1)
            slider("Variante", model.bind(\.flowPhase), 0...6.283)

        case .liquid:
            Picker("Farben", selection: model.bind(\.liquidCount)) {
                Text("3").tag(3); Text("4").tag(4); Text("5").tag(5)
            }
            .pickerStyle(.segmented)

            HStack {
                ColorPicker("Farbe 1", selection: model.bind(\.liquidColor0), supportsOpacity: false)
                ColorPicker("Farbe 2", selection: model.bind(\.liquidColor1), supportsOpacity: false)
                ColorPicker("Farbe 3", selection: model.bind(\.liquidColor2), supportsOpacity: false)
                if model.currentLook.liquidCount >= 4 {
                    ColorPicker("Farbe 4", selection: model.bind(\.liquidColor3), supportsOpacity: false)
                }
                if model.currentLook.liquidCount >= 5 {
                    ColorPicker("Farbe 5", selection: model.bind(\.liquidColor4), supportsOpacity: false)
                }
            }
            .labelsHidden()

            Button {
                model.reloadLiquidPaletteFromPhoto()
            } label: {
                Label("Aus Foto", systemImage: "eyedropper")
            }
            .disabled(model.currentLook.source == nil)

            slider("Frame", model.bind(\.liquidTime), 0...30)
            slider("Variante", model.bind(\.liquidSeed), 0...12)
            slider("Skalierung", model.bind(\.liquidScale), 0...2.5)
            slider("Turbulenz", model.bind(\.liquidTurb), 0...1.6)
            slider("Wellen", model.bind(\.liquidWave), 0.3...3)
            slider("Tonwert", model.bind(\.liquidBias), -1...1)
        }

        // Colour grade + grain — shared by every style.
        slider("Helligkeit", model.bind(\.brightness), -0.3...0.3)
        slider("Sättigung", model.bind(\.saturation), 0...2)
        slider("Kontrast", model.bind(\.contrast), 0.8...1.3)
        slider("Körnung", model.bind(\.dither), 0...1)
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            Slider(value: value, in: range)
        }
    }
}

// MARK: - Output section (resolution)

private struct OutputSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section("Ausgabe") {
            Picker("Auflösung", selection: $model.preset) {
                ForEach(ResolutionPreset.all) { Text($0.name).tag($0) }
            }

            if model.preset.isCustom {
                HStack {
                    TextField("Breite", value: $model.customWidth, format: .number)
                    Text("×").foregroundStyle(.secondary)
                    TextField("Höhe", value: $model.customHeight, format: .number)
                    Text("px").foregroundStyle(.secondary)
                }
                .textFieldStyle(.roundedBorder)
            }
        }
    }
}

// MARK: - Action bar (pinned bottom): export menu + set-as-desktop

private struct ActionBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Button {
                    model.saveToPhotosLibrary()
                } label: {
                    Label("In Fotos sichern", systemImage: "photo.stack")
                }
                Button {
                    model.exportWithPanel()
                } label: {
                    Label("Als HEIC exportieren…", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("s", modifiers: .command)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.glass)
            .controlSize(.large)
            .fixedSize()
            .help("Exportieren")
            .disabled(!model.canExport)

            Button {
                model.setAsDesktop()
            } label: {
                Label("Als Schreibtisch setzen", systemImage: "macwindow.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!model.canExport)
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
            thumbnail = await Self.loadThumbnail(url: url)
        }
    }

    private static func loadThumbnail(url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 240,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
                return nil
            }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
    }
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

private struct Thumbnail: View {
    let photo: UnsplashPhoto
    let isSelected: Bool

    var body: some View {
        AsyncImage(url: URL(string: photo.urls.small)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure:
                Color.gray.opacity(0.2).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            default:
                Rectangle().fill(Color(hex: photo.color) ?? .gray.opacity(0.2))
            }
        }
        .thumbnailChrome(isSelected: isSelected)
        .help(photo.description ?? photo.alt_description ?? "Foto von \(photo.user.name)")
    }
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
            configured = true
        }
    }
}

// MARK: - Helpers

extension Color {
    init?(hex: String?) {
        guard var hex else { return nil }
        hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let v = Int(hex, radix: 16) else { return nil }
        self = Color(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
