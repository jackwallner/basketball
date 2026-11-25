import Foundation
import RevenueCat
import XCTest
@testable import Hardwood_StatScout

/// Ask to Buy reads as waiting, not as a failure, and no purchase error shows
/// RevenueCat's English description or a stale `lastError`.
final class PurchaseFailureTests: XCTestCase {
    func testAskToBuyIsWaitingForApproval() {
        let shown = PurchaseFailure(RevenueCat.ErrorCode.paymentPendingError)
        XCTAssertEqual(shown, .pendingApproval)
        XCTAssertEqual(shown.message, "Waiting for approval. Your purchase unlocks once it is approved.")
    }

    func testPendingCopyIsCalm() {
        let message = PurchaseFailure.pendingApprovalMessage.lowercased()
        for word in ["error", "fail", "couldn't", "try again", "pending"] {
            XCTAssertFalse(message.contains(word), word)
        }
    }

    func testLostConnectionSaysSo() {
        let expected = PurchaseFailure.failed(PurchaseFailure.unreachableMessage)
        XCTAssertEqual(PurchaseFailure(RevenueCat.ErrorCode.networkError), expected)
        XCTAssertEqual(PurchaseFailure(RevenueCat.ErrorCode.offlineConnectionError), expected)
        XCTAssertEqual(PurchaseFailure(URLError(.notConnectedToInternet)), expected)
        XCTAssertTrue(PurchaseFailure.unreachableMessage.contains("connection"))
    }

    func testOtherErrorsKeepTheExistingLine() {
        let generic = PurchaseFailure.failed("Couldn't complete the purchase. Please try again.")
        XCTAssertEqual(PurchaseFailure(RevenueCat.ErrorCode.purchaseNotAllowedError), generic)
        XCTAssertEqual(PurchaseFailure(RevenueCat.ErrorCode.storeProblemError), generic)
        XCTAssertEqual(PurchaseFailure(NSError(domain: "x", code: 1)), generic)
        XCTAssertEqual(
            PurchaseFailure(StoreServiceError.purchasesUnavailableInSimulator).message,
            "Purchases are unavailable in simulator builds."
        )
    }
}
