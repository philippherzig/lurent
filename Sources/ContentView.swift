import SwiftUI
import AppKit
import Photos
import ImageIO
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var showInspector = true

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    var body: some View {
        NavigationSplitView {
            SourceSidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } content: {
            SourceContent()
                .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } detail: {
            PreviewDetail()
                .toolbar { detailToolbar }
                .inspector(isPresented: $showInspector) {
                    InspectorForm()
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
                }
        }
        .alert("Fehler", isPresented: errorBinding) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                showInspector.toggle()
            } label: {
                Label("Einstellungen ein-/ausblenden", systemImage: "slider.horizontal.3")
            }
            .help("Einstellungen ein-/ausblenden")
        }

        ToolbarSpacer(.flexible, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
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
                Label("Exportieren", systemImage: "square.and.arrow.up")
            }
            .disabled(!model.canExport)
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
            Button {
                model.setAsDesktop()
            } label: {
                Label("Als Schreibtisch setzen", systemImage: "macwindow.on.rectangle")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.glassProminent)
            .disabled(!model.canExport)
        }
    }
}

// MARK: - Sidebar (source picking)

private struct SourceSidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List(selection: $model.selectedSource) {
            Section("Quellen") {
                Label("Unsplash", systemImage: "magnifyingglass").tag(ImageSource.unsplash)
                Label("Dateien", systemImage: "folder").tag(ImageSource.files)
            }
            Section("Fotos") {
                photosSection
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var photosSection: some View {
        switch model.photosAuthStatus {
        case .notDetermined:
            Button {
                model.requestPhotosAccess()
            } label: {
                Label("Fotos-Mediathek verbinden…", systemImage: "photo.badge.plus")
            }
        case .denied, .restricted:
            Text("Kein Fotos-Zugriff")
                .foregroundStyle(.secondary)
                .help("Systemeinstellungen → Datenschutz & Sicherheit → Fotos: Zugriff für Lurent erlauben.")
        case .authorized, .limited:
            ForEach(model.photoAlbums) { album in
                Label(album.title, systemImage: "rectangle.stack")
                    .tag(ImageSource.album(id: album.id, title: album.title))
            }
        @unknown default:
            EmptyView()
        }
    }
}

// MARK: - Content column (image browser per source)

private struct SourceContent: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        switch model.selectedSource {
        case .files:
            FilesBrowser()
        case .album(let id, let title):
            AlbumBrowser(albumID: id, albumTitle: title)
        case .unsplash, .none:
            UnsplashBrowser()
        }
    }
}

/// Slim caption shown in every browser, reminding which appearance a pick lands in.
private struct SourceCaption: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Text("Bild wird für „\(model.editing.label)“ übernommen")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.top, 10)
    }
}

private let browserColumns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

private struct UnsplashBrowser: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SourceCaption()

            ScrollView {
                LazyVGrid(columns: browserColumns, spacing: 8) {
                    ForEach(model.results) { photo in
                        Thumbnail(photo: photo, isSelected: model.currentLook.photoID == photo.id)
                            .onTapGesture { model.select(photo) }
                    }
                }
                .padding(12)
            }

            Divider()

            HStack {
                Spacer()
                Link("Fotos: Unsplash", destination: URL(string: "https://unsplash.com")!)
                    .font(.caption)
            }
            .padding(12)
        }
        .searchable(text: $model.query, prompt: "Unsplash durchsuchen")
        .onSubmit(of: .search) { model.runSearch() }
        .overlay(alignment: .top) {
            if model.isSearching {
                ProgressView().controlSize(.small).padding(.top, 6)
            }
        }
        .background(.background)
    }
}

private struct FilesBrowser: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SourceCaption()

            if model.recentFiles.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Dateien", systemImage: "folder")
                } description: {
                    Text("Öffne eine Bilddatei oder ziehe sie hierher.")
                } actions: {
                    Button("Datei öffnen…") { openImagePanel() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: browserColumns, spacing: 8) {
                        ForEach(model.recentFiles, id: \.path) { url in
                            LocalFileThumbnail(url: url, isSelected: model.currentLook.photoID == url.path)
                                .onTapGesture { model.openLocalImage(url: url) }
                        }
                    }
                    .padding(12)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Datei öffnen…") { openImagePanel() }
            }
            .padding(12)
        }
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls where isImageFile(url) { model.openLocalImage(url: url) }
        }
        .background(.background)
    }

    private func isImageFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .image) ?? false
    }

    private func openImagePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            model.openLocalImage(url: url)
        }
    }
}

private struct AlbumBrowser: View {
    @EnvironmentObject var model: AppModel
    let albumID: String
    let albumTitle: String

    var body: some View {
        VStack(spacing: 0) {
            SourceCaption()

            ScrollView {
                LazyVGrid(columns: browserColumns, spacing: 8) {
                    ForEach(model.albumAssets, id: \.localIdentifier) { asset in
                        PhotoAssetThumbnail(asset: asset, isSelected: model.currentLook.photoID == asset.localIdentifier)
                            .onTapGesture { model.selectAlbumAsset(asset) }
                    }
                }
                .padding(12)
            }

            if model.albumAssets.isEmpty {
                ContentUnavailableView {
                    Label("Keine Fotos", systemImage: "photo.on.rectangle")
                } description: {
                    Text("Dieses Album enthält keine Bilder.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.background)
        .task(id: albumID) {
            model.loadAlbumAssets(albumID: albumID)
        }
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
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
        )
        .help(url.lastPathComponent)
        .task(id: url) {
            thumbnail = await Self.loadThumbnail(url: url)
        }
    }

    private static func loadThumbnail(url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 320,
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
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
        )
        .onAppear { requestThumbnail() }
        .onDisappear { cancelRequest() }
    }

    private func requestThumbnail() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        requestID = sharedPhotoImageManager.requestImage(
            for: asset, targetSize: CGSize(width: 320, height: 320),
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
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
        )
        .help(photo.description ?? photo.alt_description ?? "Foto von \(photo.user.name)")
    }
}

// MARK: - Detail (preview canvas)

private struct PreviewDetail: View {
    @EnvironmentObject var model: AppModel

