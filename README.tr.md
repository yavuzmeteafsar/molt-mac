<p align="center">
  <img src="Assets/AppIcon.png" width="128" alt="Molt simgesi">
</p>

<h1 align="center">Molt for Mac</h1>

<p align="center">
  macOS için native bir dosya dönüştürücü, <a href="https://github.com/KnifeLemon/Filee">Filee</a> motoruyla.<br>
  <em>Yılan deri değiştirir ama aynı yılandır; dosya da format değiştirir ama içeriği aynı kalır.</em>
</p>

<p align="center">
  <a href="https://github.com/yavuzmeteafsar/molt-mac/releases/latest"><img src="https://img.shields.io/github/v/release/yavuzmeteafsar/molt-mac?color=F06EAA" alt="Release"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-555" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%7C%20Intel-555" alt="Apple Silicon | Intel">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/yavuzmeteafsar/molt-mac?color=555" alt="MIT license"></a>
</p>

<p align="center">
  <img src="docs/main-window.png" width="720" alt="Dönüştürülmüş dosyalarla Molt ana penceresi">
</p>

Dosyaları pencereye bırak, hedef formatı seç, **Dönüştür**'e bas. Görsel, PDF, Word, Excel, PowerPoint, e-kitap,
yazı tipi, CAD, 3D model ve daha fazlası, tamamen çevrimdışı.

[🇬🇧 English](README.md)

<p align="center">
  <img src="docs/format-picker.png" width="720" alt="Kategorilere ayrılmış, aranabilir format seçici">
</p>

## Filee üzerine kurulu

