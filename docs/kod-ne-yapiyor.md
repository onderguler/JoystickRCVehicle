# JoystickRCVehicle Kodu Ne Yapiyor?

Bu proje, ayni iOS uygulamasindan iki farkli tank surumunu kontrol eder:

- Bluetooth modu mevcut Arduino ve BLE seri modulune komut gonderir.
- Wi-Fi modu Raspberry Pi Zero 2 W tabanli tanka UDP komutu gonderir.

Raspberry Pi tarafindaki GPIO uygulamasi bu repoda bulunmaz. Uymasi gereken ag ve komut sozlesmesi [control-protocol.md](control-protocol.md) dosyasinda tanimlanir.

## Genel Akis

1. Kullanici ana ekrandan `Bluetooth` veya `Wi-Fi` modunu secer.
2. Secilen tasiyici araca baglanir.
3. Sol kontrol alani sol ve sag motor hizlarini, sag alan taret hedefini uretir.
4. Lazer, ates ve tetik durumlari tek bir bit maskesinde birlestirilir.
5. `ConnectionCoordinator` son komutu her 25 ms'de bir Binary V2 paketi olarak aktif tasiyiciya gonderir.
6. Mod degisince veya uygulama arka plana gecince motorlar ve cihaz cikislari sifirlanir; taret son hedefini korur.

## iOS Uygulamasi

`ContentView`, ustte baglanti secimi ve durum kontrollerini, altta iki dokunma alanini gosterir. Joystickler sabit bir noktada durmaz; ilk dokunusta alana sigacak en yakin noktada belirir ve kenarda da baslangic degerini merkez kabul eder.

Sol joystick:

- Dairesel hareket siniri kullanir.
- Ileri ve donus degerlerini dogrudan sol/sag motor hizina karistirir.
- `-99...99` araliginda motor komutu uretir.
- Parmak kalkinca `0,0` degerine doner.

Sag joystick:

- Mevcut taret hedefini hareketin baslangici kabul eder.
- Her eksende `-254...254` araliginda hedef uretir.
- Parmak kalkinca hedefi sifirlamaz.
- Gyro etkinken elle taret alani devre disi kalir.

## Hassasiyet

Ayarlar ekraninda surus ve taret icin iki ayri `0...100` slider bulunur. `50` dogrusal tepkidir. Daha dusuk degerler merkez cevresini yumusatir, daha yuksek degerler merkeze yakin hareketleri hizlandirir. Taret `0%` ayarinda merkez konumunda yaklasik 5 derecelik yatay hareket icin joystick yaklasik yari mesafe suruklenir. Joystick uclarinda tam cikis araligi her durumda korunur.

Gyro, mevcut taret hedefinden baslar ve ayni taret hassasiyetini kullanir. Gyro kapatildiginda taret merkeze donmez.

## Baglanti Katmani

`ConnectionCoordinator`, joystick ve butonlardan gelen `VehicleCommand` modelini aktif baglantiya yollar. Uygulamanin geri kalani Bluetooth veya UDP ayrintilarini bilmez.

Bluetooth tarafinda `BluetoothManager`:

- Cevredeki BLE cihazlarini tarar.
- Secilen cihazin servis ve characteristic'lerini kesfeder.
- Yazilabilir characteristic bulundugunda baglantiyi hazir kabul eder.
- BLE yazma boyutunu kontrol eder ve hat doluyken sadece en yeni bekleyen komutu tutar.

Wi-Fi tarafinda `WiFiManager`:

- Varsayilan `JoystickRCTank` agina iOS sistem onayi ile katilir.
- Varsayilan `192.168.4.1:4210` hedefine UDP baglantisi acar.
- `HELLO,2` / `READY,2` el sikismasini yapar.
- `PING` / `PONG` ile baglantinin canli oldugunu izler.
- SSID, parola, IP ve port degerlerinin uygulamadan degistirilmesine izin verir.

## Komut Formati

Her kontrol paketi sabit 10 baytlik Binary V2 verisidir:

```text
A2 | sequence | sol | sag | taretX(LE) | taretY(LE) | flags | CRC-8
```

Araliklar:

- Sol ve sag motor: `-99...99`
- Taret X ve Y: `-254...254`
- Cihaz bit maskesi: `0...7`

Bitler:

- `1`: lazer
- `2`: ates mekanizmasi
- `4`: tetik

`3`, lazer ve atesin birlikte acik oldugunu belirtir. CRC-8 bozuk veriyi, sequence ise tekrar veya sirasi gecmis komutlari engeller. Ayrintili bayt tablosu [control-protocol.md](control-protocol.md) dosyasindadir.

## Arduino Firmware

Arduino sketch'i Bluetooth seri verisini bloklamadan bayt bayt okur. `0xA2` header ile senkron olur; 10 bayt tamamlaninca CRC, sequence ve butun alanlari dogrular, sonra cikislari birlikte gunceller.

- Motor degerleri yeniden karistirilmaz; orijinal yon ve enable pinleri korunarak sol ve sag komutlar `-255...255` PWM araligina map edilir.
- PWM 70 altindaki stall bolgesi kapatilir; hizlanma ve yavaslama bloklamayan bir rampa ile uygulanir.
- Yon degisiminde motor once sifira iner, sonra ters yone kalkar.
- Yatay taret `-254...254` degerini `10...180` dereceye map eder.
- Dikey taret `-254...254` degerini `52...108` dereceye map eder.
- Servo hedefleri `delay()` kullanmadan yaklasik saniyede 200 derece hizla takip edilir.
- Seri tamponda birden fazla paket varsa sequence numarasi en yeni olan son komut uygulanir.
- Tetik biti yalnizca ates biti de aciksa uygulanir.
- 250 ms boyunca yeni ve gecerli komut gelmezse motor, lazer, ates ve tetik kapanir; servolar son hedefte kalir.

Mevcut pinler ve `PWMServo` kullanimi korunur. `PWMServo.write()` derece tabanli oldugu icin kablo uzerinde 509 taret seviyesi olsa da fiziksel servo cikisi tam derece adimlariyla sinirlidir.

## Guvenli Durus

Guvenli durus komutu normal Binary V2 paketi icinde motorlari ve cihaz bitlerini sifirlar, ancak mevcut taret hedefini tasir.

Bu komut mod degisiminde, uygulama arka plana gectiginde ve kullanici baglantiyi kestiginde gonderilir. Arduino watchdog'u ile gelecekteki Raspberry Pi alicisi da baglanti kaybinda ayni cikislari kapatmalidir.
