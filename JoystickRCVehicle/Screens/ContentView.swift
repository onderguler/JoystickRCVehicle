//
//  ContentView.swift
//  JoystickRCVehicle
//
//  Created by Onder Guler on 24.09.2024.
//

import SwiftUI
import CoreMotion

struct ContentView: View {
    @AppStorage("isHapticFeedbackEnabled") private var isHapticFeedbackEnabled: Bool?
    
    @State private var showingBluetoothDevices = false
    @State private var showingInfoView = false
    @State private var showSettingsView = false
    
    // Onboarding için state değişkenleri
    @State private var showOnboarding = false
    @State private var showOnboardingIntro = false
    @State private var currentOnboardingStep = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    
    @State private var showToast = false
    @State private var showMessage = "connect_bluetooth_first".localized
    

    @State private var combinedData = ""
    var bluetoothManager = BluetoothManager()
    
    // Sol ve sağ joystick verilerini saklayan state
    @State private var leftJoystickValue = "0,0"  // Sol joystick
    @State private var rightJoystickValue = "0,0" // Sağ joystick
    @State private var laserButtonValue = "l" // Laser buton verisi
    @State private var fireButtonValue = "f" // Fire buton verisi
    @State private var triggerButtonValue = "t" // Trigger buton verisi
    private let motionManager = CMMotionManager()
    @State private var isControlling: Bool = false
    @State private var accumulatedX: Double = 0.0
    @State private var accumulatedY: Double = 0.0
    @State private var doubleValue: CGSize = .zero
        
    // Onboarding için referans noktaları
    @State private var infoButtonPosition: CGPoint = .zero
    @State private var settingsButtonPosition: CGPoint = .zero
    @State private var bluetoothButtonPosition: CGPoint = .zero
    @State private var gyroButtonPosition: CGPoint = .zero
    @State private var leftJoystickPosition: CGPoint = .zero
    @State private var laserButtonPosition: CGPoint = .zero
    @State private var fireButtonPosition: CGPoint = .zero
    @State private var triggerButtonPosition: CGPoint = .zero
    @State private var rightJoystickPosition: CGPoint = .zero
    
    // Onboarding için state değişkenleri
    @State private var onboardingIntroStep = 0
    let onboardingIntroSteps: [OnboardingStep] = [
        OnboardingStep(
            title: "Bilgi Butonu",
            description: "Uygulama hakkında bilgi almak için bu butona tıklayın.",
            icon: "info.circle"
        ),
        OnboardingStep(
            title: "Ayarlar Butonu",
            description: "Uygulama ayarlarını değiştirmek için bu butona tıklayın.",
            icon: "gear.circle"
        ),
        OnboardingStep(
            title: "Bluetooth Bağlantısı",
            description: "Aracınıza bağlanmak için bu butona tıklayın.",
            icon: "cable.connector"
        ),
        OnboardingStep(
            title: "Gyro Kontrolü",
            description: "Jiroskop ile kontrol etmek için bu butona tıklayın.",
            icon: "gyroscope"
        ),
        OnboardingStep(
            title: "Sol Joystick",
            description: "Aracın hareketini kontrol etmek için kullanılır.",
            icon: "arrow.up.and.down.and.arrow.left.and.right"
        ),
        OnboardingStep(
            title: "Lazer Butonu",
            description: "Lazeri açıp kapatmak için kullanılır.",
            icon: "target"
        ),
        OnboardingStep(
            title: "Ateş Butonu",
            description: "Ateş etmek için kullanılır.",
            icon: "bolt.fill"
        ),
        OnboardingStep(
            title: "Tetik Butonu",
            description: "Ateş etmeyi tetiklemek için kullanılır.",
            icon: "flame.fill"
        ),
        OnboardingStep(
            title: "Sağ Joystick",
            description: "Taret kontrolü için kullanılır.",
            icon: "arrow.up.and.down.and.arrow.left.and.right"
        )
    ]
    
    func toggleGyroUpdates() {
        if isControlling {
            stopGyroUpdates()
        } else {
            startGyroUpdates()
        }
        isControlling.toggle()
    }
    
