//
//  SomeComponent.swift
//  AlphaWallet
//
//  Created by Vladyslav Shepitko on 19.02.2022.
//

import Foundation
import Combine
import RealmSwift

extension XMLHandler {
    static func xmlHandlerForActivity(token: Token, assetDefinitionStore: AssetDefinitionStore) -> XMLHandler? {
        let xmlHandler = XMLHandler(token: token, assetDefinitionStore: assetDefinitionStore)
        guard xmlHandler.hasAssetDefinition, xmlHandler.server?.matches(server: token.server) ?? false else { return nil }
        return xmlHandler
    }
}

class SomeComponent {
    private let tokensDataStore: TokensDataStore
    private let assetDefinitionStore: AssetDefinitionStore
    private var cancelable = Set<AnyCancellable>()
    private let tokenHolderStore: TokenHolderStore
    private let activityObjectFactory: ActivityObjectFactory
    private let eventsActivityDataStore: EventsActivityDataStoreProtocol
    private let activityDataStore: ActivityDataStoreProtocol
    private let config: Config
    private let wallet: Wallet
    private let transactionDataStore: TransactionDataStore
    private let queue = DispatchQueue.init(label: "q1")

    init(transactionDataStore: TransactionDataStore, activityDataStore: ActivityDataStoreProtocol, eventsActivityDataStore: EventsActivityDataStoreProtocol, activityObjectFactory: ActivityObjectFactory, eventsDataStore: NonActivityEventsDataStore, tokensDataStore: TokensDataStore, assetDefinitionStore: AssetDefinitionStore, config: Config, wallet: Wallet) {
        self.tokensDataStore = tokensDataStore
        self.assetDefinitionStore = assetDefinitionStore
        self.tokenHolderStore = TokenHolderStore(eventsDataStore: eventsDataStore, assetDefinitionStore: assetDefinitionStore, wallet: wallet)
        self.activityObjectFactory = activityObjectFactory
        self.eventsActivityDataStore = eventsActivityDataStore
        self.activityDataStore = activityDataStore
        self.transactionDataStore = transactionDataStore
        self.config = config
        self.wallet = wallet
    }

    func handleActivitiesFromEvents(forTransactionsFilterStrategy transactionsFilterStrategy: TransactionsFilterStrategy) {
        //NOTE: test only
        //activityDataStore.removeAll()

        let recentEvents = eventsActivityDataStore
            .recentEventsChangeset
            .map { _ in }
            .breakpoint(receiveOutput: { change in
                print("XXX.0: pass events")
                return false
            })

        let transactions = transactionDataStore
            .transactionsChangeset(forFilter: transactionsFilterStrategy, servers: Config().enabledServers)
            .map { _ in }
            .breakpoint(receiveOutput: { change in
                print("XXX.0: pass transactions")
                return false
            })

        let tokenCards = tokenCardsPublisher(for: transactionsFilterStrategy, wallet: wallet)
            .breakpoint(receiveOutput: { change in
                print("XXX.0: pass token cards")
                return false
            })

        tokenCards.combineLatest(recentEvents, transactions)
        .map { (contractsAndCards, _, _) -> ContractsAndCards in return contractsAndCards }
        .breakpoint(receiveOutput: { change in
            print("XXX.0: after all tokencards: \(change.count)")
            return false
        })
        .receive(on: queue)
        .map { self.createDataBaseActivityObjects(contractsAndCards: $0) }
//        .receive(on: RunLoop.main)
        .sink { activities in
            print("XXX: did add \(activities.count) activities")
//            print("XXX.0: did sink")
            self.activityDataStore.add(activities: activities)
        }.store(in: &cancelable)

//        tokenCardsPublisher(for: transactionsFilterStrategy, wallet: wallet)
//            .map { self.createDataBaseActivityObjects(contractsAndCards: $0) }
//            .receive(on: DispatchQueue.main)
//            .sink { activities in
//                print("XXX: did add \(activities.count) activities")
//                self.activityDataStore.add(activities: activities)
//            }.store(in: &cancelable)
    }

