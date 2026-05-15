import SwiftUI

struct MappingEditorView: View {
    @Binding var profile: MappingProfile
    @Environment(\.dismiss) private var dismiss
    @State private var selectedEntry: MappingEntry?
    @State private var sensitivity: Float = 15.0
    @Bindable private var languageManager = LanguageManager.shared

    var body: some View {
        let _ = languageManager.currentLanguage
        VStack(spacing: 0) {
            Text(String(format: "edit_mappings_title".localized, profile.name))
                .font(.headline)
                .padding()

            HStack {
                Text(String(format: "sensitivity_label".localized, Int(sensitivity)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Slider(value: $sensitivity, in: 1...50, step: 1)
                    .onChange(of: sensitivity) {
                        profile.mouseSensitivity = Double(sensitivity)
                    }
            }
            .padding(.horizontal)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(groupedEntries.keys.sorted(), id: \.self) { category in
                        Section(header: sectionHeader(category)) {
                            ForEach(groupedEntries[category] ?? []) { entry in
                                mappingRow(entry)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }

            Divider()

            HStack {
                Button("add_mapping".localized) {
                    addMapping()
                }
                .controlSize(.regular)

                Spacer()

                Button("done".localized) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            sensitivity = Float(profile.mouseSensitivity)
        }
    }

    private var groupedEntries: [String: [MappingEntry]] {
        Dictionary(grouping: profile.entries) { $0.source.category }
    }

    private func sectionHeader(_ category: String) -> some View {
        Text(category)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    private func mappingRow(_ entry: MappingEntry) -> some View {
        HStack {
            Text(entry.source.displayName)
                .font(.subheadline)
                .frame(width: 120, alignment: .leading)

            if entry.source.isAnalog {
                Picker("", selection: bindingForDirection(entry)) {
                    Text("direction_positive".localized).tag(AnalogDirection.positive)
                    Text("direction_negative".localized).tag(AnalogDirection.negative)
                }
                .frame(width: 90)
                .labelsHidden()
            }

            Spacer()

            Text("→")
                .foregroundStyle(.secondary)

            Picker("", selection: bindingForTarget(entry)) {
                Text("target_none".localized).tag(Optional<MappingTarget>.none)
                ForEach(KeyMappings.allKeys, id: \.code) { key in
                    Text(key.name).tag(Optional<MappingTarget>.some(.key(key.code)))
                }
                Divider()
                ForEach(MouseButton.allCases) { btn in
                    Text(btn.displayName).tag(Optional<MappingTarget>.some(.mouseButton(btn)))
                }
                ForEach(MouseButton.allCases) { btn in
                    Text(btn.dragDisplayName).tag(Optional<MappingTarget>.some(.mouseDrag(btn)))
                }
                Text("target_mouse_move".localized).tag(Optional<MappingTarget>.some(MappingTarget.mouseMove))
            }
            .frame(width: 140)
            .labelsHidden()

            Button {
                removeMapping(entry)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 4))
        .opacity(entry.target == nil ? 0.45 : 1)
        .padding(.bottom, 2)
    }

    private func bindingForDirection(_ entry: MappingEntry) -> Binding<AnalogDirection> {
        Binding(
            get: { entry.direction },
            set: { newDir in
                if let index = profile.entries.firstIndex(where: { $0.id == entry.id }) {
                    profile.entries[index].direction = newDir
                }
            }
        )
    }

    private func bindingForTarget(_ entry: MappingEntry) -> Binding<MappingTarget?> {
        Binding(
            get: { entry.target },
            set: { newTarget in
                guard let index = profile.entries.firstIndex(where: { $0.id == entry.id }) else { return }
                profile.entries[index].target = newTarget
            }
        )
    }

    private func addMapping() {
        let entry = MappingEntry(
            source: .buttonA,
            target: .key(KeyMappings.space)
        )
        profile.entries.append(entry)
    }

    private func removeMapping(_ entry: MappingEntry) {
        profile.entries.removeAll { $0.id == entry.id }
    }
}
