//
//  JoystickRCVehicleUITests.swift
//  JoystickRCVehicleUITests
//
//  Created by Onder Guler on 24.09.2024.
//

import XCTest

final class JoystickRCVehicleUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testControlSurfaceAndSettings() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()

        let modePicker = app.segmentedControls["connectionModePicker"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["connectionButton"].exists)
        XCTAssertTrue(app.staticTexts["commandReadout"].exists)
        XCTAssertTrue(app.otherElements["movementJoystickArea"].exists)
        XCTAssertTrue(app.otherElements["turretJoystickArea"].exists)
        XCTAssertTrue(app.buttons["laserButton"].exists)
        XCTAssertTrue(app.buttons["fireButton"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["triggerButton"].exists)

        modePicker.buttons.element(boundBy: 1).tap()
        app.buttons["connectionButton"].tap()
        XCTAssertTrue(app.textFields["wifiSSIDField"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.secureTextFields["wifiPasswordField"].exists)
        XCTAssertTrue(app.textFields["wifiHostField"].exists)
        XCTAssertTrue(app.textFields["wifiPortField"].exists)
        XCTAssertTrue(app.buttons["wifiConnectButton"].exists)
        app.buttons["wifiCloseButton"].tap()

        modePicker.buttons.element(boundBy: 0).tap()
        app.buttons["connectionButton"].tap()
        XCTAssertTrue(app.buttons["bluetoothCloseButton"].waitForExistence(timeout: 3))
        app.buttons["bluetoothCloseButton"].tap()

        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.sliders["movementSensitivitySlider"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.sliders["turretSensitivitySlider"].exists)
    }

    @MainActor
    func testEdgeTouchStartsJoystickAtNeutral() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()

        let readout = app.staticTexts["commandReadout"]
        let turretArea = app.otherElements["turretJoystickArea"]
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        XCTAssertTrue(turretArea.exists)
        XCTAssertEqual(readout.label, "0,0;0,0;0")

        turretArea
            .coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
            .tap()

        XCTAssertEqual(readout.label, "0,0;0,0;0")
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