    private var aspect: CGFloat {
        let s = model.pixelSize
        return CGFloat(s.width) / CGFloat(max(1, s.height))
    }

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)

            if let preview = model.preview {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(aspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 16, y: 8)
                    .padding(32)
                    .onDrag { model.makeDragProvider() }
                    .help("Zum Exportieren in den Finder / auf den Schreibtisch ziehen")
                    .overlay(alignment: .bottom) {
                        Label("Ziehen exportiert das dynamische HEIC", systemImage: "arrow.down.doc")
                            .font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .glassEffect(.regular, in: Capsule())
                            .padding(.bottom, 44)
                    }
            } else {
                ContentUnavailableView {
                    Label("Kein Bild für „\(model.editing.label)“", systemImage: "photo.badge.plus")
                } description: {
                    Text("Wähle links ein Unsplash-Foto, ein Bild aus Fotos oder eine Datei.")
                } actions: {
                    EmptyView()
                }
            }

            if model.isLoadingSource { ProgressView().controlSize(.large) }

            VStack {
                AppearanceSwitcher()
                    .padding(.top, 16)
                Spacer()
                if model.statusMessage != nil {
                    StatusCapsule()
                        .padding(.bottom, 20)
                }
            }
        }
        .animation(.spring(duration: 0.3), value: model.statusMessage)
    }
}

/// Floating Hell/Dunkel switch + "auf andere Ansicht übernehmen" button.
private struct AppearanceSwitcher: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $model.editing) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
                .glassEffect(.regular.interactive(), in: Capsule())

                Button {
                    model.copyCurrentLookToOther()
                } label: {
                    Image(systemName: "square.on.square")
                }
                .buttonStyle(.plain)
                .padding(8)
                .glassEffect(.regular.interactive(), in: Circle())
                .disabled(!model.lookHasContent(model.currentLook))
                .help("Auf „\(model.editing.other.label)“ übernehmen")
            }
        }
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

// MARK: - Inspector (style + parameters + output)

private struct InspectorForm: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Stil") {
                Picker("Stil", selection: model.bind(\.style)) {
                    ForEach(WallpaperStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            switch model.currentLook.style {
            case .blur: blurSection
            case .flow: flowSection
            case .mirror: mirrorSection
            }

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
                Text(model.pixelSizeLabel)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Zurücksetzen") { model.resetCurrentLook() }
                    Spacer()
                    if let attribution = model.currentLook.attribution {
                        if let link = model.currentLook.attributionURL, let url = URL(string: link) {
                            Link(attribution, destination: url).font(.caption)
                        } else {
                            Text(attribution).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var blurSection: some View {
        Section("Blur") {
            labeledSlider("Blur", model.bind(\.blur), 0...100)
            labeledSlider("Helligkeit", model.bind(\.brightness), -0.3...0.3)
            labeledSlider("Sättigung", model.bind(\.saturation), 0...2)
            labeledSlider("Kontrast", model.bind(\.contrast), 0.8...1.3)
            labeledSlider("Körnung", model.bind(\.dither), 0...1)
        }
    }

    private var mirrorSection: some View {
        Section("Spiegel") {
            labeledSlider("Blur", model.bind(\.blur), 0...100)
            labeledSlider("Spiegel-Linie", model.bind(\.mirrorLine), 0.15...0.85)
            labeledSlider("Amplitude", model.bind(\.mirrorAmplitude), 0...0.15)
            labeledSlider("Frequenz", model.bind(\.mirrorFrequency), 0.3...3)
            labeledSlider("Kantenschärfe", model.bind(\.mirrorHardness), 0...1)
            labeledSlider("Tiefe", model.bind(\.mirrorDepth), 0...0.8)
            labeledSlider("Seiten-Fade", model.bind(\.mirrorSideFade), 0...1)
            labeledSlider("Körnung", model.bind(\.dither), 0...1)
        }
    }

    private var flowSection: some View {
        Section("Flow") {
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

            Button { model.reloadPaletteFromPhoto() } label: {
                Label("Aus Foto", systemImage: "eyedropper")
            }
            .disabled(model.currentLook.source == nil)

            labeledSlider("Amplitude", model.bind(\.flowAmplitude), 0...0.25)
            labeledSlider("Frequenz", model.bind(\.flowFrequency), 0.3...3)
            labeledSlider("Kantenschärfe", model.bind(\.flowSharpness), 0...1)
            labeledSlider("Rand-Weichheit", model.bind(\.flowEdgeSoftness), 0...1)
            labeledSlider("Variante", model.bind(\.flowPhase), 0...6.283)
            labeledSlider("Körnung", model.bind(\.dither), 0...1)
        }
    }

    private func labeledSlider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            Slider(value: value, in: range)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                TextField("Access-Key (optional)", text: $model.accessKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 360)
            } header: {
                Text("Unsplash Access-Key")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ein Key ist bereits hinterlegt (gemeinsames Ratenlimit). Für ein eigenes Limit unter unsplash.com/developers einen Key erstellen und hier einsetzen.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("unsplash.com/developers öffnen",
                         destination: URL(string: "https://unsplash.com/developers")!)
                        .font(.caption)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
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
