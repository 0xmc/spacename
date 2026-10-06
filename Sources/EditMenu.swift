import AppKit

// Text fields get Cut, Copy, Paste, Select All, Undo, and the emoji picker
// only through key equivalents in the main menu. An accessory app shows no
// menu bar, so it has no main menu unless it installs one, and those keys do
// nothing. This menu is never visible, but it handles the shortcuts.
func makeMainMenu() -> NSMenu {
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    edit.addItem(.separator())
    edit.addItem(withTitle: "Emoji & Symbols", action: #selector(NSApplication.orderFrontCharacterPalette(_:)),
                 keyEquivalent: " ").keyEquivalentModifierMask = [.control, .command]

    let main = NSMenu()
    main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = NSMenu()  // App menu.
    main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
    return main
}
