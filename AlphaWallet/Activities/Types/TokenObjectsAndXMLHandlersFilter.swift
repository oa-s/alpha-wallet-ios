//
//  XMLHandlerEventMapper.swift
//  AlphaWallet
//
//  Created by Vladyslav Shepitko on 19.02.2022.
//

import Foundation

typealias TokenObjectAndXMLHandler = [(token: Token, xmlHandler: XMLHandler)]
typealias ContractsAndCards = [(token: Token, server: RPCServer, card: TokenScriptCard, interpolatedFilter: String)]

struct XMLHandlerEventMapper {
    private let config: Config
    private let wallet: Wallet
    private let enabledServers: [RPCServer]

    init(config: Config, wallet: Wallet) {
        self.config = config
        self.wallet = wallet
        self.enabledServers = config.enabledServers
    }

    func convert(contractServerXmlHandlers: TokenObjectAndXMLHandler) -> ContractsAndCards {
        let contractsAndCardsOptional: [ContractsAndCards] = contractServerXmlHandlers.compactMap { token, xmlHandler in
            var contractAndCard: ContractsAndCards = .init()
            for card in xmlHandler.activityCards {
                let (filterName, filterValue) = card.eventOrigin.eventFilter
                let interpolatedFilter: String
                switch EventSourceCoordinator.functional.convertToImplicitAttribute(string: filterValue) {
                case .ownerAddress:
                    interpolatedFilter = "\(filterName)=\(wallet.address.eip55String)"
                case .label, .contractAddress, .symbol, .tokenId, .none:
                    //TODO support more? //TODO support things like "$prefix-{tokenId}"
                    continue
                }

                guard let server = xmlHandler.server else { continue }
                switch server {
                case .any:
                    for each in enabledServers {
                        contractAndCard.append((token: token, server: each, card: card, interpolatedFilter: interpolatedFilter))
                    }
                case .server(let server):
                    contractAndCard.append((token: token, server: server, card: card, interpolatedFilter: interpolatedFilter))
                }
            }
            return contractAndCard
        }
        return contractsAndCardsOptional.flatMap { $0 }
    }
}