    private func startGyroUpdates() {
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 0.1
            motionManager.startGyroUpdates(to: OperationQueue.main) { data, error in
                guard let gyroData = data else { return }
                
                // Rotation rate'i biriktirerek kullanıyoruz
                let rotationRateX = gyroData.rotationRate.x * 100.0
                let rotationRateY = gyroData.rotationRate.y * 100.0
                
                // Yeni pozisyonları önceki pozisyonlara ekleyerek biriktiriyoruz
                accumulatedX += rotationRateX * 0.1 // Kümülatif birikim
                accumulatedY += rotationRateY * 0.1 // Kümülatif birikim
                
                // Yeni değerleri sınırlandır
                let xValue = constrain(Int(accumulatedX), min: -100, max: 100)
                let yValue = constrain(Int(accumulatedY), min: -100, max: 100)
                
                // Joystick verilerini güncelle
                rightJoystickValue = "\(xValue),\(yValue)"
                updateAndSendCombinedJoystickData()
            }
        }
    }
    
    private func stopGyroUpdates() {
        motionManager.stopGyroUpdates()
        
        accumulatedX = 0.0
        accumulatedY = 0.0
        rightJoystickValue = "\(accumulatedX),\(accumulatedY)"
        updateAndSendCombinedJoystickData()
    }
    
    var body: some View {
        VStack {
            VStack {
                HStack {
                    Button(action: {
                        if isHapticFeedbackEnabled ?? true {
                            HapticFeedbackManager.shared.triggerImpact(style: .light)
                        }
                        showingInfoView = true
                    }) {
                        Image(systemName: "info.circle")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .padding()
                            .background(Color.blue)
                            .clipShape(Circle())
                            .foregroundColor(.white)
                    }
                    .sheet(isPresented: $showingInfoView) {
                      
                        InfoView()
                    }
                    .background(GeometryReader { geo -> Color in
                        DispatchQueue.main.async {
                            infoButtonPosition = CGPoint(
                                x: geo.frame(in: .global).midX,
                                y: geo.frame(in: .global).midY
                            )
                        }
                        return Color.clear
                    })
                    
                    Button(action: {
                        if isHapticFeedbackEnabled ?? true {
                            HapticFeedbackManager.shared.triggerImpact(style: .light)
                        }
                        showSettingsView = true
                    }) {
                        Image(systemName: "gear.circle")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .padding()
                            .background(Color.blue)
                            .clipShape(Circle())
                            .foregroundColor(.white)
                    }
                    .sheet(isPresented: $showSettingsView) {
                        SettingsView()
                    }
                    .background(GeometryReader { geo -> Color in
                        DispatchQueue.main.async {
                            settingsButtonPosition = CGPoint(
                                x: geo.frame(in: .global).midX,
                                y: geo.frame(in: .global).midY
                            )
                        }
                        return Color.clear
                    })

                    Spacer()
                    Button(action: {
                        if isHapticFeedbackEnabled ?? true {
                            HapticFeedbackManager.shared.triggerImpact(style: .light)
                        }
                        showingBluetoothDevices = true  // Bluetooth cihaz listesini açar
                    }) {
                        Image(systemName: bluetoothManager.isConnected ?  "cable.connector" : "cable.connector.slash")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .padding()
                            .background(bluetoothManager.isConnected ? Color.green: .red)
                            .clipShape(Circle())
                            .foregroundColor(.white)
                    }
                    .sheet(isPresented: $showingBluetoothDevices) {
                        // Bluetooth cihaz listesini burada açabilirsiniz
                        BluetoothDeviceListView(bluetoothManager: bluetoothManager)
                    }
                    .background(GeometryReader { geo -> Color in
                        DispatchQueue.main.async {
                            bluetoothButtonPosition = CGPoint(
                                x: geo.frame(in: .global).midX,
                                y: geo.frame(in: .global).midY
                            )
                        }
                        return Color.clear
                    })
                    
                    // Gyro Kontrol Butonu
                    Button(action: {
                        if isHapticFeedbackEnabled ?? true {
                            HapticFeedbackManager.shared.triggerImpact(style: .light)
                        }
                        if bluetoothManager.isConnected {
                            toggleGyroUpdates()
                        } else {
                            showMessage = "connect_bluetooth_first".localized
                            showToast = true
                        }
                    }) {
                        Text("gyro".localized)
                            .font(.title)
                            .padding()
                            .background(isControlling ? Color.red : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .background(GeometryReader { geo -> Color in
                        DispatchQueue.main.async {
                            gyroButtonPosition = CGPoint(
                                x: geo.frame(in: .global).midX,
                                y: geo.frame(in: .global).midY
                            )
                        }
                        return Color.clear
                    })
                }
            }
            .padding(20)
            Spacer()
            Text("\(combinedData)")
            
            HStack {
                // Sol joystick
                
                ZStack {
                    JoystickView(size: 250, joyStickOnChange: { translation, doubleValue in
                        
                        leftJoystickValue = translation
                        updateAndSendCombinedJoystickData()
                    }, type: .movement)
                    .background(GeometryReader { geo -> Color in
                        DispatchQueue.main.async {
                            leftJoystickPosition = CGPoint(
                                x: geo.frame(in: .global).midX,
                                y: geo.frame(in: .global).midY
                            )
                        }
                        return Color.clear
                    })
                       
                       // Fire Button
                       Button(action: {
                           if isHapticFeedbackEnabled ?? true {
                               HapticFeedbackManager.shared.triggerImpact(style: .light)
                           }
                           if bluetoothManager.isConnected {
                               if fireButtonValue == "F" {
                                   fireButtonValue = "f"
                                   triggerButtonValue = "t"
                               } else {
                                   fireButtonValue = "F"
                               }
                               updateAndSendCombinedJoystickData()
                           } else {
                               showMessage = "connect_bluetooth_first".localized
                               showToast = true
                           }
                       }) {
                           Image(systemName: "bolt.fill") // Uygun ikon
                               .resizable()
                               .frame(width: 40, height: 40)
                               .padding()
                               .background(fireButtonValue == "F" ? Color.red : Color.blue)
                               .clipShape(Circle())
                               .foregroundColor(.white)
                       }
                       .offset(x: 148, y: -80) // Sağ joystick'in sol üst köşesi için yerleşim
                       .background(GeometryReader { geo -> Color in
                           DispatchQueue.main.async {
                               fireButtonPosition = CGPoint(
                                   x: geo.frame(in: .global).midX,
                                   y: geo.frame(in: .global).midY
                               )
                           }
                           return Color.clear
                       })
                       
                       // Trigger Button
                       Button(action: {
                           if isHapticFeedbackEnabled ?? true {
                               HapticFeedbackManager.shared.triggerImpact(style: .light)
                           }
                           if bluetoothManager.isConnected {
                               if triggerButtonValue == "T" {
                                   triggerButtonValue = "t"
                               } else if fireButtonValue == "F" && triggerButtonValue == "t" {
                                   triggerButtonValue = "T"
                               } else {
                                   showMessage = "enable_fire_button_first".localized
                                   showToast = true
                               }
                               updateAndSendCombinedJoystickData()
                           } else {
                               showMessage = "connect_bluetooth_first".localized
                               showToast = true
                           }
                       }) {
                           Image(systemName: "flame.fill") // Uygun ikon
                               .resizable()
                               .frame(width: 40, height: 40)
                               .padding()
                               .background(triggerButtonValue == "T" ? Color.red : Color.blue)
                               .clipShape(Circle())
                               .foregroundColor(.white)
                       }
                       .offset(x: 168, y: 0) // Sağ joystick'in sol üst köşesi için yerleşim
                       .background(GeometryReader { geo -> Color in
                           DispatchQueue.main.async {
                               triggerButtonPosition = CGPoint(
                                   x: geo.frame(in: .global).midX,
                                   y: geo.frame(in: .global).midY
                               )
                           }
                           return Color.clear
                       })
                    
                    // Laser Button
                    Button(action: {
                        if isHapticFeedbackEnabled ?? true {
                            HapticFeedbackManager.shared.triggerImpact(style: .light)
                        }
                        if bluetoothManager.isConnected {
                            laserButtonValue = (laserButtonValue == "L") ? "l" : "L"
                            updateAndSendCombinedJoystickData()
                        } else {
                            showMessage = "connect_bluetooth_first".localized
                            showToast = true
                        }
                        
                    }) {
                        Image(systemName: "target") // Uygun ikon
                            .resizable()
                            .frame(width: 40, height: 40)
                            .padding()
                            .background(laserButtonValue == "L" ? Color.red : Color.blue)
                            .clipShape(Circle())
                            .foregroundColor(.white)
                    }
                    .offset(x: 148, y: 80)
                    .background(GeometryReader { geo -> Color in
                        DispatchQueue.main.async {
                            laserButtonPosition = CGPoint(
                                x: geo.frame(in: .global).midX,
                                y: geo.frame(in: .global).midY
                            )
                        }
                        return Color.clear
                    })
                }
                Spacer()
                
                JoystickView(joystickPosition: doubleValue, size: 250, joyStickOnChange: { translation, doubleValue in
                    self.doubleValue = doubleValue
                    rightJoystickValue = translation
                    updateAndSendCombinedJoystickData()
                }, type: .turret)
                .background(GeometryReader { geo -> Color in
                    DispatchQueue.main.async {
                        rightJoystickPosition = CGPoint(
                            x: geo.frame(in: .global).midX,
                            y: geo.frame(in: .global).midY
                        )
                    }
                    return Color.clear
                })
                
            }
        }
        .padding(.horizontal)
        .toast(isPresented: $showToast, message: $showMessage)
        .onAppear {
            if !hasCompletedOnboarding {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    showOnboardingIntro = true
                }
            }
        }
        .overlay {
            if showOnboardingIntro {
                StepByStepIntroView(
                    steps: onboardingIntroSteps,
                    currentStep: $onboardingIntroStep,
                    isPresented: $showOnboardingIntro,
                    onComplete: {
                        hasCompletedOnboarding = true
                    }
                )
            }
            
            if showOnboarding {
                ImprovedOnboardingView(
                    isPresented: $showOnboarding,
                    currentStep: $currentOnboardingStep,
                    onComplete: {
                        hasCompletedOnboarding = true
                        showOnboarding = false
                    },
                    positions: [
                        infoButtonPosition,
                        settingsButtonPosition,
                        bluetoothButtonPosition,
                        gyroButtonPosition,
                        leftJoystickPosition,
                        laserButtonPosition,
                        fireButtonPosition,
                        triggerButtonPosition,
                        rightJoystickPosition
                    ]
                )
            }
        }
    }
    
    // Joystick verilerini birleştirip Bluetooth'a gönderir
    func updateAndSendCombinedJoystickData() {
        combinedData = "\(leftJoystickValue);\(rightJoystickValue);\(laserButtonValue)\(fireButtonValue)\(triggerButtonValue)"
        bluetoothManager.updateJoystickValue(value: combinedData)
        debugPrint(combinedData)
    }
    
    // Gelen değerlerin sınırlandırılması
    private func constrain(_ value: Int, min: Int, max: Int) -> Int {
        return Swift.min(Swift.max(value, min), max)
    }
}

