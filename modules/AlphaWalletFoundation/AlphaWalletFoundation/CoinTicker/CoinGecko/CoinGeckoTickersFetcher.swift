//
//  CoinGeckoTickersFetcher.swift
//  AlphaWallet
//
//  Created by Vladyslav Shepitko on 24.05.2022.
//

import Combine
import Foundation
import AlphaWalletCore

public final class CoinGeckoTickersFetcher: BaseCoinTickersFetcher, CoinTickersFetcherProvider {
    public convenience init(storage: CoinTickersStorage & ChartHistoryStorage & TickerIdsStorage, transporter: ApiTransporter) {
        let networking: CoinTickerNetworking
        if isRunningTests() {
            networking = FakeCoinTickerNetworking()
        } else {
            networking = BaseCoinTickerNetworking(transporter: transporter)
        }

        let supportedTickerIdsFetcher = SupportedTickerIdsFetcher(networking: networking, storage: storage, config: Config())
        let fileTokenEntriesProvider = FileTokenEntriesProvider()

        let tickerIdsFetcher: TickerIdsFetcher = TickerIdsFetcherImpl(providers: [
            InMemoryTickerIdsFetcher(storage: storage),
            supportedTickerIdsFetcher,
            AlphaWalletRemoteTickerIdsFetcher(provider: fileTokenEntriesProvider, tickerIdsFetcher: supportedTickerIdsFetcher)
        ])

        self.init(networking: networking, storage: storage, tickerIdsFetcher: tickerIdsFetcher)
    }
}
