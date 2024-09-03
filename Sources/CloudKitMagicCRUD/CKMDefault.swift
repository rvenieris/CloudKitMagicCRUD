//
//  CKDefaults.swift
//  ClodKitMagic
//
//  Created by Ricardo Venieris on 28/07/20.
//  Copyright © 2020 Ricardo Venieris. All rights reserved.
//

import CloudKit


open class CKMDefault {
    /**
     The default database
     By dafault get the CKContainer.default().publicCloudDatabase value.
     Can be resseted to another value
     */
    public static var containerIdentifier:String {
        get {
            return container.containerIdentifier ?? "*** no containner ***"
        }
        set {
            Self.container = CKContainer(identifier: newValue)
            Self.database = container.publicCloudDatabase
        }
    }
    
    /**
     The default container
     Same as CKContainer.default()
     */
    public static var container = CKContainer.default()
    
    public static var database:CKDatabase  = {
        return container.publicCloudDatabase
    }()
    
    public struct CacheItem {
        let record: CKRecord
        let addedAt:Date
    }
    
    /// The default semaphore for awaiting subqueries
    public static let semaphore = DispatchSemaphore(value: 0)
    
    /// Cache inplementationn
    private static var cache:[String:CacheItem] = [:]
    
    /// Time in seconds for cache expiration
    public  static var cacheExpirationTime:TimeInterval = {
        #if DEBUG
        return .infinity
        #else
        return 30
        #endif
        
    }()
    
    // A queue to deal with Self.cache race issues
    private static let cacheQueue = DispatchQueue(label: "name.cache.queue")
    public static func addToCache(_ record:CKRecord) {
        cacheQueue.sync {
            typeIsCacheable[record.recordType] = typeIsCacheable[record.recordType] ?? true
            guard typeIsCacheable[record.recordType]! else {return}
            let cacheItem = CacheItem(record: record, addedAt: Date())
            Self.cache[record.recordID.recordName] = cacheItem
        }
    }
    
    public static func removeFromCache(_ recordName:String) {
        cacheQueue.sync {
            Self.cache[recordName] = nil
        }
    }
    
    public static func removeFromCacheCascade(_ recordName:String) {
        cacheQueue.sync {
            var recordNames = childReferencesInCacheFor(recordName)
                .compactMap{$0.recordID.recordName}
            recordNames.append(recordName)
            recordNames.forEach{Self.cache[$0] = nil}
        }
        
    }
    
    public static func childReferencesInCacheFor(_ recordName:String)->[CKRecord.Reference] {
        guard let record = Self.cache[recordName] else {return [] }
        var result:[CKRecord.Reference] = []
        
        for item in record.record.allKeys() {
            guard let value = record.record.value(forKey: item)  else { continue }
            
            if let reference = (value as? CKRecord.Reference) {
                let ancestors = childReferencesInCacheFor(reference.recordID.recordName)
                result.append(contentsOf: ancestors)
                result.append(reference)
            }
            else if let references = (value as? [CKRecord.Reference]) {
                let recordNames = references.compactMap{ $0.recordID.recordName }
                let ancestors = recordNames.flatMap{ childReferencesInCacheFor($0) }
                result.append(contentsOf: ancestors)
                result.append(contentsOf: references)
            }
        }
        return result
    }
    
    
    
    public static func addToCache(_ records:[CKRecord]) {
        records.forEach {
            Self.addToCache($0) }
    }
    
    /// Manage if Type is Cacheable
    private static var typeIsCacheable:[String:Bool] = [:]
    
    public static func get<T>(isCacheable type:T.Type)->Bool {
        return typeIsCacheable[getRecordTypeFor(type:type)] ?? true
    }
    
    public static func set<T>(type:T.Type, isCacheable:Bool) {
        typeIsCacheable[getRecordTypeFor(type:type)] = isCacheable
    }
    
    public static func getFromCache(_ recordName: String)->CKRecord? {
        if let item = Self.cache[recordName],
           item.addedAt.timeIntervalSinceNow < cacheExpirationTime {
            return item.record
        } else {
            Self.removeFromCache(recordName)
            return nil
        }
    }
    
    public static func getFromCache<T:CKMRecord>(all: T.Type)->[T]? {
        return Self.cache.filter {$0.value.record.recordType == T.ckRecordType}
            .compactMap{try? T.load(from: $0.value.record.asDictionary)}
        
    }
    
    /// Naming Types to RecordType implementation
    private static var typeRecordName:[String:String] = [:]
    
    public static func getRecordTypeFor<T:CKMRecord>(_ object:T)->String {
        return Self.getRecordTypeFor(type: T.Type.self)
    }
    
    public static func getRecordTypeFor<T>(type:T.Type)->String {
        let name = String(describing: type)
        return typeRecordName[name] ?? name
    }
    
    public static func setRecordTypeFor<T:CKMRecord>(_ object:T, recordName:String) {
        Self.setRecordTypeFor(type: T.Type.self, recordName: recordName)
    }
    
    public static func setRecordTypeFor<T>(type:T.Type, recordName:String) {
        let name = String(describing: type)
        typeRecordName[name] = recordName
    }
    
    /// Check Types with Cycles
    private static var typeHaveCycle:[String:Bool] = [:]
    public static func haveCycle<T>(_ type:T.Type)->Bool {
        let type:String = String(describing: type)
        if let haveCycle = typeHaveCycle[type] { return haveCycle}
        // else
        
        return true
    }
    
}
