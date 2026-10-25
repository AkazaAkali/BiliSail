import Cocoa
import FlutterMacOS
import XCTest
@testable import BiliSail

class RunnerTests: XCTestCase {

  func testRepeatedQuitWaitsForCleanupApproval() {
    var scheduled: [() -> Void] = []
    let coordinator = ApplicationTerminationCoordinator(scheduleTermination: { scheduled.append($0) })
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
    XCTAssertEqual(terminations, 0)
    XCTAssertEqual(scheduled.count, 1)
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    XCTAssertEqual(requests, 1)
    scheduled.removeFirst()()
    XCTAssertEqual(terminations, 1)
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateNow)
    XCTAssertEqual(requests, 1)
  }

  func testCancelledQuitCanBeRequestedAgain() {
    let coordinator = ApplicationTerminationCoordinator(scheduleTermination: { _ in
      XCTFail("Cancelled cleanup must not schedule termination")
    })
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

  func testSynchronousCleanupStillDefersTermination() {
    var scheduled: [() -> Void] = []
    let coordinator = ApplicationTerminationCoordinator(scheduleTermination: { scheduled.append($0) })
    var requesting = false
    var terminations = 0
    let request: (@escaping (Bool) -> Void) -> Void = { callback in
      requesting = true
      callback(true)
      requesting = false
    }
    let terminate = {
      XCTAssertFalse(requesting)
      terminations += 1
    }
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    XCTAssertEqual(terminations, 0)
    XCTAssertEqual(scheduled.count, 1)
    scheduled.removeFirst()()
    XCTAssertEqual(terminations, 1)
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateNow)
  }

  func testDefaultSchedulerLeavesTheCleanupReplyBeforeTerminating() {
    let coordinator = ApplicationTerminationCoordinator()
    let terminated = expectation(description: "Termination runs on the main queue")
    var replying = false
    XCTAssertEqual(coordinator.requestExit(using: { callback in
      replying = true
      callback(true)
      replying = false
    }, terminate: {
      XCTAssertFalse(replying)
      XCTAssertTrue(Thread.isMainThread)
      terminated.fulfill()
    }), .terminateCancel)
    wait(for: [terminated], timeout: 2)
  }

}
