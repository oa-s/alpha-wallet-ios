//
//  ActivityObject.swift
//  AlphaWallet
//
//  Created by Vladyslav Shepitko on 19.02.2022.
//

import Foundation
import RealmSwift
import SwiftProtobuf

class ActivityObject: Object {

    static func generatePrimaryKey(eventName: String, blockNumber: Int, transactionId: String, transactionIndex: Int, logIndex: Int) -> String {
        return "\(eventName)-\(blockNumber)-\(transactionId)-\(transactionIndex)-\(logIndex)"
    }

    @objc dynamic var primaryKey: String = ""
    //We use the internal id to track which activity to replace/update
    @objc dynamic var id: Int = 0
    @objc dynamic var rowTypeRawValue: Int = 0
    @objc dynamic var tokenObject: TokenObject?
    @objc dynamic var chainId: Int = 0
    @objc dynamic var name: String = ""
    @objc dynamic var eventName: String = ""
    @objc dynamic var blockNumber: Int = 0
    @objc dynamic var transactionId: String = ""
    @objc dynamic var transactionIndex: Int = 0
    @objc dynamic var logIndex: Int = 0
    @objc dynamic var dateRawValue: TimeInterval = 0
    @objc dynamic var valuesRawValue: ActivityValues?
    @objc dynamic var viewRawValue: ActivityView?
    @objc dynamic var itemViewRawValue: ActivityView?

    @objc dynamic var isBaseCard: Bool = false
    @objc dynamic var stateRawValue: Int = 0

    var values: (token: [AttributeId: AssetInternalValue], card: [AttributeId: AssetInternalValue]) {
        guard let values = valuesRawValue else { return ([:], [:]) }
        return (values.token, values.card)
    }

    var view: (html: String, style: String) {
        guard let view = viewRawValue else { return ("", "") }
        return (view.html, view.style)
    }

    var itemView: (html: String, style: String) {
        guard let view = itemViewRawValue else { return ("", "") }
        return (view.html, view.style)
    }

    convenience init(id: Int, rowType: ActivityRowType, tokenObject: TokenObject, server: RPCServer, name: String, eventName: String, blockNumber: Int, transactionId: String, transactionIndex: Int, logIndex: Int, date: Date, values: (token: [AttributeId: AssetInternalValue], card: [AttributeId: AssetInternalValue]), view: (html: String, style: String), itemView: (html: String, style: String), isBaseCard: Bool, state: Activity.State) {
        self.init()
        self.primaryKey = ActivityObject.generatePrimaryKey(eventName: eventName, blockNumber: blockNumber, transactionId: transactionId, transactionIndex: transactionIndex, logIndex: logIndex)
        self.id = id
        self.tokenObject = tokenObject
        self.chainId = server.chainID
        self.name = name
        self.eventName = eventName
        self.blockNumber = blockNumber
        self.transactionId = transactionId
        self.transactionIndex = transactionIndex
        self.logIndex = logIndex
        self.dateRawValue = date.timeIntervalSince1970
        self.viewRawValue = ActivityView(html: view.html, style: view.style)
        self.itemViewRawValue = ActivityView(html: itemView.html, style: itemView.style)
        self.valuesRawValue = ActivityValues(values: values)
        self.isBaseCard = isBaseCard
        self.stateRawValue = state.rawValue
        self.rowTypeRawValue = rowType.rawValue
    }

    override static func primaryKey() -> String? {
        return "primaryKey"
    }

    var viewHtml: (html: String, hash: Int) {
        guard let view = viewRawValue else { return ("", 0) }
        let hash = "\(view.style)\(view.html)".hashForCachingHeight
        return (html: wrapWithHtmlViewport(html: view.html, style: view.style, forTokenId: .init(id)), hash: hash)
    }

    var itemViewHtml: (html: String, hash: Int) {
        guard let itemView = viewRawValue else { return ("", 0) }
        let hash = "\(itemView.style)\(itemView.html)".hashForCachingHeight
        return (html: wrapWithHtmlViewport(html: itemView.html, style: itemView.style, forTokenId: .init(id)), hash: hash)
    }

    var nativeViewType: Activity.NativeViewType {
        switch tokenObject?.type {
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
        case .erc875, .none:
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

class ActivityView: Object {
    @objc dynamic var primaryKey: String = ""
    @objc dynamic var html: String = ""
    @objc dynamic var style: String = ""

    convenience init(html: String, style: String) {
        self.init()
        self.primaryKey = UUID().uuidString
        self.html = html
        self.style = style
    }

    override static func primaryKey() -> String? {
        return "primaryKey"
    }
}

class ActivityValues: Object {
    @objc dynamic var primaryKey: String = ""
    @objc dynamic var tokenData: Data?
    @objc dynamic var cardData: Data?

    var token: [AttributeId: AssetInternalValue] {
        get { return tokenData.flatMap { try? JSONDecoder().decode([AttributeId: AssetInternalValue].self, from: $0) } ?? [:] }
        set { tokenData = try? JSONEncoder().encode(newValue) }
    }

    var card: [AttributeId: AssetInternalValue] {
        get { return cardData.flatMap { try? JSONDecoder().decode([AttributeId: AssetInternalValue].self, from: $0) } ?? [:] }
        set { cardData = try? JSONEncoder().encode(newValue) }
    }

    convenience init(values: (token: [AttributeId: AssetInternalValue], card: [AttributeId: AssetInternalValue])) {
        self.init()

        self.primaryKey = UUID().uuidString
        tokenData = try? JSONEncoder().encode(values.token)
        cardData = try? JSONEncoder().encode(values.card)
    }

    override static func ignoredProperties() -> [String] {
        return ["token", "card"]
    }

    override static func primaryKey() -> String? {
        return "primaryKey"
    }
}
