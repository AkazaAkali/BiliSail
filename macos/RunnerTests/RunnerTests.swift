import Cocoa
import FlutterMacOS
import XCTest
@testable import BiliSail

class RunnerTests: XCTestCase {

  func testRepeatedQuitWaitsForCleanupApproval() {
    let coordinator = ApplicationTerminationCoordinator()
    var reply: ((Bool) -> Void)?
    var requests = 0
    var terminations = 0
    let request: (@escaping (Bool) -> Void) -> Void = { callback in
      requests += 1
      reply = callback
    }
    let terminate = { terminations += 1 }
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    XCTAssertEqual(requests, 1)
    XCTAssertEqual(terminations, 0)
    reply?(true)
    XCTAssertEqual(terminations, 1)
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateNow)
    XCTAssertEqual(requests, 1)
  }

  func testCancelledQuitCanBeRequestedAgain() {
    let coordinator = ApplicationTerminationCoordinator()
    var reply: ((Bool) -> Void)?
    var requests = 0
    let request: (@escaping (Bool) -> Void) -> Void = { callback in
      requests += 1
      reply = callback
    }
    let terminate = { XCTFail("Cancelled cleanup must keep the application open") }
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    reply?(false)
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    XCTAssertEqual(requests, 2)
    reply?(false)
  }

}