// Geliştirilmiş Onboarding ekranı
struct ImprovedOnboardingView: View {
    @Binding var isPresented: Bool
    @Binding var currentStep: Int
    var onComplete: () -> Void
    var positions: [CGPoint]
    
    // Onboarding adımları
    let steps = [
        OnboardingStep(
            title: "Bilgi Butonu",
            description: "Uygulama hakkında bilgi almak için bu butona tıklayın.",
            icon: "info.circle"
        ),
        OnboardingStep(
            title: "Ayarlar Butonu",
            description: "Uygulama ayarlarını değiştirmek için bu butona tıklayın.",
            icon: "gear.circle"
        ),
        OnboardingStep(
            title: "Bluetooth Bağlantısı",
            description: "Aracınıza bağlanmak için bu butona tıklayın.",
            icon: "cable.connector"
        ),
        OnboardingStep(
            title: "Gyro Kontrolü",
            description: "Jiroskop ile kontrol etmek için bu butona tıklayın.",
            icon: "gyroscope"
        ),
        OnboardingStep(
            title: "Sol Joystick",
            description: "Aracın hareketini kontrol etmek için kullanılır.",
            icon: "arrow.up.and.down.and.arrow.left.and.right"
        ),
        OnboardingStep(
            title: "Lazer Butonu",
            description: "Lazeri açıp kapatmak için kullanılır.",
            icon: "target"
        ),
        OnboardingStep(
            title: "Ateş Butonu",
            description: "Ateş etmek için kullanılır.",
            icon: "bolt.fill"
        ),
        OnboardingStep(
            title: "Tetik Butonu",
            description: "Ateş etmeyi tetiklemek için kullanılır.",
            icon: "flame.fill"
        ),
        OnboardingStep(
            title: "Sağ Joystick",
            description: "Taret kontrolü için kullanılır.",
            icon: "arrow.up.and.down.and.arrow.left.and.right"
        )
    ]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Yarı saydam arka plan
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                
                // Mevcut adımı göster
                if currentStep < steps.count && currentStep < positions.count {
                    let step = steps[currentStep]
                    let position = positions[currentStep]
                    
                    // Pozisyon geçerli ise göster
                    if position != .zero {
                        // Vurgulanan öğe
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: 80, height: 80)
                            .position(position)
                        
                        // Bilgi kartı
                        VStack(alignment: .center, spacing: 10) {
                            Image(systemName: step.icon)
                                .font(.largeTitle)
                                .foregroundColor(.white)
                            
                            Text(step.title)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text(step.description)
                                .font(.body)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                            
                            HStack(spacing: 20) {
                                // Önceki buton
                                if currentStep > 0 {
                                    Button("Önceki") {
                                        withAnimation {
                                            currentStep -= 1
                                        }
                                    }
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                                
                                // Sonraki/Bitir buton
                                Button(currentStep == steps.count - 1 ? "Bitir" : "Sonraki") {
                                    withAnimation {
                                        if currentStep == steps.count - 1 {
                                            onComplete()
                                        } else {
                                            currentStep += 1
                                        }
                                    }
                                }
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                                
                                // Atla butonu
                                Button("Atla") {
                                    onComplete()
                                }
                                .padding()
                                .background(Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                        }
                        .padding()
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(15)
                        .shadow(radius: 10)
                        .frame(width: min(geometry.size.width * 0.4, 400))
                        .position(calculateInfoCardPosition(for: position, in: geometry))
                    }
                }
            }
        }
    }
    
    // Bilgi kartının pozisyonunu hesapla
    private func calculateInfoCardPosition(for elementPosition: CGPoint, in geometry: GeometryProxy) -> CGPoint {
        let size = geometry.size
        
        // Ekranın merkezi
        let centerX = size.width / 2
        let centerY = size.height / 2
        
        // Bileşenin merkeze göre konumu
        let isLeft = elementPosition.x < centerX
        let isTop = elementPosition.y < centerY
        
        // Güvenli kenar boşlukları
        let horizontalPadding: CGFloat = 30
        let verticalPadding: CGFloat = 30
        
        // Bilgi kartının boyutları (yaklaşık)
        let cardWidth = min(size.width * 0.4, 400)
        let cardHeight: CGFloat = 250 // Yaklaşık yükseklik
        
        // Kartın x pozisyonu
        let cardX: CGFloat
        if isLeft {
            // Bileşen solda, kart sağda
            cardX = size.width - cardWidth/2 - horizontalPadding
        } else {
            // Bileşen sağda, kart solda
            cardX = cardWidth/2 + horizontalPadding
        }
        
        // Kartın y pozisyonu
        let cardY: CGFloat
        if isTop {
            // Bileşen üstte, kart altta
            cardY = size.height - cardHeight/2 - verticalPadding
        } else {
            // Bileşen altta, kart üstte
            cardY = cardHeight/2 + verticalPadding
        }
        
        // Özel durumlar için ayarlamalar
        // Joystick ve çevresindeki butonlar için özel ayarlamalar
        if currentStep >= 4 && currentStep <= 8 {
            // Sol joystick ve çevresi
            if currentStep == 4 || (currentStep >= 5 && currentStep <= 7) {
                return CGPoint(x: size.width * 0.75, y: centerY)
            }
            // Sağ joystick
            else if currentStep == 8 {
                return CGPoint(x: size.width * 0.25, y: centerY)
            }
        }
        
        return CGPoint(x: cardX, y: cardY)
    }
}

