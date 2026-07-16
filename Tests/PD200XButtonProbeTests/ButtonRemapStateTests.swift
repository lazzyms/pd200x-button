import XCTest
@testable import PD200XButtonProbe

final class ButtonRemapStateTests: XCTestCase {
    func testStartupWhileMutedOnlyRestoresAudioAndDoesNotToggleHandy() {
        let started = transition(ButtonRemapState(), .start).state
        let result = transition(started, .observedMute(true))

        XCTAssertEqual(result.effects, [.forceUnmute])
        XCTAssertFalse(result.state.isArmed)
    }

    func testEachArmedMutePressProducesOneHandyToggle() {
        var state = transition(ButtonRemapState(), .start).state
        state = transition(state, .observedMute(false)).state

        let firstPress = transition(state, .observedMute(true))
        XCTAssertEqual(firstPress.effects, [.forceUnmute, .buttonPressed])
        XCTAssertFalse(firstPress.state.isArmed)

        state = transition(firstPress.state, .observedMute(false)).state
        let secondPress = transition(state, .observedMute(true))
        XCTAssertEqual(secondPress.effects, [.forceUnmute, .buttonPressed])
    }
}
