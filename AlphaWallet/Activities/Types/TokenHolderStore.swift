//
//  TokenHolderStore.swift
//  AlphaWallet
//
//  Created by Vladyslav Shepitko on 19.02.2022.
//

import Foundation

class TokenHolderStore {
    private let eventsDataStore: NonActivityEventsDataStore
    private var tokensAndTokenHolders: [AlphaWallet.Address: [TokenHolder]] = .init()
    private let wallet: Wallet
    private let assetDefinitionStore: AssetDefinitionStore

    init(eventsDataStore: NonActivityEventsDataStore, assetDefinitionStore: AssetDefinitionStore, wallet: Wallet) {
        self.eventsDataStore = eventsDataStore
        self.assetDefinitionStore = assetDefinitionStore
        self.wallet = wallet
    }

    func createHolderIfNeeded(for token: Token) {
        tokenHolders(for: token)
    }

    @discardableResult func tokenHolders(for token: Token) -> [TokenHolder] {
        let tokenHolders: [TokenHolder]
        if let h = tokensAndTokenHolders[token.contractAddress] {
            tokenHolders = h
        } else {
            if token.contractAddress.sameContract(as: Constants.nativeCryptoAddressInDatabase) {
                let _token = TokenScript.Token(tokenIdOrEvent: .tokenId(tokenId: .init(1)), tokenType: .nativeCryptocurrency, index: 0, name: "", symbol: "", status: .available, values: .init())

                tokenHolders = [TokenHolder(tokens: [_token], contractAddress: token.contractAddress, hasAssetDefinition: true)]
            } else {
                tokenHolders = TokenAdaptor(token: token, assetDefinitionStore: assetDefinitionStore, eventsDataStore: eventsDataStore)
                    .getTokenHolders(forWallet: wallet)
            }

            tokensAndTokenHolders[token.contractAddress] = tokenHolders
        }
        return tokenHolders
    }
}
