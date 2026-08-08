# RC Joystick: WiFi and BLE

SwiftUI ile gelistirilen bu iOS uygulamasi, ayni tank kontrol arayuzunu Bluetooth veya Wi-Fi UDP uzerinden kullanir. Baglanti modu ana ekrandan secilir ve uygulama yeniden acildiginda korunur.

## Ozellikler

- Dokunulan noktada beliren bagimsiz surus ve taret joystickleri
- Bluetooth cihaz tarama, baglanma ve BLE komut iletimi
- Raspberry Pi Zero 2 W araclar icin Wi-Fi katilimi ve UDP el sikismasi
- Ayri `0...100` surus ve taret hassasiyeti
- `-99...99` dogrudan sol/sag motor komutlari
- `-254...254` kalici taret hedefleri
- Lazer, ates ve tetik icin bit maskesi
- Mod veya baglanti degisiminde guvenli durus komutu
- Jiroskopla mevcut hedeften devam eden taret kontrolu
- 10 bayt Binary V2, CRC-8, sequence ve 25 ms latest-wins komut akisi
- Alici tarafinda 250 ms guvenlik watchdog'u

## Protokol

Komut paketi, Wi-Fi varsayilanlari ve gelecekteki Raspberry Pi servisinin sorumluluklari [kontrol protokolu](docs/control-protocol.md) belgesinde tanimlanir. Kodun genel akisi icin [mimari aciklama](docs/kod-ne-yapiyor.md) belgesine bakin. Arduino Nano firmware'i ve sabit pin haritasi [Firmware](Firmware/README.md) altinda tutulur.

## Gereksinimler

- Xcode 16 veya daha yeni surum
- iOS 16 veya daha yeni surum
- Wi-Fi modu icin Hotspot Configuration yetenegi olan bir Apple gelistirici profili

Raspberry Pi GPIO servisi, hotspot kurulumu ve systemd yapilandirmasi bu deponun kapsami disindadir.