// Basitleştirilmiş Onboarding adımı modeli
struct OnboardingStep {
    let title: String
    let description: String
    let icon: String
}

// Her buton için tam ekran intro view
struct StepByStepIntroView: View {
    let steps: [OnboardingStep]
    @Binding var currentStep: Int
    @Binding var isPresented: Bool
    var onComplete: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                Image(systemName: steps[currentStep].icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue.opacity(0.5))
                    .clipShape(Circle())
                Text(steps[currentStep].title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(steps[currentStep].description)
                    .font(.title3)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Spacer()
                HStack(spacing: 24) {
                    Button("Atla") {
                        isPresented = false
                        onComplete()
                    }
                    .font(.title2)
                    .frame(minWidth: 100, minHeight: 44)
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    if currentStep > 0 {
                        Button("Geri") {
                            withAnimation { currentStep -= 1 }
                        }
                        .font(.title2)
                        .frame(minWidth: 100, minHeight: 44)
                        .background(Color.blue.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    Button(currentStep == steps.count - 1 ? "Bitir" : "Sonraki") {
                        withAnimation {
                            if currentStep == steps.count - 1 {
                                isPresented = false
                                onComplete()
                            } else {
                                currentStep += 1
                            }
                        }
                    }
                    .font(.title2)
                    .frame(minWidth: 100, minHeight: 44)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
    }
}
