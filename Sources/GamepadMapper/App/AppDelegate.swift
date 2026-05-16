import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var mappingItem: NSMenuItem!
    private var settingsWindow: NSWindow?
    private let permissions: PermissionsManager
    private let controller: GameControllerManager
    private let profileManager: ProfileManager
    private let engine: MappingEngine

    @MainActor
    override init() {
        self.permissions = .shared
        self.controller = .shared
        self.profileManager = .shared
        self.engine = .shared
        super.init()
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupEngine()
        checkPermissions()
        observeEngineState()
    }

    @MainActor
    private func observeEngineState() {
        withObservationTracking {
            _ = engine.isActive
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateMappingMenuItem()
                self?.observeEngineState()
            }
        }
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
        controller.stopMonitoring()
    }

    // MARK: - Menu Bar

    @MainActor
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gamecontroller", accessibilityDescription: "GamepadMapper")
        }

        let menu = NSMenu()
        menu.delegate = self

        let settingsItem = NSMenuItem(
            title: "menu_open_settings".localized,
            action: #selector(openSettings),
            keyEquivalent: "s"
        )
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let debugItem = NSMenuItem(
            title: "menu_debug_info".localized,
            action: #selector(openDebug),
            keyEquivalent: "d"
        )
        debugItem.image = NSImage(systemSymbolName: "ladybug", accessibilityDescription: nil)
        menu.addItem(debugItem)

        let logItem = NSMenuItem(
            title: "menu_engine_log".localized,
            action: #selector(openEngineLog),
            keyEquivalent: "l"
        )
        logItem.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        menu.addItem(logItem)

        menu.addItem(NSMenuItem.separator())

        mappingItem = NSMenuItem(
            title: "menu_start_mapping".localized,
            action: #selector(toggleMapping),
            keyEquivalent: "m"
        )
        mappingItem.image = NSImage(systemSymbolName: "play", accessibilityDescription: nil)
        menu.addItem(mappingItem!)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "menu_quit".localized,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate

    @MainActor
    func menuWillOpen(_ menu: NSMenu) {
        updateMappingMenuItem()
    }

    @MainActor
    private func updateMappingMenuItem() {
        guard let item = mappingItem else { return }
        if engine.isActive {
            item.title = "menu_stop_mapping".localized
            item.image = NSImage(systemSymbolName: "stop", accessibilityDescription: nil)
            if let button = statusItem.button {
                button.image = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: "GamepadMapper")
            }
        } else {
            item.title = "menu_start_mapping".localized
            item.image = NSImage(systemSymbolName: "play", accessibilityDescription: nil)
            if let button = statusItem.button {
                button.image = NSImage(systemSymbolName: "gamecontroller", accessibilityDescription: "GamepadMapper")
            }
        }
    }

    @MainActor
    private func setupEngine() {
        controller.startMonitoring()
    }

    // MARK: - Permissions

    @MainActor
    private func checkPermissions() {
        if !permissions.hasAccessibilityPermission {
            openSettings()
        }
    }

    // MARK: - Actions

    @MainActor
    @objc private func openSettings() {
        if let window = settingsWindow, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = ContentView()
        let hostingView = NSHostingView(rootView: contentView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 450),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "app_name".localized
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        settingsWindow = window
    }

    private var debugWindow: NSWindow?

    @MainActor
    @objc private func openDebug() {
        if let window = debugWindow, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let debugView = DebugView()
        let hostingView = NSHostingView(rootView: debugView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "debug_title".localized
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false

        debugWindow = window
    }

    @MainActor
    @objc private func openEngineLog() {
        NSWorkspace.shared.open(EngineLogger.logURL)
    }

    @MainActor
    @objc private func toggleMapping() {
        if engine.isActive {
            EngineLogger.log("UI: toggleMapping - stopping engine")
            engine.stop()
            EngineLogger.log("UI: toggleMapping - engine.stop() returned")
        } else {
            guard permissions.hasAccessibilityPermission else {
                openSettings()
                return
            }
            engine.start()
        }
    }
}
