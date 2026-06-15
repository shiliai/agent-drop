import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "Agent Drop")
        let item = NSMenuItem(title: "Agent Drop is starting up", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        return menu
    }
}
