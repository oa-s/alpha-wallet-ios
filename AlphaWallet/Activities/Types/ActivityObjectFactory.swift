//
//  ActivityObjectFactory.swift
//  AlphaWallet
//
//  Created by Vladyslav Shepitko on 19.02.2022.
//

import Foundation

class ActivityObjectFactory {
    private let sessions: ServerDictionary<WalletSession>
    private let tokensDataStore: TokensDataStore

    init(sessions: ServerDictionary<WalletSession>, tokensDataStore: TokensDataStore) {
        self.sessions = sessions
        self.tokensDataStore = tokensDataStore
    }

    func createActivity(from eachEvent: EventActivityInstance, server: RPCServer, token: Token, card: TokenScriptCard, interpolatedFilter: String) -> ActivityObject? {
        let implicitAttributes = generateImplicitAttributesForToken(forContract: token.contractAddress, server: server, symbol: token.symbol)
        let tokenAttributes = implicitAttributes
        var cardAttributes = ActivitiesService.functional.generateImplicitAttributesForCard(forContract: token.contractAddress, server: server, event: eachEvent)
        cardAttributes.merge(eachEvent.data) { _, new in new }

        for parameter in card.eventOrigin.parameters {
            guard let originalValue = cardAttributes[parameter.name] else { continue }
            guard let type = SolidityType(rawValue: parameter.type) else { continue }
            let translatedValue = type.coerce(value: originalValue)
            cardAttributes[parameter.name] = translatedValue
        }

        //TODO fix for activities: special fix to filter out the event we don't want - need to doc this and have to handle with TokenScript design
        let isNativeCryptoAddress = token.contractAddress.sameContract(as: Constants.nativeCryptoAddressInDatabase)
        if card.name == "aETHMinted" && isNativeCryptoAddress && cardAttributes["amount"]?.uintValue == 0 {
            return nil
        } else {
            guard let tokenObject = tokensDataStore.tokenObject(forContract: token.contractAddress, server: token.server) else { return nil }
            return ActivityObject(id: Int.random(in: 0..<Int.max), rowType: .standalone, tokenObject: tokenObject, server: eachEvent.server, name: card.name, eventName: eachEvent.eventName, blockNumber: eachEvent.blockNumber, transactionId: eachEvent.transactionId, transactionIndex: eachEvent.transactionIndex, logIndex: eachEvent.logIndex, date: eachEvent.date, values: (token: tokenAttributes, card: cardAttributes), view: card.view, itemView: card.itemView, isBaseCard: card.isBase, state: .completed)
        }
    }

    private func generateImplicitAttributesForToken(forContract contract: AlphaWallet.Address, server: RPCServer, symbol: String) -> [String: AssetInternalValue] {
        var results = [String: AssetInternalValue]()
        for each in AssetImplicitAttributes.allCases {
            //TODO ERC721s aren't fungible, but doesn't matter here
            guard each.shouldInclude(forAddress: contract, isFungible: true) else { continue }
            switch each {
            case .ownerAddress:
                results[each.javaScriptName] = .address(sessions[server].account.address)
            case .tokenId:
                //We aren't going to add `tokenId` as an implicit attribute even for ERC721s, because we don't know it
                break
            case .label:
                break
            case .symbol:
                results[each.javaScriptName] = .string(symbol)
            case .contractAddress:
                results[each.javaScriptName] = .address(contract)
            }
        }
        return results
    }
}
