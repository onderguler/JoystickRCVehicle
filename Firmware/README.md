# Arduino rc tank with bluetooth joystick

Bu firmware yalnizca JoystickRCVehicle Binary Control Protocol V2 paketlerini kabul eder. Eski satir tabanli metin komutlari desteklenmez; iOS uygulamasi ve Arduino sketch'i birlikte guncellenmelidir.

- Paket boyutu: sabit 10 bayt
- Gonderim araligi: 25 ms
- Butunluk kontrolu: CRC-8/ATM
- Tekrar ve eski paket korumasi: 8 bit sequence
- Arduino seri tamponunda yalnizca en yeni gecerli komut uygulanir
- Guvenli cikis watchdog'u: 250 ms
- Dusuk hiz korumasi: PWM 70 altinda motor kapali
- Non-blocking motor hizlanma/yavaslama rampasi
- Non-blocking servo hiz siniri: yaklasik 200 derece/saniye

Paket yerlesimi ve sabit test vektoru icin [kontrol protokolu](../docs/control-protocol.md) belgesine bakin.

## Sabit Pin Haritasi

Bu pinler aracin orijinal kablolamasidir ve firmware degisikliklerinde korunmalidir:

| Islev | Nano pini |
| --- | --- |
| Motor `in1`, `in2`, `in3`, `in4` | `8`, `6`, `7`, `12` |
| Motor PWM `enA`, `enB` | `3`, `5` |
| Yatay, dikey servo | `10`, `9` |
| Bluetooth donanimsal RX, TX | `0`, `1` |
| Lazer | `2` |
| Firlaticilar | `11` |
| Atesleyici | `4` |
