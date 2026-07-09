import XCTest
@testable import LVRead

final class PaperCurlPhysicsTests: XCTestCase {

    func testShortSlowDragReturnsToCurrentPage() {
        XCTAssertFalse(
            PaperCurlPhysics.shouldCommit(
                progress: 0.20,
                velocityX: -200,
                direction: .next
            )
        )
    }

    func testDistanceThresholdCommits() {
        XCTAssertTrue(
            PaperCurlPhysics.shouldCommit(
                progress: 0.24,
                velocityX: 0,
                direction: .next
            )
        )
    }

    func testFastVelocityInCorrectDirectionCommits() {
        XCTAssertTrue(
            PaperCurlPhysics.shouldCommit(
                progress: 0.10,
                velocityX: -700,
                direction: .next
            )
        )
        XCTAssertTrue(
            PaperCurlPhysics.shouldCommit(
                progress: 0.10,
                velocityX: 700,
                direction: .prev
            )
        )
    }

    func testOppositeVelocityDoesNotCommit() {
        XCTAssertFalse(
            PaperCurlPhysics.shouldCommit(
                progress: 0.10,
                velocityX: 700,
                direction: .next
            )
        )
    }

    func testProgressIsClamped() {
        XCTAssertEqual(
            PaperCurlPhysics.progress(translationX: -500, pageWidth: 400),
            1
        )
        XCTAssertEqual(
            PaperCurlPhysics.progress(translationX: 100, pageWidth: 0),
            0
        )
    }

    func testCompletionDurationIsBounded() {
        let duration = PaperCurlPhysics.completionDuration(
            progress: 0.25,
            velocityX: -700,
            pageWidth: 400
        )
        XCTAssertGreaterThanOrEqual(duration, 0.18)
        XCTAssertLessThanOrEqual(duration, 0.48)
    }
}
