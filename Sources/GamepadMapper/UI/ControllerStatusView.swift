import AppKit
import SwiftUI

struct ControllerStatusView: View {
    let controller: GameControllerManager

    private var tertiaryColor: Color { Color(nsColor: .tertiaryLabelColor) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                // Left side: D-Pad
                dpadView
                Spacer()
                // Center: Sticks
                stickView(title: "left_stick".localized, x: controller.leftStickX, y: controller.leftStickY)
                Spacer()
                stickView(title: "right_stick".localized, x: controller.rightStickX, y: controller.rightStickY)
                Spacer()
                // Right: Face buttons
                faceButtonsView
            }

            HStack(spacing: 20) {
                triggerView("left_trigger".localized, value: controller.leftTrigger)
                buttonIndicator("left_shoulder".localized, active: controller.leftShoulder > 0.5)
                Spacer()
                buttonIndicator("left_thumbstick_button".localized, active: controller.leftThumbstickButton > 0.5)
                buttonIndicator("right_thumbstick_button".localized, active: controller.rightThumbstickButton > 0.5)
                Spacer()
                buttonIndicator("right_shoulder".localized, active: controller.rightShoulder > 0.5)
                triggerView("right_trigger".localized, value: controller.rightTrigger)
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var dpadView: some View {
        VStack(spacing: 2) {
            buttonIndicator("↑", active: controller.dpadUp > 0.5)
            HStack(spacing: 2) {
                buttonIndicator("←", active: controller.dpadLeft > 0.5)
                buttonIndicator("↓", active: controller.dpadDown > 0.5)
                buttonIndicator("→", active: controller.dpadRight > 0.5)
            }
        }
    }

    private func stickView(title: String, x: Float, y: Float) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            ZStack {
                Circle()
                    .stroke(tertiaryColor, lineWidth: 1)
                    .frame(width: 40, height: 40)
                Circle()
                    .fill(x != 0 || y != 0 ? .blue : .secondary)
                    .frame(width: 8, height: 8)
                    .offset(x: CGFloat(x) * 16, y: CGFloat(-y) * 16)
            }
        }
    }

    private var faceButtonsView: some View {
        VStack(spacing: 2) {
            buttonIndicator("Y", active: controller.buttonY > 0.5, color: .yellow)
            HStack(spacing: 2) {
                buttonIndicator("X", active: controller.buttonX > 0.5, color: .blue)
                buttonIndicator("B", active: controller.buttonB > 0.5, color: .red)
                buttonIndicator("A", active: controller.buttonA > 0.5, color: .green)
            }
        }
    }

    private func buttonIndicator(_ label: String, active: Bool, color: Color = .accentColor) -> some View {
        Text(label)
            .font(.caption2.bold())
            .frame(width: 24, height: 20)
            .background(active ? color.opacity(0.8) : tertiaryColor, in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(active ? .white : .secondary)
    }

    private func triggerView(_ label: String, value: Float) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tertiaryColor)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(value > 0 ? .blue : .clear)
                        .frame(height: geo.size.height * CGFloat(value))
                }
            }
            .frame(width: 20, height: 40)
            Text("\(Int(value * 100))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
