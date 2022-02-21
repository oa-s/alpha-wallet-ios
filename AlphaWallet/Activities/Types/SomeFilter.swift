//
//  SomeFilter.swift
//  AlphaWallet
//
//  Created by Vladyslav Shepitko on 19.02.2022.
//

import Foundation
import RealmSwift

struct SomeFilter {

    static func initialOrNewOrDelatedTokens(change: ChangeSet<[Token]>) -> Bool {
        switch change {
        case .initial:
            return true
        case .update(let tokens, let deletions, let insertions, _):
            let deletedTokens = deletions.map { tokens[$0] }
            let aNewTokens = insertions.map { tokens[$0] }

            return !deletedTokens.isEmpty || !aNewTokens.isEmpty
        case .error:
            return true
        }
    }

    static func newActivities(change: ChangeSet<[Activity]>) -> Bool {
        switch change {
        case .initial, .error:
            return false
        case .update(let activities, _, let insertions, _):
            let aNewActivities = insertions.map { activities[$0] }
            return !aNewActivities.isEmpty
        }
    }

    static func mapToArray(fromActivitiesChange change: ChangeSet<[ActivityObject]>) -> [ActivityObject] {
        switch change {
        case .initial:
            return []
        case .update(let activities, _, let insertions, _):
            return Array(insertions.map { activities[$0] })
        case .error:
            return []
        }
    } 
}
