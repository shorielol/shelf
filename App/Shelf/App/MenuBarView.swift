import ServiceManagement
import ShelfCore
import SwiftUI

/// The menu bar panel: now playing at a glance, then the wall's controls.
struct MenuBarView: View {
    let replayOnboarding: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Text("Shelf").font(Theme.Typeface.display(20)).displayTracking(20)
                Spacer()
                Text("\(model.layout.widgets.count) widgets").font(Theme.Typeface.caption).foregroundStyle(Theme.textSecondary)
            }
            if let track = model.nowPlaying.track {
                HStack(spacing: 10) {
                    ArtworkView(image: model.nowPlaying.artwork, cornerRadius: 8).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(Theme.Typeface.title(13)).lineLimit(1)
                        Text(track.artist).font(Theme.Typeface.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    TransportControls(size: 11, spacing: 2)
                }
                .padding(10)
                .glass(cornerRadius: 14)
            }
            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 8) {
                    row("Edit Widgets", symbol: "square.and.pencil", tint: Theme.ember) { model.isEditing = true }
                    row("Add Widget…", symbol: "plus.square.on.square") { model.isEditing = true; model.showingGallery = true }
                    row(model.widgetsHidden ? "Show Widgets" : "Hide Widgets", symbol: model.widgetsHidden ? "eye" : "eye.slash") { model.widgetsHidden.toggle() }
                }
            }
            Divider().opacity(0.4)
            HStack {
                Button("Welcome Tour", action: replayOnboarding)
                Spacer()
                Button("Settings…") {
                    NSApp.activate()
                    openSettings()
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(Theme.Typeface.caption)
        }
        .padding(Theme.Space.m)
        .frame(width: 320)
    }

    private func row(_ title: String, symbol: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Theme.Typeface.title(13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glass(cornerRadius: 12, tint: tint, interactive: true)
    }
}

struct SettingsView: View {
    let replayOnboarding: () -> Void
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var sounds = Sounds.shared.isEnabled

    var body: some View {
        @Bindable var model = model
        @Bindable var lyrics = model.lyrics
        Form {
            Section("General") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Snap widgets to the grid", isOn: $model.snapToGrid)
                Toggle("Interface sounds", isOn: $sounds)
                    .onChange(of: sounds) { _, on in Sounds.shared.isEnabled = on }
            }
            Section("Lyrics") {
                LabeledContent("Timing") {
                    Stepper(value: $lyrics.offset, in: -3...3, step: 0.1) {
                        Text(lyrics.offset == 0 ? "In sync" : String(format: "%+.1f s", lyrics.offset)).monospacedDigit()
                    }
                }
                Text("Lyrics come from LRCLIB, a free community database.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Layout") {
                Button("Edit Widgets") { model.isEditing = true }
                Button("Welcome Tour", action: replayOnboarding)
                Button("Remove All Widgets", role: .destructive) { model.replaceAll(with: []) }
            }
            Section("Credits") {
                Text("Weather data by Open-Meteo (CC BY 4.0). Lyrics by LRCLIB. Departure Mono by Helena Zhang (SIL OFL).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
