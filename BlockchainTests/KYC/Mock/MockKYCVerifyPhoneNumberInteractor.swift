//
//  MockKYCVerifyPhoneNumberInteractor.swift
//  BlockchainTests
//
//  Created by Chris Arriola on 7/31/18.
//  Copyright © 2018 Blockchain Luxembourg S.A. All rights reserved.
//

import RxSwift
import PlatformKit

class MockKYCVerifyPhoneNumberInteractor: KYCVerifyPhoneNumberInteractor {
    var shouldSucceed = true

    override func startVerification(number: String) -> Completable {
        if shouldSucceed {
            return Completable.empty()
        } else {
            return Completable.error(HTTPRequestServerError.badResponse)
        }
    }

    override func verifyNumber(with code: String) -> Completable {
        if shouldSucceed {
            return Completable.empty()
        } else {
            return Completable.error(HTTPRequestServerError.badResponse)
        }
    }
}
