import XCTest
@testable import PD200XTarget

final class TargetActionPlannerTests: XCTestCase {
    private let planner = TargetActionPlanner()

    func testHandyStopTogglesThenSubmitsAfterConfiguredDelay() throws {
        let configuration = TargetConfiguration(
            kind: .handy,
            submitWithEnter: true,
            submitDelayMilliseconds: 2_000
        )

        XCTAssertEqual(
            try planner.toggleActions(configuration: configuration, isStopping: true),
            [.handyToggle, .wait(milliseconds: 2_000), .pressEnter]
        )
    }

    func testStartingNeverSubmits() throws {
        XCTAssertEqual(
            try planner.toggleActions(configuration: .default, isStopping: false),
            [.handyToggle]
        )
    }

    func testNativeDictationUsesSameConfiguredShortcutForStartAndStop() throws {
        let configuration = TargetConfiguration(
            kind: .macOSDictation,
            submitWithEnter: false,
            nativeShortcut: .controlTwice
        )

        let expected = [TargetAction.shortcut(
            KeyboardShortcut(key: "control", pressCount: 2)
        )]
        XCTAssertEqual(
            try planner.toggleActions(configuration: configuration, isStopping: false),
            expected
        )
        XCTAssertEqual(
            try planner.toggleActions(configuration: configuration, isStopping: true),
            expected
        )
    }

    func testCustomTargetSupportsDifferentStartAndStopShortcuts() throws {
        let configuration = TargetConfiguration(
            kind: .customShortcut,
            submitWithEnter: false,
            customStartShortcut: "command+shift+d",
            customStopShortcut: "control control"
        )

        XCTAssertEqual(
            try planner.toggleActions(configuration: configuration, isStopping: false),
            [.shortcut(KeyboardShortcut(
                key: "d",
                modifiers: [.command, .shift]
            ))]
        )
        XCTAssertEqual(
            try planner.toggleActions(configuration: configuration, isStopping: true),
            [.shortcut(KeyboardShortcut(key: "control", pressCount: 2))]
        )
    }

    func testInvalidCustomShortcutReturnsHelpfulError() {
        let configuration = TargetConfiguration(
            kind: .customShortcut,
            customStartShortcut: "hyper+banana"
        )

        XCTAssertThrowsError(
            try planner.toggleActions(configuration: configuration, isStopping: false)
        )
    }
}
