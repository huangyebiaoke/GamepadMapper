import SwiftUI

struct MappingEditorView: View {
    @Binding var profile: MappingProfile
    var onClose: (() -> Void)?
    @State private var selectedEntry: MappingEntry?
    @State private var sensitivity: Float = 15.0
    @State private var boundaryEnabled = false
    @State private var boundaryRadius: Double = 100
    @State private var boundaryCenterText = ""
    @State private var overlayWindow: DragBoundaryOverlayWindow?
    @Bindable private var languageManager = LanguageManager.shared

    var body: some View {
        let _ = languageManager.currentLanguage
        VStack(spacing: 0) {
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

            // Drag Boundary Section
            VStack(spacing: 8) {
                HStack {
                    Toggle("drag_boundary_title".localized, isOn: $boundaryEnabled)
                        .font(.subheadline)
                        .onChange(of: boundaryEnabled) {
                            updateBoundaryFromState()
                        }
                    Spacer()
                }

                if boundaryEnabled {
                    HStack {
                        Text("drag_boundary_center".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(boundaryCenterText)
                            .font(.caption)
                            .monospaced()
                        Spacer()
                        Button {
                            centerBoundary()
                        } label: {
                            Image(systemName: "scope")
                        }
                        .controlSize(.small)
                        .help("drag_boundary_center_screen".localized)
                        Button("drag_boundary_set_center".localized) {
                            showOverlay()
                        }
                        .controlSize(.small)
                    }

                    HStack {
                        Text(String(format: "drag_boundary_radius".localized, Int(boundaryRadius)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $boundaryRadius, in: 20...300, step: 10)
                            .onChange(of: boundaryRadius) {
                                updateBoundaryFromState()
                                overlayWindow?.updateRadius(boundaryRadius)
                            }
                    }
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
                Menu("add_mapping".localized) {
                    ForEach(sourceCategories, id: \.self) { category in
                        Menu(category) {
                            ForEach(ControllerElement.allCases.filter { $0.category == category }, id: \.self) { source in
                                Button(source.displayName) {
                                    addMapping(source: source)
                                }
                            }
                        }
                    }
                }
                .controlSize(.regular)

                Spacer()

                Button("done".localized) {
                    onClose?()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            sensitivity = Float(profile.mouseSensitivity)
            if let b = profile.dragBoundary {
                boundaryEnabled = true
                boundaryRadius = b.radius
                boundaryCenterText = "(\(Int(b.centerX)), \(Int(b.centerY)))"
            } else {
                boundaryEnabled = false
                boundaryCenterText = "drag_boundary_not_set".localized
            }
        }
        .onDisappear {
            overlayWindow?.close()
            overlayWindow = nil
        }
    }

    private var groupedEntries: [String: [MappingEntry]] {
        Dictionary(grouping: profile.entries) { $0.source.category }
    }

    private var sourceCategories: [String] {
        ["category_dpad", "category_face_buttons", "category_shoulder", "category_triggers", "category_left_stick", "category_right_stick"].map(\.localized)
    }

    private func sectionHeader(_ category: String) -> some View {
        Text(category)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    private func mappingRow(_ entry: MappingEntry) -> some View {
        HStack(spacing: 6) {
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
            .frame(width: 130)
            .labelsHidden()

            // Combo target chips
            ForEach(0..<entry.comboTargets.count, id: \.self) { index in
                if index < entry.comboTargets.count {
                    comboChip(entry: entry, index: index)
                }
            }

            // Combo add button
            Menu {
                comboMenuContent(entry: entry)
            } label: {
                Image(systemName: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .disabled(entry.comboTargets.count >= 2)
            .help("add_combo".localized)

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

    private func comboChip(entry: MappingEntry, index: Int) -> some View {
        let target = entry.comboTargets[index]
        return HStack(spacing: 2) {
            Text(target.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button {
                removeComboTarget(entry: entry, index: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary, in: Capsule())
    }

    private func comboMenuContent(entry: MappingEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(KeyMappings.allKeys, id: \.code) { key in
                Button(key.name) {
                    addComboTarget(entry: entry, target: .key(key.code))
                }
            }
            Divider()
            ForEach(MouseButton.allCases) { btn in
                Button(btn.displayName) {
                    addComboTarget(entry: entry, target: .mouseButton(btn))
                }
            }
            ForEach(MouseButton.allCases) { btn in
                Button(btn.dragDisplayName) {
                    addComboTarget(entry: entry, target: .mouseDrag(btn))
                }
            }
        }
        .padding(4)
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

    private func addComboTarget(entry: MappingEntry, target: MappingTarget) {
        if case .mouseMove = target { return } // mouseMove is not a valid combo target
        guard let index = profile.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        if let mainTarget = profile.entries[index].target, target == mainTarget { return }
        guard !profile.entries[index].comboTargets.contains(target) else { return }
        profile.entries[index].comboTargets.append(target)
    }

    private func removeComboTarget(entry: MappingEntry, index: Int) {
        guard let entryIndex = profile.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let comboCount = profile.entries[entryIndex].comboTargets.count
        guard index >= 0, index < comboCount else { return }
        profile.entries[entryIndex].comboTargets.remove(at: index)
    }

    private func addMapping(source: ControllerElement) {
        let entry = MappingEntry(
            source: source,
            target: nil
        )
        profile.entries.append(entry)
    }

    private func removeMapping(_ entry: MappingEntry) {
        profile.entries.removeAll { $0.id == entry.id }
    }

    private func centerBoundary() {
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let centerX = screen.width / 2
        let centerY = screen.height / 2

        if profile.dragBoundary == nil {
            profile.dragBoundary = DragBoundary(centerX: centerX, centerY: centerY, radius: boundaryRadius)
        } else {
            profile.dragBoundary?.centerX = centerX
            profile.dragBoundary?.centerY = centerY
        }
        boundaryCenterText = "(\(Int(centerX)), \(Int(centerY)))"
        overlayWindow?.updateCenter(CGPoint(x: centerX, y: centerY))
    }

    private func showOverlay() {
        // Close any existing overlay first
        overlayWindow?.close()

        let initialCenter: CGPoint
        if let existing = profile.dragBoundary {
            initialCenter = CGPoint(x: existing.centerX, y: existing.centerY)
        } else {
            // Default to center of screen
            let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
            initialCenter = CGPoint(x: screen.width / 2, y: screen.height / 2)
        }

        let overlay = DragBoundaryOverlayWindow(initialCenter: initialCenter, radius: boundaryRadius)
        overlay.onPositionChanged = { center in
            boundaryCenterText = "(\(Int(center.x)), \(Int(center.y)))"
        }
        overlay.onRadiusChanged = { newRadius in
            boundaryRadius = newRadius
            updateBoundaryFromState()
        }
        overlay.onClose = { center in
            let flippedY = center.y
            if profile.dragBoundary == nil {
                profile.dragBoundary = DragBoundary(centerX: center.x, centerY: flippedY, radius: boundaryRadius)
            } else {
                profile.dragBoundary?.centerX = center.x
                profile.dragBoundary?.centerY = flippedY
                profile.dragBoundary?.radius = boundaryRadius
            }
            boundaryCenterText = "(\(Int(center.x)), \(Int(center.y)))"
            overlayWindow = nil
        }
        overlayWindow = overlay
        overlay.makeKeyAndOrderFront(nil)
    }

    private func updateBoundaryFromState() {
        if boundaryEnabled {
            if let existing = profile.dragBoundary {
                profile.dragBoundary = DragBoundary(
                    centerX: existing.centerX,
                    centerY: existing.centerY,
                    radius: boundaryRadius
                )
            } else {
                // Not yet set — show placeholder
                boundaryCenterText = "drag_boundary_not_set".localized
            }
        } else {
            profile.dragBoundary = nil
        }
    }
}
