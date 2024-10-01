//
//  BluetoothManager.swift
//  JoystickRCVehicle
//
//  Created by Onder Guler on 24.09.2024.
//

import CoreBluetooth
import SwiftUI

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var peripherals: [CBPeripheral] = []  // Cihazları listelemek için
    @Published var isConnected = false  // Bağlantı durumu
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writableCharacteristic: CBCharacteristic?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // Merkezi Bluetooth yöneticisinin durumu değiştiğinde çağrılır
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            // Bluetooth açık, cihazları aramaya başla
            central.scanForPeripherals(withServices: nil, options: nil)
        } else {
            print("Bluetooth kullanılabilir değil.")
        }
    }
    
    // Cihaz bulunduğunda tetiklenir
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !peripherals.contains(peripheral) {
            peripherals.append(peripheral)
        }
    }
    
    // Cihaza bağlanma
    func connect(to peripheral: CBPeripheral) {
        centralManager.stopScan()  // Tarama durdurulur
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }
    
    // Bağlantı başarılı olduğunda tetiklenir
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Bağlandı: \(peripheral.name ?? "Bilinmeyen cihaz")")
        startSendingJoystickData()
        isConnected = true
        peripheral.discoverServices(nil)  // Tüm servisleri keşfet
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        isConnected = false
    }
    
    // Servisler keşfedildiğinde tetiklenir
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            for service in services {
                // Servis içindeki karakteristikleri keşfet
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    // Karakteristikler keşfedildiğinde tetiklenir
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                // Yazma özelliği olan karakteristiği kaydet
                if characteristic.properties.contains(.write) {
                    writableCharacteristic = characteristic
                }
            }
        }
    }
    
    // Joystick verilerini gönder
    var timer: Timer?
    var lastJoystickValue: String = "0,0;0,0;lft"  // En son joystick verisini saklamak için
    
    // Timer başlatıp 100 ms'de bir veri gönderen fonksiyon
    func startSendingJoystickData() {
        // Eğer bir timer zaten çalışıyorsa, başlatmadan önce durdur
        if timer != nil {
            timer?.invalidate()
        }
        
        // 100 milisaniyede bir çalışan timer
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            // Son joystick verisini gönder
            self.sendJoystickData(value: self.lastJoystickValue)
        }
    }
    
    func stopSendingJoystickData() {
        // Timer'ı durdur
        timer?.invalidate()
        timer = nil
    }
    
    // Joystick verisini sadece 100 milisaniyede bir gönderiyoruz
    func updateJoystickValue( value: String) {
        // Joystick'ten gelen veriyi kaydet
        lastJoystickValue = value
    }
        
    private func sendJoystickData(value: String) {
        // Yazılabilir karakteristiğin olup olmadığını kontrol et
        guard let characteristic = writableCharacteristic else {
            print("Yazılabilir karakteristik bulunamadı.")
            return
        }

        // Bağlı periferik cihazın mevcut olup olmadığını kontrol et
        guard let connectedPeripheral = connectedPeripheral else {
            print("Bağlı periferik cihaz bulunamadı.")
            return
        }
        
        // String değerini karakter dizisine çevir
        let tmpValue = value + "\n"
       
        let data = Data(tmpValue.utf8)
        print(data)
        print(tmpValue)
        // Bluetooth karakteristiğine veri yaz
        connectedPeripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

}
