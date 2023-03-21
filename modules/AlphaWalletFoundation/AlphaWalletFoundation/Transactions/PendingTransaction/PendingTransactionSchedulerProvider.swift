//
//  PendingTransactionSchedulerProvider.swift
//  AlphaWallet
//
//  Created by Vladyslav Shepitko on 04.04.2022.
//

import Foundation
import Combine
import CombineExt
import AlphaWalletCore

final class PendingTransactionSchedulerProvider: SchedulerProvider {
    private let fetchPendingTransactionsQueue: OperationQueue
    private let blockchainProvider: BlockchainProvider
    private let responseSubject = PassthroughSubject<Swift.Result<EthereumTransaction, SessionTaskError>, Never>()

    var interval: TimeInterval { return Constants.Covalent.pendingTransactionUpdateInterval }
    var name: String { "PendingTransactionSchedulerProvider" }
    var operation: AnyPublisher<Void, PromiseError> {
        return fetchPublisher()
    }

    let transaction: TransactionInstance

    var responsePublisher: AnyPublisher<Swift.Result<EthereumTransaction, SessionTaskError>, Never> {
        responseSubject.eraseToAnyPublisher()
    }

    init(blockchainProvider: BlockchainProvider,
         transaction: TransactionInstance,
         fetchPendingTransactionsQueue: OperationQueue) {

        self.blockchainProvider = blockchainProvider
        self.fetchPendingTransactionsQueue = fetchPendingTransactionsQueue
        self.transaction = transaction
    }

    private func fetchPublisher() -> AnyPublisher<Void, PromiseError> {
        return Future { [blockchainProvider, transaction] in try await blockchainProvider.transaction(byHash: transaction.id) }
            .subscribe(on: fetchPendingTransactionsQueue)
            .handleEvents(receiveOutput: { [weak self] pendingTransaction in
                //We can't just delete the pending transaction because it might be valid, just that the RPC node doesn't know about it
                guard let tx = pendingTransaction, let blockNumber = Int(tx.blockNumber), blockNumber > 0  else { return }

                self?.handle(response: .success(tx))
            }, receiveCompletion: { [weak self] result in
                guard case .failure(let error) = result, let e = error as? SessionTaskError else { return }
                
                self?.handle(response: .failure(e))
            })
            .mapToVoid()
            .mapError { PromiseError(error: $0) }
            .eraseToAnyPublisher()
    }

    private func handle(response: Swift.Result<EthereumTransaction, SessionTaskError>) {
        responseSubject.send(response)
    }
}
