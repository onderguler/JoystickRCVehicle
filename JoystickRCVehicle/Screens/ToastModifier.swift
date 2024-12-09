//
//  ToastModifier.swift
//  JoystickRCVehicle
//
//  Created by Onder Guler on 6.12.2024.
//

import SwiftUI

struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var message: String
    let duration: TimeInterval

    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isPresented {
                VStack {
                    Toast(message: message)
                        .transition(.move(edge: .top).combined(with: .opacity)) // Slide-in with fade
                        .animation(.easeIn(duration: 0.3), value: isPresented)
                        .padding(.top, 50)
                    Spacer()
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                        withAnimation {
                            isPresented = false
                        }
                    }
                }
            }
        }
    }
}

extension View {
    func toast(
        isPresented: Binding<Bool>,
        message: Binding<String>,
        duration: TimeInterval = 2.0
    ) -> some View {
        self.modifier(ToastModifier(isPresented: isPresented, message: message, duration: duration))
    }
}
