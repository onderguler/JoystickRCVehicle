//
//  Toast.swift
//  JoystickRCVehicle
//
//  Created by Onder Guler on 6.12.2024.
//


import SwiftUI

struct Toast: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.body)
            .padding()
            .background(Color.black.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(10)
            .multilineTextAlignment(.center)
            .shadow(radius: 5)
    }
}
