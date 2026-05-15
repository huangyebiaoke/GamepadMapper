// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GamepadMapper",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GamepadMapper",
            path: "Sources/GamepadMapper",
            resources: [
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj"),
                .process("Resources/ja.lproj"),
                .process("Resources/ko.lproj"),
                .process("Resources/ru.lproj"),
                .process("Resources/es.lproj"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
