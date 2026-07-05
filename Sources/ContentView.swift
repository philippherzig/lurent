import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HSplitView {
            SourceSidebar()
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 460)
            EditorPane()
                .frame(minWidth: 560)
        }
        .frame(minWidth: 940, minHeight: 640)
    }
}

// MARK: - Sidebar (source picking)

private struct SourceSidebar: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Unsplash durchsuchen…", text: $model.query)
                        .textFieldStyle(.plain)
                        .onSubmit { model.runSearch() }
                    if model.isSearching { ProgressView().controlSize(.small) }
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                Button { openImagePanel() } label: {
                    Label("Eigenes Bild öffnen…", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                if model.mode == .dynamic {
                    Text("Wählt Bild für: \(model.editing.label)")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)

            Divider()

            if let error = model.errorMessage {
                Text(error)
                    .font(.callout).foregroundStyle(.orange)
                    .padding(.horizontal, 12).padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.results) { photo in
                        Thumbnail(photo: photo, isSelected: model.currentLook.photoID == photo.id)
                            .onTapGesture { model.select(photo) }
                    }
                }
                .padding(12)
            }

            Divider()
            HStack {
                Button {
                    openSettings()
                } label: {
                    Label("Einstellungen", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)
                Spacer()
                Link("Unsplash", destination: URL(string: "https://unsplash.com")!)
                    .font(.caption)
            }
            .padding(10)
        }
        .background(.background)
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
        )
        .help(photo.description ?? photo.alt_description ?? "Foto von \(photo.user.name)")
    }
}

// MARK: - Editor (preview + controls + export)

private struct EditorPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PreviewArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            ControlsBar()
        }
        .background(.background)
    }
}

private struct PreviewArea: View {
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
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 12, y: 6)
                    .padding(24)
                    .onDrag { model.makeDragProvider() }
                    .help("Zum Exportieren in den Finder / auf den Schreibtisch ziehen")
                    .overlay(alignment: .bottom) {
                        Label(model.mode == .dynamic
                              ? "Ziehen exportiert das dynamische HEIC"
                              : "Ziehen zum Exportieren",
                              systemImage: "arrow.down.doc")
                            .font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 34)
                    }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 44)).foregroundStyle(.secondary)
                    Text(model.mode == .dynamic
                         ? "Bild für „\(model.editing.label)“ wählen"
                         : "Bild aus Unsplash wählen oder eigenes öffnen")
                        .foregroundStyle(.secondary)
                }
            }

            if model.isLoadingSource { ProgressView().controlSize(.large) }
        }
    }
}

private struct ControlsBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            // Mode + appearance row
            HStack(spacing: 12) {
                Picker("", selection: $model.mode) {
                    ForEach(WallpaperMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)

                if model.mode == .dynamic {
                    Picker("", selection: $model.editing) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)

                    Button {
                        model.copyCurrentSourceToOther()
                    } label: {
                        Label("Quelle für \(model.editing.other.label) übernehmen", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(model.currentLook.source == nil)
                }
                Spacer()
                Text(model.pixelSizeLabel)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }

            // Attribution + status
            HStack {
                if let attribution = model.currentLook.attribution {
                    if let link = model.currentLook.attributionURL, let url = URL(string: link) {
                        Link(attribution, destination: url).font(.caption)
                    } else {
                        Text(attribution).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let status = model.statusMessage {
                    Label(status, systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.green)
                }
            }

            // Resolution + sliders
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Auflösung", selection: $model.preset) {
                        ForEach(ResolutionPreset.all) { Text($0.name).tag($0) }
                    }
                    if model.preset.isCustom {
                        HStack {
                            TextField("Breite", value: $model.customWidth, format: .number).frame(width: 78)
                            Text("×").foregroundStyle(.secondary)
                            TextField("Höhe", value: $model.customHeight, format: .number).frame(width: 78)
                            Text("px").foregroundStyle(.secondary)
                        }
                        .textFieldStyle(.roundedBorder)
                    }
                }
                .frame(maxWidth: 280, alignment: .leading)

                VStack(spacing: 4) {
                    labeledSlider("Blur", model.bind(\.blur), 0...100)
                    labeledSlider("Helligkeit", model.bind(\.brightness), -0.3...0.3)
                    labeledSlider("Sättigung", model.bind(\.saturation), 0...2)
                    labeledSlider("Kontrast", model.bind(\.contrast), 0.8...1.3)
                    labeledSlider("Körnung", model.bind(\.dither), 0...3)
                }
                .frame(maxWidth: .infinity)
            }

            // Actions
            HStack {
                Button("Zurücksetzen") { model.resetCurrentLook() }
                Spacer()
                Button { model.setAsDesktop() } label: {
                    Label("Als Schreibtisch setzen", systemImage: "menubar.dock.rectangle")
                }
                .disabled(!model.canExport)
                Button { model.exportWithPanel() } label: {
                    Label(model.mode == .dynamic ? "Dynamisch exportieren…" : "Exportieren…",
                          systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canExport)
            }
        }
        .padding(16)
    }

    private func labeledSlider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.callout).frame(width: 78, alignment: .leading)
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
