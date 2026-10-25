import Foundation

enum L10n {
    static let isTurkish: Bool = {
        if let forced = ProcessInfo.processInfo.environment["MOLT_LANG"] {
            return forced.lowercased() == "tr"
        }
        return (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("tr")
    }()

    static let tr: [String: String] = [
        "menu.about": "%@ Hakkında",
        "format.folder": "Klasöre çıkar",
        "about.engine": "Dönüştürme motoru:",
        "about.inspired": "Arayüz ilhamı:",
        "about.licenses": "Lisanslar ve üçüncü parti bildirimleri:",
        "menu.locateFilee": "Filee Konumunu Seç…",
        "menu.hide": "%@ Uygulamasını Gizle",
        "menu.hideOthers": "Diğerlerini Gizle",
        "menu.showAll": "Tümünü Göster",
        "menu.quit": "%@ Uygulamasından Çık",
        "menu.file": "Dosya",
        "menu.addFiles": "Dosya Ekle…",
        "menu.convert": "Dönüştür",
        "menu.remove": "Seçilenleri Kaldır",
        "menu.clear": "Listeyi Temizle",
        "menu.reveal": "Finder'da Göster",
        "menu.close": "Kapat",
        "menu.edit": "Düzen",
        "menu.selectAll": "Tümünü Seç",
        "menu.window": "Pencere",
        "menu.minimize": "Küçült",
        "menu.zoom": "Yakınlaştır",
        "menu.help": "Yardım",
        "menu.fileeGitHub": "Filee GitHub Sayfası",
        "menu.fileeReleases": "Filee'yi İndir",

        "toolbar.add": "Ekle",
        "toolbar.remove": "Kaldır",
        "toolbar.clear": "Temizle",
        "toolbar.reveal": "Göster",
        "toolbar.convert": "Dönüştür",

        "column.name": "Ad",
        "column.type": "Tür",
        "column.size": "Boyut",
        "column.status": "Durum",

        "label.target": "Dönüştür:",
        "label.quality": "Kalite",
        "label.output": "Kayıt yeri:",
        "option.overwrite": "Var olanın üzerine yaz",
        "option.keepDates": "Tarihleri koru",

        "button.convert": "Dönüştür",
        "button.stop": "Durdur",
        "button.close": "Kapat",
        "button.cancel": "Vazgeç",
        "button.quit": "Çık",

        "output.nextToSource": "Kaynak dosyanın yanına",
        "output.choose": "Klasör Seç…",
        "output.panelPrompt": "Seç",

        "target.addFiles": "Önce dosya ekleyin",
        "target.loading": "Formatlar yükleniyor…",
        "target.none": "Bu dosyalar için ortak hedef yok",
        "target.needsEngine": "Filee'de ek motor gerektirir",
        "target.needsEngineCount": "Ek motor gerektirenler (%ld)",
        "target.choose": "Format seçin",
        "picker.search": "Format ara (ör. jpg, pdf, mp4)",
        "picker.noMatch": "Eşleşen format yok",
        "picker.showEngine": "Ek motor gerektirenleri de göster (%ld)",
        "target.waiting": "Filee bekleniyor…",

        "drop.title": "Dosyaları buraya sürükleyin",
        "drop.subtitle": "ya da tıklayıp seçin, klasörler de olur",

        "status.pending": "Bekliyor",
        "status.running": "Dönüştürülüyor…",
        "status.doneMany": "✓ %ld dosya",
        "status.skipped": "Atlandı (çıktı zaten var)",
        "status.failed": "Hata: %@",
        "status.cancelled": "Durduruldu",
        "status.noResult": "Filee bu dosya için sonuç bildirmedi",
        "status.summaryFiles": "%ld dosya · %@",
        "status.summaryFile": "1 dosya · %@",
        "status.skippedUnknown": "%ld dosya atlandı (Filee bu formatı tanımıyor)",
        "status.loadingEngine": "Filee yükleniyor…",
        "status.missingEngine": "Filee bulunamadı. %@ menüsünden konumunu seçebilirsiniz.",
        "status.engineReady": "%@ hazır",
        "status.engineError": "Filee başlatılamadı: %@",

        "progress.title": "%@ biçimine dönüştürülüyor",
        "progress.count": "%ld / %ld dosya",
        "progress.elapsed": "Geçen %@",
        "progress.remaining": "Kalan ~%@",
        "progress.preparing": "Hazırlanıyor…",
        "progress.stopping": "Durduruluyor…",
        "progress.details": "Ayrıntılar",
        "progress.summary.ok": "%ld dosya dönüştürüldü",
        "progress.summary.mixed": "%ld dönüştürüldü, %ld hatalı",
        "progress.summary.skipped": ", %ld atlandı",
        "progress.summary.cancelled": "Durduruldu: %ld dönüştürüldü",
        "progress.summary.error": "Filee çalıştırılamadı",

        "missing.title": "Filee bulunamadı",
        "missing.body": "%@ dönüştürme için Filee'nin komut satırı aracını kullanır. Filee'yi GitHub'dan indirip paketteki install.sh ile kurun ya da konumunu elle gösterin.",
        "missing.download": "Filee'yi İndir",
        "missing.locate": "Konum Seç…",
        "missing.invalid": "Seçilen öğe Filee komut satırı aracı değil.",
        "missing.panelMessage": "Filee.app'i ya da filee-cli dosyasını seçin",

        "error.notFound": "Filee komut satırı aracı bulunamadı.",
        "error.noFormats": "Filee format listesi okunamadı.",

        "quit.title": "Dönüştürme sürüyor",
        "quit.body": "Çıkarsanız işlem durdurulur.",

        "context.open": "Aç",
        "context.openOutput": "Çıktıyı Aç",
        "context.revealOutput": "Çıktıyı Finder'da Göster",
        "context.revealSource": "Kaynağı Finder'da Göster",
        "context.remove": "Listeden Kaldır",

        "category.Image": "Görsel",
        "category.Vector": "Vektör",
        "category.Pdf": "PDF",
        "category.Document": "Belge",
        "category.Spreadsheet": "Tablo",
        "category.Presentation": "Sunum",
        "category.Hwp": "HWP",
        "category.Text": "Metin",
        "category.Video": "Video",
        "category.Audio": "Ses",
        "category.Ebook": "E-kitap",
        "category.Archive": "Arşiv",
        "category.Cad": "CAD",
        "category.Font": "Yazı tipi",
        "category.Subtitle": "Altyazı",
        "category.Data": "Veri",
        "category.Model3D": "3D model",
        "category.Geo": "Harita",
    ]

    static let en: [String: String] = [
        "menu.about": "About %@",
        "format.folder": "Extract to folder",
        "about.engine": "Conversion engine:",
        "about.inspired": "Interface inspired by",
        "about.licenses": "Licenses and third-party notices:",
        "menu.locateFilee": "Locate Filee…",
        "menu.hide": "Hide %@",
        "menu.hideOthers": "Hide Others",
        "menu.showAll": "Show All",
        "menu.quit": "Quit %@",
        "menu.file": "File",
        "menu.addFiles": "Add Files…",
        "menu.convert": "Convert",
        "menu.remove": "Remove Selected",
        "menu.clear": "Clear List",
        "menu.reveal": "Show in Finder",
        "menu.close": "Close",
        "menu.edit": "Edit",
        "menu.selectAll": "Select All",
        "menu.window": "Window",
        "menu.minimize": "Minimize",
        "menu.zoom": "Zoom",
        "menu.help": "Help",
        "menu.fileeGitHub": "Filee on GitHub",
        "menu.fileeReleases": "Download Filee",

        "toolbar.add": "Add",
        "toolbar.remove": "Remove",
        "toolbar.clear": "Clear",
        "toolbar.reveal": "Show",
        "toolbar.convert": "Convert",

        "column.name": "Name",
        "column.type": "Type",
        "column.size": "Size",
        "column.status": "Status",

        "label.target": "Convert to:",
        "label.quality": "Quality",
        "label.output": "Save to:",
        "option.overwrite": "Overwrite existing",
        "option.keepDates": "Keep dates",

        "button.convert": "Convert",
        "button.stop": "Stop",
        "button.close": "Close",
        "button.cancel": "Cancel",
        "button.quit": "Quit",

        "output.nextToSource": "Next to the original",
        "output.choose": "Choose Folder…",
        "output.panelPrompt": "Choose",

        "target.addFiles": "Add files first",
        "target.loading": "Loading formats…",
        "target.none": "No common target for these files",
        "target.needsEngine": "Needs an optional engine in Filee",
        "target.needsEngineCount": "Needs an optional engine (%ld)",
        "target.choose": "Choose a format",
        "picker.search": "Search formats (e.g. jpg, pdf, mp4)",
        "picker.noMatch": "No matching format",
        "picker.showEngine": "Also show formats that need an optional engine (%ld)",
        "target.waiting": "Waiting for Filee…",

        "drop.title": "Drop files here",
        "drop.subtitle": "or click to choose, folders work too",

        "status.pending": "Waiting",
        "status.running": "Converting…",
        "status.doneMany": "✓ %ld files",
        "status.skipped": "Skipped (output exists)",
        "status.failed": "Error: %@",
        "status.cancelled": "Stopped",
        "status.noResult": "Filee reported no result for this file",
        "status.summaryFiles": "%ld files · %@",
        "status.summaryFile": "1 file · %@",
        "status.skippedUnknown": "%ld file(s) skipped (format not supported by Filee)",
        "status.loadingEngine": "Loading Filee…",
        "status.missingEngine": "Filee not found. You can locate it from the %@ menu.",
        "status.engineReady": "%@ ready",
        "status.engineError": "Couldn't start Filee: %@",

        "progress.title": "Converting to %@",
        "progress.count": "%ld of %ld files",
        "progress.elapsed": "Elapsed %@",
        "progress.remaining": "About %@ left",
        "progress.preparing": "Preparing…",
        "progress.stopping": "Stopping…",
        "progress.details": "Details",
        "progress.summary.ok": "%ld file(s) converted",
        "progress.summary.mixed": "%ld converted, %ld failed",
        "progress.summary.skipped": ", %ld skipped",
        "progress.summary.cancelled": "Stopped: %ld converted",
        "progress.summary.error": "Filee couldn't run",

        "missing.title": "Filee not found",
        "missing.body": "%@ uses Filee's command-line tool to convert files. Download Filee from GitHub and install it with the bundled install.sh, or locate it manually.",
        "missing.download": "Download Filee",
        "missing.locate": "Locate…",
        "missing.invalid": "The selected item isn't the Filee command-line tool.",
        "missing.panelMessage": "Choose Filee.app or the filee-cli file",

        "error.notFound": "The Filee command-line tool wasn't found.",
        "error.noFormats": "Couldn't read Filee's format list.",

        "quit.title": "A conversion is running",
        "quit.body": "Quitting will stop it.",

        "context.open": "Open",
        "context.openOutput": "Open Output",
        "context.revealOutput": "Show Output in Finder",
        "context.revealSource": "Show Original in Finder",
        "context.remove": "Remove from List",

        "category.Image": "Image",
        "category.Vector": "Vector",
        "category.Pdf": "PDF",
        "category.Document": "Document",
        "category.Spreadsheet": "Spreadsheet",
        "category.Presentation": "Presentation",
        "category.Hwp": "HWP",
        "category.Text": "Text",
        "category.Video": "Video",
        "category.Audio": "Audio",
        "category.Ebook": "E-book",
        "category.Archive": "Archive",
        "category.Cad": "CAD",
        "category.Font": "Font",
        "category.Subtitle": "Subtitle",
        "category.Data": "Data",
        "category.Model3D": "3D model",
        "category.Geo": "Map",
    ]
}

func L(_ key: String) -> String {
    let table = L10n.isTurkish ? L10n.tr : L10n.en
    return table[key] ?? L10n.en[key] ?? key
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), arguments: arguments)
}

func categoryName(_ raw: String) -> String {
    let key = "category." + raw
    let value = L(key)
    return value == key ? raw : value
}
