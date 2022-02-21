// Copyright © 2020 Stormbird PTE. LTD.

import Foundation
import BigInt
import RealmSwift

struct Activity {
    enum NativeViewType {
        case nativeCryptoSent
        case nativeCryptoReceived
        case erc20Sent
        case erc20Received
        case erc20OwnerApproved
        case erc20ApprovalObtained
        case erc721Sent
        case erc721Received
        case erc721OwnerApproved
        case erc721ApprovalObtained
        case none
    }

    enum State: Int {
        case pending
        case completed
        case failed
    }
    let primaryKey: String
    //We use the internal id to track which activity to replace/update
    let id: Int
    var rowType: ActivityRowType
    let token: Token
    let server: RPCServer
    let name: String
    let eventName: String
    let blockNumber: Int
    let transactionId: String
    let transactionIndex: Int
    let logIndex: Int
    let date: Date
    let values: (token: [AttributeId: AssetInternalValue], card: [AttributeId: AssetInternalValue])
    let view: (html: String, style: String)
    let itemView: (html: String, style: String)
    let isBaseCard: Bool
    let state: State

    init() {
        self.init(id: 0, rowType: .item, token: .init(), server: .main, name: "", eventName: "", blockNumber: 0, transactionId: "", transactionIndex: 0, logIndex: 0, date: Date(), values: (token: [:], card: [:]), view: (html: "", style: ""), itemView: (html: "", style: ""), isBaseCard: false, state: .completed)
    }

    init(id: Int, rowType: ActivityRowType, token: Token, server: RPCServer, name: String, eventName: String, blockNumber: Int, transactionId: String, transactionIndex: Int, logIndex: Int, date: Date, values: (token: [AttributeId: AssetInternalValue], card: [AttributeId: AssetInternalValue]), view: (html: String, style: String), itemView: (html: String, style: String), isBaseCard: Bool, state: State) {
        self.id = id
        self.primaryKey = ActivityObject.generatePrimaryKey(eventName: eventName, blockNumber: blockNumber, transactionId: transactionId, transactionIndex: transactionIndex, logIndex: logIndex)
        self.token = token
        self.server = server
        self.name = name
        self.eventName = eventName
        self.blockNumber = blockNumber
        self.transactionId = transactionId
        self.transactionIndex = transactionIndex
        self.logIndex = logIndex
        self.date = date
        self.values = values
        self.view = view
        self.itemView = itemView
        self.isBaseCard = isBaseCard
        self.state = state
        self.rowType = rowType
    }

    init?(activityObject activity: ActivityObject) {
        guard let token = activity.tokenObject.flatMap({ Token(tokenObject: $0) }) else {
            print("XXX failure to create activity")
            return nil
        }
        //print("XXX create activity")
        self.primaryKey = activity.primaryKey
        self.id = activity.id
        self.token = token
        self.server = RPCServer(chainID: activity.chainId)
        self.name = activity.name
        self.eventName = activity.eventName
        self.blockNumber = activity.blockNumber
        self.transactionId = activity.transactionId
        self.transactionIndex = activity.transactionIndex
        self.logIndex = activity.logIndex
        self.date = Date(timeIntervalSince1970: activity.dateRawValue)
        self.values = activity.values
        self.view = activity.view
        self.itemView = activity.itemView
        self.isBaseCard = activity.isBaseCard
        self.state = State(rawValue: activity.stateRawValue)!
        self.rowType = ActivityRowType(rawValue: activity.rowTypeRawValue)!
    }

    var viewHtml: (html: String, hash: Int) {
        let hash = "\(view.style)\(view.html)".hashForCachingHeight
        return (html: wrapWithHtmlViewport(html: view.html, style: view.style, forTokenId: .init(id)), hash: hash)
    }

    var itemViewHtml: (html: String, hash: Int) {
        let hash = "\(itemView.style)\(itemView.html)".hashForCachingHeight
        return (html: wrapWithHtmlViewport(html: itemView.html, style: itemView.style, forTokenId: .init(id)), hash: hash)
    }

    var nativeViewType: NativeViewType {
        switch token.type {
        case .nativeCryptocurrency:
            switch name {
            case "sent":
                return .nativeCryptoSent
            case "received":
                return .nativeCryptoReceived
            default:
                return .none
            }
        case .erc20:
            if isBaseCard {
                switch name {
                case "sent":
                    return .erc20Sent
                case "received":
                    return .erc20Received
                case "ownerApproved":
                    return .erc20OwnerApproved
                case "approvalObtained":
                    return .erc20ApprovalObtained
                default:
                    return .none
                }
            } else {
                return .none
            }
        case .erc721, .erc721ForTickets, .erc1155:
            if isBaseCard {
                switch name {
                case "sent":
                    return .erc721Sent
                case "received":
                    return .erc721Received
                case "ownerApproved":
                    return .erc721OwnerApproved
                case "approvalObtained":
                    return .erc721ApprovalObtained
                default:
                    return .none
                }
            } else {
                return .none
            }
        case .erc875:
            return .none
        }
    }

    var isSend: Bool {
        name == "sent"
    }

    var isReceive: Bool {
        name == "received"
    }
}