    private func createDataBaseActivityObjects(contractsAndCards: ContractsAndCards) -> [ActivityObject] {
        return contractsAndCards.map { (token, server, card, interpolatedFilter) -> [ActivityObject] in
            eventsActivityDataStore
                .getRecentEventsSortedByBlockNumber(for: card.eventOrigin.contract, server: server, eventName: card.eventOrigin.eventName, interpolatedFilter: interpolatedFilter)
                .compactMap {
                    guard let activity = activityObjectFactory.createActivity(from: $0, server: server, token: token, card: card, interpolatedFilter: interpolatedFilter), activityDataStore.activityNotExists(activity: activity) else { return nil }
                    return activity
                }
        }.flatMap { $0 }
    }

    private func tokenCardsPublisher(for transactionsFilterStrategy: TransactionsFilterStrategy, wallet: Wallet) -> AnyPublisher<ContractsAndCards, Never> {
        return Just(transactionsFilterStrategy)
            .flatMap { self.tokensDataStore.tokensForActivitiesChangeset(forStrategy: $0) }
            .filter(SomeFilter.initialOrNewOrDelatedTokens(change:))
            .map { changeset -> [Token] in
                switch changeset {
                case .initial(let tokens): return tokens
                case .update(let tokens, _, _, _): return tokens
                case .error: return []
                }
            }
//            .receive(on: RunLoop.main)
            .map { tokens -> ContractsAndCards in
                let contractServerXmlHandlers = tokens
                    .compactMap { token -> (token: Token, xmlHandler: XMLHandler)? in
                        guard let xmlHandler = XMLHandler.xmlHandlerForActivity(token: token, assetDefinitionStore: self.assetDefinitionStore) else { return nil }
                        self.tokenHolderStore.createHolderIfNeeded(for: token) //NOTE: create tokenHolder if needed

                        return (token: token, xmlHandler: xmlHandler)
                    }

                return XMLHandlerEventMapper(config: self.config, wallet: wallet)
                    .convert(contractServerXmlHandlers: contractServerXmlHandlers)
            }.eraseToAnyPublisher()
    }

    func handleUpdateActivitiesForTokenHandlerAttribuesChange() {
        activityDataStore
            .newActivitiesChangeset(strategy: .noFilter)
            .receive(on: queue)
            .filter(SomeFilter.newActivities(change:))
            .map { changeset -> [Activity] in
                switch changeset {
                case .initial(let activities): return activities
                case .update(let activities, _, let insertions, _): return insertions.map { activities[$0] }
                case .error: return []
                }
            }.sink { [queue, tokenHolderStore, activityDataStore] activities in
                print("XXX: update activities: \(activities.count)")

                for activity in activities {
                    let token = activity.token
                    guard let tokenHolder = tokenHolderStore.tokenHolders(for: token).first else { continue }
                    let attributeValues = AssetAttributeValues(attributeValues: tokenHolder.values)

                    let resolvedAttributeNameValues = attributeValues.resolve { resolvedAttributeNameValues in
                        queue.async {
                            let updatedValues = (token: activity.values.token.merging(resolvedAttributeNameValues) { _, new in new }, card: activity.values.card)
                            print("XXX: did update activity \(activity.primaryKey) in callback")
                            if activity.values.card != updatedValues.card || activity.values.token != updatedValues.token {
                                activityDataStore.update(activity: activity, withAttributeValues: updatedValues)
                            }
                        }
                    }

                    let updatedValues = (token: activity.values.token.merging(resolvedAttributeNameValues) { _, new in new }, card: activity.values.card)
                    print("XXX: did update activity \(activity.primaryKey)")
                    activityDataStore.update(activity: activity, withAttributeValues: updatedValues)
                }
            }.store(in: &cancelable)
    }
}
