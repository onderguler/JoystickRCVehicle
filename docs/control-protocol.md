# JoystickRCVehicle Binary Control Protocol V2

Bu belge iOS uygulamasi, Arduino Bluetooth firmware'i ve ileride gelistirilecek Raspberry Pi Zero 2 W servisi arasindaki Binary V2 sozlesmesidir. V1 metin paketleri artik kabul edilmez; iOS uygulamasi ve Arduino firmware'i birlikte guncellenmelidir.

## Tasima Katmanlari

### Bluetooth

- Uygulama BLE central, arac yazilabilir characteristic sunan peripheral olarak calisir.
- Her kontrol paketi tek characteristic yazmasi olarak gonderilir.
- Paket sabit `10` bayttir ve dusuk MTU'lu BLE UART modullerine sigar.
- Uygulama her `25 ms` icin en guncel komutu, yani saniyede `40` paket gonderir.
- BLE yazma hatti doluysa en fazla bir paket bekletilir. Yeni komut eski bekleyen komutun yerini alir (`latest-wins`).

### Wi-Fi UDP

- Varsayilan SSID: `JoystickRCTank`
- Varsayilan parola: `JoystickRC254`
- Varsayilan arac adresi: `192.168.4.1`
- Varsayilan UDP portu: `4210`
- SSID, IP ve port `UserDefaults`, parola iOS Keychain icinde saklanir.

UDP oturumu su sira ile hazir olur:

1. Uygulama `HELLO,2\n` metin datagramini gonderir.
2. Pi ayni istemci adresine `READY,2\n` doner.
3. Uygulama ancak `READY,2` sonrasinda 10 baytlik binary kontrol datagramlarini gonderir.
4. Uygulama her saniye `PING\n`, Pi `PONG\n` gonderir.
5. Ilk `READY,2` uc saniyede gelmezse baglanti basarisizdir.
6. Son `PONG` uzerinden 2,5 saniye gecerse baglanti kopmus sayilir.

UDP alicisi metin oturum datagramlarini ve `0xA2` ile baslayan 10 baytlik kontrol datagramlarini ayri mesaj tipleri olarak ele almalidir.

## Binary V2 Kontrol Paketi

Paket sabit olarak `10` bayttir. Cok baytli alanlar little-endian siradadir. Isaretli sayilar two's complement bicimindedir.

| Bayt | Alan | Tip | Anlam |
| ---: | --- | --- | --- |
| 0 | `header` | `uint8` | Sabit `0xA2`: komut paketi ve protokol V2 |
| 1 | `sequence` | `uint8` | Her gonderimde bir artan, `255` sonrasinda `0` olan sira numarasi |
| 2 | `leftMotor` | `int8` | Dogrudan sol motor komutu, `-99...99` |
| 3 | `rightMotor` | `int8` | Dogrudan sag motor komutu, `-99...99` |
| 4-5 | `turretX` | `int16 LE` | Yatay taret mutlak hedefi, `-254...254` |
| 6-7 | `turretY` | `int16 LE` | Dikey taret mutlak hedefi, `-254...254` |
| 8 | `flags` | `uint8` | Cihaz bit maskesi, yalnizca `0...7` |
| 9 | `crc8` | `uint8` | Bayt `0...8` uzerinden CRC-8/ATM |

Flag bitleri:

| Bit | Deger | Cihaz |
| ---: | ---: | --- |
| 0 | 1 | Lazer |
| 1 | 2 | Ates mekanizmasi |
| 2 | 4 | Tetik |

Tetik biti, ates biti yoksa alici tarafindan yok sayilir.

### Sabit Test Vektoru

`sequence=127`, motorlar `-99,-99`, taret `-254,-254`, flags `7` icin paket:

```text
A2 7F 9D 9D 02 FF 02 FF 07 07
```

Son `07` CRC baytidir.

## CRC-8

CRC parametreleri:

- Ad: `CRC-8/ATM` veya `CRC-8/SMBUS`
- Polynomial: `0x07`
- Initial value: `0x00`
- Reflect input/output: hayir
- Final XOR: `0x00`
- Korunan alan: paketin ilk 9 bayti
- `123456789` kontrol sonucu: `0xF4`

Header, CRC, alan araligi veya flags dogrulamasi basarisizsa paket atomik olarak reddedilir ve hicbir cikis degistirilmez. Arduino akisi bir sonraki `0xA2` adayindan yeniden senkron eder.

## Sequence ve Latest-Wins

Gonderici her olusturdugu paket icin sequence degerini bir artirir. Alici modulo-256 farkini hesaplar:

- Fark `1...127`: yeni paket, uygulanir.
- Fark `0`: tekrar paket, uygulanmaz.
- Fark `128...255`: eski veya sirasi bozulmus paket, uygulanmaz.

Sequence atlamalari normaldir; latest-wins kuyrugu hat mesgulse eski bekleyen paketi bilerek silebilir. Watchdog calistiginda Arduino sequence kilidini de temizler, boylece yeniden baglanan uygulamanin ilk gecerli paketi kabul edilir. Tekrar veya eski paketler watchdog suresini yenilemez.

## Guvenlik ve Watchdog

Guvenli durus komutu binary paketin normal alanlarini kullanir:

- `leftMotor = 0`
- `rightMotor = 0`
- `turretX/turretY = son hedef`
- `flags = 0`

Arduino ve gelecekteki Pi servisi son kabul edilen yeni komuttan sonra `250 ms` watchdog uygulamalidir. Sure dolunca:

- Sol ve sag motor durdurulur.
- Lazer kapanir.
- Ates mekanizmasi kapanir.
- Tetik kapanir.
- Taret servolari son hedefte tutulur.
- Sequence gecmisi temizlenir.

CRC ve sequence bozuk, tekrar veya sirasi gecmis komutlarin uygulanmasini engeller; tek basina teslimat garantisi vermez.

## Geri Bildirim Durumu

Bu surum komut yolunu Binary V2'ye gecirir, ancak Arduino'dan iOS'a ACK/telemetri paketi gondermez. Bunun icin kullanilan Bluetooth modulunun tam modeli ile su ozellikler dogrulanmalidir:

- UART'in iki yonlu calismasi
- Notify veya indicate destekleyen characteristic UUID'si
- Yazma ve bildirim characteristic'lerinin ayni mi ayri mi oldugu
- Bildirim MTU'su ve modul tampon davranisi

Bu bilgiler olmadan uygulama tarafinda teslim edildi veya uygulandi bilgisi guvenilir bicimde gosterilemez.

## Raspberry Pi Servisi Icin Gereksinimler

Pi uygulamasi bu repoda yer almaz. Ayri servis en az su davranislari saglamalidir:

- UDP `4210` portunu dinlemek ve `HELLO,2` / `READY,2`, `PING` / `PONG` mesajlarini cevaplamak.
- Yalnizca tam 10 baytlik, `0xA2` header ve gecerli CRC tasiyan komut datagramlarini kabul etmek.
- Alan araliklarini, flags ve sequence tazeligini atomik dogrulamak.
- Sol ve sag motor komutlarini yeniden tank karisimina sokmadan dogrudan uygulamak.
- Taret hedeflerini `-254...254` araligindan kendi servo kalibrasyonuna map etmek.
- Tetik/ates bagimliligini zorlamak ve `250 ms` watchdog uygulamak.
- Yeni istemci kontrolu devraldiginda onceki istemcinin sequence ve komut durumunu gecersiz kilmak.

Raspberry Pi GPIO pinleri, motor/servo kutuphaneleri, hotspot kurulumu ve systemd servisi Pi projesinde tanimlanacaktir.
