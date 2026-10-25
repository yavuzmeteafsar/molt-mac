import AppKit

enum AppInfo {
    static let name: String = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "Molt"
    static let fileeRepo = URL(string: "https://github.com/KnifeLemon/Filee")!
    static let fileeReleases = URL(string: "https://github.com/KnifeLemon/Filee/releases/latest")!
    static let macRARRepo = URL(string: "https://github.com/mstcvk/MacRAR")!
    static var noticesURL: URL {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Licenses")
        if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return URL(string: "https://github.com/KnifeLemon/Filee/blob/main/THIRD-PARTY-NOTICES.md")!
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MainWindowController?
    private var openedBeforeLaunch: [URL] = []

    private let serviceProvider = ServiceProvider()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        serviceProvider.onFiles = { [weak self] urls in
            self?.application(NSApp, open: urls)
            NSApp.activate(ignoringOtherApps: true)
        }
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = MainWindowController()
        self.controller = controller
        controller.showWindow(nil)
        controller.startEngine()
        if !openedBeforeLaunch.isEmpty {
            controller.addURLs(openedBeforeLaunch)
            openedBeforeLaunch = []
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let controller else {
            openedBeforeLaunch += urls
            return
        }
        controller.showWindow(nil)
        controller.addURLs(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller, controller.isConverting else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = L("quit.title")
        alert.informativeText = L("quit.body")
        alert.addButton(withTitle: L("button.quit"))
        alert.addButton(withTitle: L("button.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        controller.cancelConversion()
        return .terminateNow
    }

    @objc private func showAbout(_ sender: Any?) {
        let credits = NSMutableAttributedString()
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        func line(_ text: String, link: URL? = nil) {
            var attributes = body
            if let link { attributes[.link] = link }
            credits.append(NSAttributedString(string: text, attributes: attributes))
        }
        line(L("about.engine") + " ")
        line("Filee", link: AppInfo.fileeRepo)
        line(" · Myeonggu Kim (KnifeLemon) · MIT\n")
        if let version = FileeEngine.shared.version { line(version + "\n") }
        line(L("about.inspired") + " ")
        line("MacRAR", link: AppInfo.macRARRepo)
        line(" · Mesut Çevik\n\n")
        line(L("about.licenses") + " ")
        line("THIRD-PARTY-NOTICES", link: AppInfo.noticesURL)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openFileeRepo(_ sender: Any?) {
        NSWorkspace.shared.open(AppInfo.fileeRepo)
    }

    @objc private func openFileeReleases(_ sender: Any?) {
        NSWorkspace.shared.open(AppInfo.fileeReleases)
    }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        let name = AppInfo.name

        let appMenu = NSMenu(title: name)
        let about = appMenu.addItem(withTitle: L("menu.about", name), action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("menu.locateFilee"),
                        action: #selector(MainWindowController.locateFilee(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("menu.hide", name), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: L("menu.hideOthers"),
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: L("menu.showAll"),
                        action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("menu.quit", name), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(appMenu))

        let fileMenu = NSMenu(title: L("menu.file"))
        fileMenu.addItem(withTitle: L("menu.addFiles"),
                         action: #selector(MainWindowController.addFiles(_:)), keyEquivalent: "o")
        let convert = fileMenu.addItem(withTitle: L("menu.convert"),
                                       action: #selector(MainWindowController.convert(_:)), keyEquivalent: "\r")
        convert.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: L("menu.reveal"),
                         action: #selector(MainWindowController.revealInFinder(_:)), keyEquivalent: "r")
        fileMenu.addItem(.separator())
        let remove = fileMenu.addItem(withTitle: L("menu.remove"),
                                      action: #selector(MainWindowController.removeSelected(_:)),
                                      keyEquivalent: "\u{8}")
        remove.keyEquivalentModifierMask = [.command]
        let clear = fileMenu.addItem(withTitle: L("menu.clear"),
                                     action: #selector(MainWindowController.clearAll(_:)), keyEquivalent: "\u{8}")
        clear.keyEquivalentModifierMask = [.command, .option]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: L("menu.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu(fileMenu))

        let editMenu = NSMenu(title: L("menu.edit"))
        editMenu.addItem(withTitle: L("menu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu(editMenu))

        let windowMenu = NSMenu(title: L("menu.window"))
        windowMenu.addItem(withTitle: L("menu.minimize"),
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: L("menu.zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        main.addItem(submenu(windowMenu))
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: L("menu.help"))
        let repo = helpMenu.addItem(withTitle: L("menu.fileeGitHub"), action: #selector(openFileeRepo(_:)), keyEquivalent: "")
        repo.target = self
        let releases = helpMenu.addItem(withTitle: L("menu.fileeReleases"),
                                        action: #selector(openFileeReleases(_:)), keyEquivalent: "")
        releases.target = self
        main.addItem(submenu(helpMenu))
        NSApp.helpMenu = helpMenu

        return main
    }

    private func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

final class ServiceProvider: NSObject {
    var onFiles: (([URL]) -> Void)?

    @objc func convertFiles(_ pasteboard: NSPasteboard, userData: String?,
                            error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = "No files were passed to Molt." as NSString
            return
        }
        onFiles?(urls)
    }
}
