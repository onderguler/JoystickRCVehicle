# App Store Submission Notes

## Rejection Resolution

Submission `787f034d-dd6c-48ec-88da-d56068ea2987`, reviewed on May 5, 2025, identified three issues.

### Guideline 2.1 - App Completeness

The previous description did not explain the app's features sufficiently. Complete English and Turkish descriptions are now stored under `fastlane/metadata`. They explain:

- The compatible custom RC vehicle requirement.
- Bluetooth Low Energy and Wi-Fi UDP connection modes.
- Driving, turret, sensitivity, gyroscope, and auxiliary controls.
- Connection safety behavior and the limits of operation without hardware.
- The absence of accounts, advertising, analytics, tracking, and cloud services.

### Guideline 5.1.1 - Bluetooth Purpose String

The Bluetooth purpose string now identifies the protected resource, explains why it is needed, and gives a concrete example: moving a joystick sends driving and turret commands to the selected RC vehicle. English and Turkish purpose strings provide the same level of detail.

### Guideline 5.2.5 - Apple Intellectual Property

Use `BLE & Wi-Fi RC Controller` as the subtitle for every App Store localization. It contains no Apple product or service name. Remove the previous subtitle from App Store Connect rather than appending this text to it.

## App Store Connect Metadata

- App name: `RC Joystick: WiFi and BLE`
- Subtitle: `BLE & Wi-Fi RC Controller`
- Primary category: `Utilities`
- Build number: `8`
- Support URL and privacy policy URL must be valid and publicly accessible.
- Screenshots must show both connection modes and the actual control interface.

Changing project files does not update existing App Store Connect metadata. Replace the name, subtitle, description, category, keywords, screenshots, and build selection in App Store Connect before resubmitting.

## App Review Notes

Add a working demonstration-video URL and the actual test hardware credentials separately in App Store Connect. Do not submit bracketed placeholders.

The following review note is ready to use without placeholders:

> RC Joystick: WiFi and BLE controls a user-owned compatible RC vehicle. It connects either through Bluetooth Low Energy or directly to the vehicle's local Wi-Fi network and sends control commands only to that vehicle. No account is required. The app contains no advertising, analytics, tracking, purchases, or cloud data transfer. Bluetooth access discovers and connects to the compatible vehicle; for example, moving a joystick sends driving and turret commands to the selected vehicle. Local network and Hotspot Configuration access are used only to join the vehicle network and send UDP commands. Compatible hardware is required for live motor, turret, and auxiliary-output operation. Test hardware details and the demonstration video are supplied in the App Review Information section.

Supply these review resources before submission:

1. Exact BLE peripheral name.
2. Test Wi-Fi SSID, password, IP address, and UDP port.
3. Public video showing Bluetooth connection, Wi-Fi connection, joystick control, and safe stop after disconnect.
4. Physical review hardware if App Review requests it.

## Reply To App Review

> Hello App Review Team. We addressed all three issues in this submission. For Guideline 2.1, the App Store description now fully explains the compatible-hardware requirement, Bluetooth and Wi-Fi connection modes, driving and turret controls, sensitivity settings, gyroscope control, auxiliary controls, and safe-disconnect behavior. For Guideline 5.1.1, the Bluetooth purpose string now explains that Bluetooth discovers and connects to a compatible RC vehicle and includes the specific example that moving a joystick sends driving and turret commands to the selected vehicle. For Guideline 5.2.5, we removed the previous Apple product term from every subtitle and replaced it with "BLE & Wi-Fi RC Controller." We also updated the screenshots and review information to reflect the final app. Thank you for reviewing the revised submission.

## Additional Privacy Compliance

`PrivacyInfo.xcprivacy` declares app-local `UserDefaults` access with reason `CA92.1` and elapsed-time measurement through `systemUptime` with reason `35F9.1`. The manifest declares no tracking and no collected data.