Molt kendisi hiçbir dönüştürme yapmaz. Bütün dönüşümleri Myeonggu Kim'in (KnifeLemon) MIT lisanslı açık kaynak
dönüştürücüsü **[Filee](https://github.com/KnifeLemon/Filee)** yapar. Molt, Filee'nin dönüştürme motorunu
(komut satırı aracı ve kullandığı kütüphaneler) uygulamanın içinde taşır ve önüne native bir AppKit penceresi koyar.
Filee uygulamasını ayrıca kurmak gerekmez.

Molt'un kattıkları:

- Filee'nin imleçte açılan halka menüsü yerine klasik bir Mac penceresi: dosya başına durum gösteren liste,
  sütunlara yayılmış ve aranabilen format seçici, kayıtlı ilerleme penceresi
- Finder'ın sağ tık menüsünde **Molt ile Dönüştür** (Hızlı İşlemler ya da Servisler altında): dosyaları seç, sağ
  tıkla, Molt'ta açılsınlar
- Arşivler (RAR, ZIP, 7Z, TAR, ISO ve daha fazlası) Finder'daki gibi açılır: tek öğenin etrafında ekstra klasör
  yok, `__MACOSX` artığı yok
- Erişilebilirlik veya Finder Otomasyonu izni yok; Molt sistem genelindeki sürükleme hareketlerini dinlemez
- Türkçe ve İngilizce arayüz

Windows veya Linux kullanıyorsan ya da halka menüyü tercih ediyorsan doğrudan Filee'yi kullan.

## Kurulum

Mac'ine uygun DMG'yi [Releases](../../releases/latest) sayfasından indir:

- `Molt-<sürüm>-arm64.dmg`: Apple Silicon (M1 ve sonrası)
- `Molt-<sürüm>-x86_64.dmg`: Intel Mac'ler

Aç ve **Molt**'u **Uygulamalar** klasörüne sürükle. macOS 13 Ventura veya üstü gerekiyor.

Molt ad-hoc imzalı ve notarize edilmemiş (bunun için ücretli Apple Developer üyeliği gerekiyor). İlk açılışta macOS
uygulamayı engeller: **Sistem Ayarları → Gizlilik ve Güvenlik** bölümünde aşağı kaydırıp **Yine de Aç**'a tıkla.

**Molt ile Dönüştür** ilk açılıştan sonra görünmezse **Sistem Ayarları → Klavye → Klavye Kestirmeleri → Servisler →
Dosyalar ve Klasörler** altından aç.

## İsteğe bağlı motorlar

Çoğu dönüşüm kurulumsuz çalışır. Bazıları, Filee'nin Mac'te aradığı daha büyük bir program gerektirir:

| Motor | Açtığı formatlar | Kurulum |
| --- | --- | --- |
| LibreOffice | DOC, RTF, ODT, PPT ve diğer eski ofis formatları; Türkçe, Arapça gibi Latin-1 dışı metinlerde düzgün PDF | `brew install --cask libreoffice` |
| FFmpeg | Bütün video ve ses | `brew install ffmpeg` |
| Pandoc | Markdown, LaTeX ve diğer işaretleme dilleri ↔ DOCX/ODT, DOCX → PPTX slayt | `brew install pandoc` |
| Ghostscript | EPS / PS | `brew install ghostscript` |
| calibre | MOBI, AZW3 ve nadir e-kitap formatları | `brew install --cask calibre` |

Kurduktan sonra Molt'u yeniden başlat. Eksik motor gerektiren formatlar seçicide gizlidir; **Ek motor gerektirenleri
de göster** ile gri hâlde görülebilir.

## Nasıl çalışıyor

Molt, Filee'nin komut satırı aracını alt süreç olarak çalıştırır; arşiv arayüzlerinin `unrar` ya da `7zz`'yi
sarmalaması gibi:

| Adım | Filee komutu | Molt ne yapıyor |
| --- | --- | --- |
| Açılış | `filee formats` | Uzantı → format tablosunu kurar |
| Dosya eklenince | `filee formats <id>` | Her formatın hedeflerini alıp seçili dosyaların ortak hedeflerini bulur |
| Dönüştür | `filee convert <dosyalar> --to <id> [-o klasör] [--quality n] [--overwrite] [--keep-dates]` | Filee'nin dosya başına yazdığı `ok` / `fail` / `skip` satırlarını yazıldıkları anda okuyup tabloyu ve ilerleme penceresini canlı günceller |
| Durdur | `SIGINT` | Terminaldeki Ctrl+C ile aynı; Filee işi temiz şekilde iptal eder |

Filee'nin `--json` çıktısı bilerek kullanılmadı: o çıktı bütün iş bittikten sonra tek seferde gelir, satır çıktısı
ise uzun bir toplu işte dosya bazında ilerleme verir.

## Kaynaktan derleme

Gereksinimler: macOS 13+, Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone --recurse-submodules https://github.com/<kullanıcı>/molt-mac.git
cd molt-mac
sh build.sh run
```

Bu, motoru gömmeden derler. Uygulama bu durumda Filee'nin kendi `install.sh`'ı ile kurulmuş bir Filee'yi
(`~/.local/bin/filee`) ya da **Molt → Filee Konumunu Seç…** ile gösterileni kullanır.

Motoru release'teki gibi gömmek için .NET 10 SDK ve PowerShell de gerekir (`brew install dotnet powershell`):

```sh
sh scripts/embed-engine.sh osx-arm64
ENGINE_DIR=build/engine-osx-arm64/cli sh build.sh run
```

Release'ler her `v*` tag'inde [GitHub Actions](.github/workflows/release.yml) ile iki mimari için derlenir.

## Teşekkürler ve lisanslar

- **[Filee](https://github.com/KnifeLemon/Filee)** © Myeonggu Kim (KnifeLemon) ve Filee katkıcıları, MIT.
  Dönüştürme motoru. Lisansı ve üçüncü parti bildirimleri (ImageMagick, PDFium, SkiaSharp, rhwp, 7-Zip ve
  diğerleri) uygulamanın içinde `Contents/Resources/Licenses` altında ve [vendor/Filee](vendor/Filee) klasöründe.
- **[MacRAR](https://github.com/mstcvk/MacRAR)**, Mesut Çevik, MIT. Pencere düzeni ve komut satırı motorunu native
  bir uygulamayla sarmalama yaklaşımı için ilham kaynağı.

Molt, Filee projesiyle bağlantılı değildir ve onun tarafından onaylanmamıştır.

Molt'un kendi kodu MIT lisanslıdır, [LICENSE](LICENSE) dosyasına bakın.
