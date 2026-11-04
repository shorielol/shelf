import ShelfCore
import SwiftUI

/// Renders a widget's declared options as a compact form.
struct WidgetInspector: View {
    let id: UUID
    let descriptor: WidgetDescriptor
    @Environment(AppModel.self) private var model

    var body: some View {
        let config = model.instance(id)?.config ?? [:]
        Form {
            Section {
                ForEach(Array(descriptor.options.enumerated()), id: \.offset) { _, option in
                    row(option, config: config)
                }
            } header: {
                Label(descriptor.name, systemImage: descriptor.symbol)
                    .font(Theme.Typeface.title(13))
            }
        }
        .formStyle(.grouped)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func row(_ option: WidgetOption, config: WidgetConfig) -> some View {
        switch option {
        case let .choice(key, label, options):
            Picker(label, selection: binding(key, config: config, fallback: options.first?.value ?? "")) {
                ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
            }
        case let .toggle(key, label):
            Toggle(label, isOn: Binding(
                get: { config.bool(key, default: false) ?? false },
                set: { model.updateConfig(id, key: key, value: .bool($0)) }
            ))
        case let .text(key, label, placeholder):
            TextField(label, text: binding(key, config: config, fallback: ""), prompt: Text(placeholder))
        case let .number(key, label, range, step):
            let value = config.double(key, default: range.lowerBound) ?? range.lowerBound
            Stepper(value: Binding(get: { value }, set: { model.updateConfig(id, key: key, value: .number($0)) }), in: range, step: step) {
                LabeledContent(label, value: value.formatted(.number.precision(.fractionLength(step < 1 ? 1 : 0))))
            }
        case let .date(key, label):
            let seconds = config.double(key, default: Date().addingTimeInterval(86_400 * 7).timeIntervalSince1970) ?? 0
            DatePicker(label, selection: Binding(
                get: { Date(timeIntervalSince1970: seconds) },
                set: { model.updateConfig(id, key: key, value: .number($0.timeIntervalSince1970)) }
            ))
        }
    }

    private func binding(_ key: String, config: WidgetConfig, fallback: String) -> Binding<String> {
        Binding(
            get: { config.string(key, default: fallback) ?? fallback },
            set: { model.updateConfig(id, key: key, value: .string($0)) }
        )
    }
}
