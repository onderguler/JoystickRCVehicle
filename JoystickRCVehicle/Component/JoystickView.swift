//
//  JoystickView.swift
//  JoystickRCVehicle
//
//  Created by Onder Guler on 24.09.2024.
//

import SwiftUI

struct JoystickView: View {
    @State private var joystickPosition = CGSize.zero
    
    var size: CGFloat = 250 // Joystick çerçeve boyutunu 250 yap
    var joyStickOnChange: (String) -> Void
    var type: JoystickDataType = .movement
    
    var body: some View {
        ZStack {
            // Joystick dış çerçeve (arka plan)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.01))
                .frame(width: size, height: size)
            
            // Joystick kontrolcü (thumb)
            Circle()
                .fill(Color.blue)
                .frame(width: size / 5, height: size / 5) // Thumb boyutunu çerçeve boyutuna göre ayarla
                .offset(joystickPosition)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Joystick pozisyonunu sınırlayıp hareket ettirelim
                            let limitedPosition = limitMovement(translation: value.translation)
                            self.joystickPosition = limitedPosition
                            
                            // X ve Y değerlerini hesapla
                            let xValue = constrain(Int(limitedPosition.width / (size / 2) * 100), min: -100, max: 100)
                            let yValue = constrain(Int(-limitedPosition.height / (size / 2) * 100), min: -100, max: 100)
                            var joystickData = ""
                            
                            // Motor hızlarını hesapla
                            switch type {
                            case .movement:
                                let leftMotorSpeed = constrain(yValue + xValue, min: -99, max: 99)
                                let rightMotorSpeed = constrain(yValue - xValue, min: -99, max: 99)
                                joystickData = "\(leftMotorSpeed),\(rightMotorSpeed)"
                                
                            case .turret:
                                let leftMotorSpeed = constrain(-xValue, min: -99, max: 99)
                                let rightMotorSpeed = constrain(yValue, min: -99, max: 99)
                                joystickData = "\(leftMotorSpeed),\(rightMotorSpeed)"
                            }
                            
                            // Arduino'ya verileri gönder
                            joyStickOnChange(joystickData)
                        }
                        .onEnded { _ in
                            // Joystick sıfırlama
                            self.joystickPosition = .zero
                            joyStickOnChange("0,0") // Motor hızlarını sıfırla
                        }
                )
        }
    }
    
    enum JoystickDataType {
        case movement
        case turret
    }
    
    // Joystick hareketini kare sınırlayıcıyla sınırlama fonksiyonu
    private func limitMovement(translation: CGSize) -> CGSize {
        let limit: CGFloat = size / 2 // Joystick yarıçapı
        
        // X ve Y sınırlarını ayarla
        let limitedWidth = min(max(translation.width, -limit), limit)
        let limitedHeight = min(max(translation.height, -limit), limit)
        
        return CGSize(width: limitedWidth, height: limitedHeight)
    }
}

// Değerleri sınırlama fonksiyonu
public func constrain(_ value: Int, min: Int, max: Int) -> Int {
    return Swift.max(min, Swift.min(max, value))
}
