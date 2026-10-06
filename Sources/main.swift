import AppKit
import ServiceManagement

// Private CoreGraphics Spaces API. There is no public way to identify the
// current desktop, so this uses the same calls other Spaces utilities use.
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray

struct Space {
    let key: String     // Stable identifier used to store the label.
    let number: Int     // 1-based position on its display.
}

// Returns the current desktop of each display, keyed by display UUID. Each
// display has its own current desktop when displays have separate Spaces.
func currentSpaces() -> [String: Space] {
    let cid = CGSMainConnectionID()
    guard let displays = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else { return [:] }
    func spaceID(_ space: [String: Any]?) -> UInt64? {
        (space?["ManagedSpaceID"] as? NSNumber)?.uint64Value ?? (space?["id64"] as? NSNumber)?.uint64Value
    }
    var result: [String: Space] = [:]
    for display in displays {
        guard let displayID = display["Display Identifier"] as? String,
              let active = spaceID(display["Current Space"] as? [String: Any]) else { continue }
        let spaces = display["Spaces"] as? [[String: Any]] ?? []
        for (i, space) in spaces.enumerated() where spaceID(space) == active {
            // The UUID persists across reboots; the numeric ID does not.
            let uuid = space["uuid"] as? String ?? ""
            let key = uuid.isEmpty ? "id:\(active)" : uuid
            result[displayID] = Space(key: key, number: i + 1)
        }
    }
    return result
}

extension NSScreen {
    // Matches the "Display Identifier" in CGSCopyManagedDisplaySpaces.
    var displayUUID: String? {
        guard let n = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(n.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

// With a single display (or "Displays have separate Spaces" off), Spaces
// reports one entry named "Main" instead of a display UUID.
func space(for screen: NSScreen, in spaces: [String: Space]) -> Space? {
    screen.displayUUID.flatMap { spaces[$0] } ?? spaces["Main"] ?? (spaces.count == 1 ? spaces.first?.value : nil)
}

final class LabelStore {
    private let defaultsKey = "labels"
    private var labels: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
    func label(for key: String) -> String? { labels[key] }
    func set(_ label: String?, for key: String) {
        var l = labels
        l[key] = label
        labels = l
    }
}

// A click-through window that draws one display's label over the status item.
// macOS mirrors a status item identically onto every display's menu bar, so
// the item itself stays blank and reserves space while these draw the text.
final class Overlay {
    let window: NSPanel
    let field = NSTextField(labelWithString: "")

    init() {
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        field.font = NSFont.menuBarFont(ofSize: 0)
        field.alignment = .center
        window.contentView = field
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = LabelStore()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var overlays: [Overlay] = []
    private var menuSpace: Space?   // Desktop of the display whose menu is open.
    private let padding: CGFloat = 8

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        item.menu = menu
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(refresh),
                           name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Status items shift when others appear or the clock changes width,
        // and menu bars on other displays send no notification when they do.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.layout() }
        refresh()
    }

    private func title(for space: Space?) -> NSAttributedString {
        guard let space else { return NSAttributedString(string: "?") }
        if let label = store.label(for: space.key) {
            return NSAttributedString(string: "[ \(label) ]")
        }
        return NSAttributedString(string: "[ Desktop \(space.number) ]",
                                  attributes: [.foregroundColor: NSColor.secondaryLabelColor])
    }

    @objc func refresh() {
        let spaces = currentSpaces()
        let screens = NSScreen.screens
        while overlays.count < screens.count { overlays.append(Overlay()) }
        while overlays.count > screens.count { overlays.removeLast().window.orderOut(nil) }
        var width: CGFloat = 0
        for (screen, overlay) in zip(screens, overlays) {
            overlay.field.attributedStringValue = title(for: space(for: screen, in: spaces))
            overlay.field.font = NSFont.menuBarFont(ofSize: 0)
            width = max(width, overlay.field.intrinsicContentSize.width)
        }
        // Size the blank status item to fit the widest label.
        item.button?.title = ""
        item.length = ceil(width) + padding
        layout()
    }

    // Places each overlay over the status item's copy on its display. Each
    // menu bar shows its own copy at its own position, and a display can hide
    // it (for example, behind the camera housing). Copies are found by width,
    // and ties are broken by position counted from the right, since status
    // items keep the same order on every menu bar.
    @objc func layout() {
        guard let window = item.button?.window, let primary = NSScreen.screens.first else { return }
        // Window list bounds use a top-left origin at the primary display.
        func cocoaRect(_ r: CGRect) -> NSRect {
            NSRect(x: r.minX, y: primary.frame.maxY - r.maxY, width: r.width, height: r.height)
        }
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let statusItems: [NSRect] = info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.statusWindow)),
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return cocoaRect(r)
        }
        func itemsOn(_ screen: NSScreen) -> [NSRect] {
            statusItems.filter { NSPointInRect(NSPoint(x: $0.midX, y: $0.midY), screen.frame) }
                       .sorted { $0.maxX > $1.maxX }
        }
        let own = window.frame
        let hostItems = window.screen.map(itemsOn) ?? []
        let hostIndex = hostItems.firstIndex { abs($0.minX - own.minX) < 1 && abs($0.maxY - own.maxY) < 1 }
        for (screen, overlay) in zip(NSScreen.screens, overlays) {
            let items = itemsOn(screen)
            let match = items.indices.filter { abs(items[$0].width - own.width) < 1 }
                .min { abs($0 - (hostIndex ?? $0)) < abs($1 - (hostIndex ?? $1)) }
            guard let match else {
                overlay.window.orderOut(nil)
                continue
            }
            let r = items[match]
            let textHeight = overlay.field.intrinsicContentSize.height
            overlay.window.setFrame(NSRect(x: r.minX, y: r.minY + (r.height - textHeight) / 2,
                                           width: r.width, height: textHeight), display: true)
            overlay.window.orderFrontRegardless()
        }
    }

    // Rebuild the menu each time it opens so it reflects the desktop of the
    // display that was clicked.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        menuSpace = screen.flatMap { space(for: $0, in: currentSpaces()) }
        let hasLabel = menuSpace.flatMap { store.label(for: $0.key) } != nil
        menu.addItem(withTitle: hasLabel ? "Rename Desktop…" : "Name Desktop…",
                     action: #selector(rename), keyEquivalent: "").target = self
        if hasLabel {
            menu.addItem(withTitle: "Remove Name", action: #selector(clear), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc func rename() {
        guard let space = menuSpace else { return }
        let alert = NSAlert()
        alert.messageText = "Name this desktop"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = store.label(for: space.key) ?? ""
        field.placeholderString = "Desktop \(space.number)"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // Pasted text can contain line breaks, which the menu bar can't show.
        let name = field.stringValue.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        store.set(name.isEmpty ? nil : name, for: space.key)
        refresh()
    }

    @objc func clear() {
        guard let space = menuSpace else { return }
        store.set(nil, for: space.key)
        refresh()
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

if CommandLine.arguments.contains("--dump") {
    // Debug aid: print each display's current desktop, then exit.
    let spaces = currentSpaces()
    let store = LabelStore()
    for screen in NSScreen.screens {
        let s = space(for: screen, in: spaces)
        print("\(screen.localizedName): key=\(s?.key ?? "-") number=\(s.map { String($0.number) } ?? "-")"
              + " label=\(s.flatMap { store.label(for: $0.key) } ?? "-")")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.mainMenu = makeMainMenu()
app.run()
