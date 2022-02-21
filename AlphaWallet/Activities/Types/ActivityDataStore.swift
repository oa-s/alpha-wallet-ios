//
//  ActivityDataStore.swift
//  AlphaWallet
//
//  Created by Vladyslav Shepitko on 19.02.2022.
//

import Foundation
import RealmSwift
import Combine

protocol ActivityDataStoreProtocol: NSObjectProtocol {
    func activityNotExists(activity: ActivityObject) -> Bool
    func add(activities: [ActivityObject])
    func removeAll()
    func update(activity: Activity, withAttributeValues attributeValues: (token: [AttributeId: AssetInternalValue], card: [AttributeId: AssetInternalValue]))
    func activitiesChangeset(strategy: ActivitiesFilterStrategy) -> AnyPublisher<ChangeSet<[Activity]>, Never>
}

extension ActivityDataStoreProtocol {
    func newActivitiesChangeset(strategy: ActivitiesFilterStrategy) -> AnyPublisher<ChangeSet<[Activity]>, Never> {
        activitiesChangeset(strategy: .noFilter)
            .filter { changeset in
                switch changeset {
                case .initial, .error:
                    return false
                case .update(let activities, _, let insertions, _):
                    let aNewActivities = insertions.map { activities[$0] }
                    return !aNewActivities.isEmpty
                }
            }.eraseToAnyPublisher()
    }
}

class ActivityDataStore: NSObject, ActivityDataStoreProtocol {
    private let realm: Realm
    private let queue = DispatchQueue.init(label: "q1")
    private let store: RealmStore

    init(realm: Realm) {
        self.realm = realm
        self.store = .init(realm: realm)
        super.init()

        removeAll()
    }

    func activityNotExists(activity: ActivityObject) -> Bool {
        var notExists: Bool = false
        store.performSync { realm in
            notExists = realm.object(ofType: ActivityObject.self, forPrimaryKey: activity.primaryKey) == nil
        }

        return notExists
    }

    func activitiesChangeset(strategy: ActivitiesFilterStrategy) -> AnyPublisher<ChangeSet<[Activity]>, Never> {
        var publisher: AnyPublisher<ChangeSet<[Activity]>, Never>!
        store.performSync { realm in

            let results: Results<ActivityObject>
            switch strategy {
            case .noFilter:
                results = realm.objects(ActivityObject.self)
            case .contract(let contract), .operationTypes(_, let contract):
                results = realm.objects(ActivityObject.self)
                    .filter("tokenObject != nil AND tokenObject.contract = '\(contract.eip55String)'")
            case .nativeCryptocurrency(let primaryKey):
                results = realm.objects(ActivityObject.self)
                    .filter("tokenObject != nil AND tokenObject.primaryKey = '\(primaryKey)'")
            }

            publisher = results
                .sorted(byKeyPath: "blockNumber", ascending: false)
                .changesetPublisher
                .subscribe(on: self.queue)
                .map { change in
                    switch change {
                    case .initial(let transactions):
                        return .initial(Array(transactions.compactMap { Activity(activityObject: $0) }))
                    case .update(let transactions, let deletions, let insertions, let modifications):
                        return .update(Array(transactions.compactMap { Activity(activityObject: $0) }), deletions: deletions, insertions: insertions, modifications: modifications)
                    case .error(let error):
                        return .error(error)
                    }
                }
                .eraseToAnyPublisher()
        }
        return publisher
    }

    func removeAll() {
        store.performSync { realm in
            realm.beginWrite()
            realm.delete(realm.objects(ActivityObject.self))
            try! realm.commitWrite()
        }
    }

    func add(activities: [ActivityObject]) {
        guard !activities.isEmpty else { return }

        store.performSync { realm in
            realm.beginWrite()

            for each in activities {
                realm.create(ActivityObject.self, value: each, update: .all)
            }

            try! realm.commitWrite()
        }
    }

    func update(activity: Activity, withAttributeValues attributeValues: (token: [AttributeId: AssetInternalValue], card: [AttributeId: AssetInternalValue])) {
        store.performSync { realm in
            guard let existedActivity = realm.object(ofType: ActivityObject.self, forPrimaryKey: activity.primaryKey) else { return }

            realm.beginWrite()

            if let valuesRawValue = existedActivity.valuesRawValue {
                realm.delete(valuesRawValue)
                existedActivity.valuesRawValue = ActivityValues(values: attributeValues)
            } else {
                existedActivity.valuesRawValue = ActivityValues(values: attributeValues)
            }
            try! realm.commitWrite()
        }
    }
}
