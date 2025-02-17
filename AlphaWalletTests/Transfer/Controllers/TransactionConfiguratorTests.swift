// Copyright SIX DAY LLC. All rights reserved.

import XCTest
@testable import AlphaWallet
import BigInt
import AlphaWalletFoundation

class TransactionConfiguratorTests: XCTestCase {
    func testAdjustGasPrice() {
        let gasPrice = BigUInt(1000000000)
        let analytics = FakeAnalyticsService()
        let configurator = TransactionConfigurator(
            session: .make(),
            analytics: analytics,
            transaction: .make(gasPrice: .legacy(gasPrice: gasPrice)),
            networkService: FakeNetworkService(),
            tokensService: WalletDataProcessingPipeline.make(wallet: .make(), server: .main).pipeline,
            configuration: .sendFungiblesTransaction(confirmType: .signThenSend))

        XCTAssertEqual(gasPrice, configurator.currentConfiguration.gasPrice)
    }

    func testMinGasPrice() {
        let analytics = FakeAnalyticsService()
        let configurator = TransactionConfigurator(
            session: .make(),
            analytics: analytics,
            transaction: .make(gasPrice: .legacy(gasPrice: BigUInt(1000000000))),
            networkService: FakeNetworkService(),
            tokensService: WalletDataProcessingPipeline.make(wallet: .make(), server: .main).pipeline,
            configuration: .sendFungiblesTransaction(confirmType: .signThenSend))

        XCTAssertEqual(GasPriceConfiguration.minPrice, configurator.currentConfiguration.gasPrice)
    }

    func testMaxGasPrice() {
        let analytics = FakeAnalyticsService()
        let configurator = TransactionConfigurator(
            session: .make(),
            analytics: analytics,
            transaction: .make(gasPrice: .legacy(gasPrice: BigUInt(990000000000))),
            networkService: FakeNetworkService(),
            tokensService: WalletDataProcessingPipeline.make(wallet: .make(), server: .main).pipeline,
            configuration: .sendFungiblesTransaction(confirmType: .signThenSend))

        XCTAssertEqual(GasPriceConfiguration.maxPrice, configurator.currentConfiguration.gasPrice)
    }

    func testSendEtherGasPriceAndLimit() {
        let analytics = FakeAnalyticsService()
        let configurator = TransactionConfigurator(
            session: .make(),
            analytics: analytics,
            transaction: .make(gasLimit: nil, gasPrice: nil),
            networkService: FakeNetworkService(),
            tokensService: WalletDataProcessingPipeline.make(wallet: .make(), server: .main).pipeline,
            configuration: .sendFungiblesTransaction(confirmType: .signThenSend))
        XCTAssertEqual(BigUInt(GasPriceConfiguration.defaultPrice), configurator.currentConfiguration.gasPrice)
        //gas limit is always 21k for native ether transfers
        XCTAssertEqual(BigUInt(21000), configurator.currentConfiguration.gasLimit)
    }
}
