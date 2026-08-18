import AppKit

/// The main menu exists for its key equivalents, not to be seen.
///
/// An accessory app shows no menu bar, but AppKit still delivers editing
/// shortcuts through the main menu. Without one, `⌘V` does nothing in a text
/// view while right-click → Paste keeps working, because that path goes straight
/// to the responder.
///
/// Quit is deliberately absent. `⌘Q` in the gist window would kill the menu bar
/// app and silently take the hotkey with it.
enum MainMenu {

    static func install() {
        let root = NSMenu()
        root.addItem(windowMenu())
        root.addItem(editMenu())
        NSApp.mainMenu = root
    }

    private static func windowMenu() -> NSMenuItem {
        let menu = NSMenu(title: "Window")
        menu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private static func editMenu() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")

        // A nil target sends these along the responder chain, so the focused
        // text view handles them.
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")

        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }
}
