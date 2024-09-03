//
//  Extensions.swift
//  CloudKitExample
//
//  Created by Ricardo Venieris on 26/07/20.
//  Copyright © 2020 Ricardo Venieris. All rights reserved.
//

import CloudKit
import CodableExtensions

public typealias CKMCursor = CKQueryOperation.Cursor
public typealias CKMRecordName = String
public typealias CKRecordAsyncResult = (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)],
                                        queryCursor: CKQueryOperation.Cursor?)
public typealias CKMRecordAsyncResult = (Result<(records: [Any],
                                                 queryCursor: CKMCursor?,
                                                 partialErrors: [CKMRecordName:Error]), Error>)

extension CKRecord {
    
    @available(iOS 13.0.0, *)
    func asDictionary() async -> [String: Any] {
        var result:[String:Any] = [:]
        result["recordName"] = self.recordID.recordName
        result["createdBy"] = self.creatorUserRecordID?.recordName
        result["createdAt"] = self.creationDate
        result["modifiedBy"] = self.lastModifiedUserRecordID?.recordName
        result["modifiedAt"] = self.modificationDate
        result["changeTag"] = self.recordChangeTag

        
        for key in self.allKeys() {
            
            // Se valor é Date
            if let value = self.value(forKey: key) as? Date {
                result[key] = value.timeIntervalSinceReferenceDate
            }
            else if let value = self.value(forKey: key) as? [Date] {
                result[key] = value.map{$0.timeIntervalSinceReferenceDate}
            }

            // Se o cara for uma referência para outro objeto, pegar o outro objeto e transformar para dicionario
            else if let value = self.value(forKey: key) as? CKRecord.Reference {
                result[key] = await value.asyncLoad()
            }
            else if let value = self.value(forKey: key) as? [CKRecord.Reference] {
                var records: [[String: Any]] = []
                for v in value {
                    let dict = await v.asyncLoad()
                    if let dict {
                        records.append(dict)
                    }
                }
                result[key] = records
            }
                
            // Se o cara for um Asset converter para Data
            else if let value = self.value(forKey: key) as? CKAsset {
                result[key] = value.fileURL?.contentAsData
            }
            else if let value = self.value(forKey: key) as? [CKAsset] {
                result[key] = value.map{ $0.fileURL?.contentAsData }
            } else {
                result[key] = self.value(forKey: key)
            }
        }
        return result
    }
    
	public var asDictionary:[String:Any] {
		var result:[String:Any] = [:]
		result["recordName"] = self.recordID.recordName
		result["createdBy"] = self.creatorUserRecordID?.recordName
		result["createdAt"] = self.creationDate
		result["modifiedBy"] = self.lastModifiedUserRecordID?.recordName
		result["modifiedAt"] = self.modificationDate
		result["changeTag"] = self.recordChangeTag

		
		for key in self.allKeys() {
			
			// Se valor é Date
			if let value = self.value(forKey: key) as? Date {
				result[key] = value.timeIntervalSinceReferenceDate
			}
			else if let value = self.value(forKey: key) as? [Date] {
				result[key] = value.map{$0.timeIntervalSinceReferenceDate}
			}

			// Se o cara for uma referência para outro objeto, pegar o outro objeto e transformar para dicionario
			else if let value = self.value(forKey: key) as? CKRecord.Reference {
				result[key] = value.syncLoad()
			}
			else if let value = self.value(forKey: key) as? [CKRecord.Reference] {
				result[key] = value.map{ $0.syncLoad() }
			}
				
			// Se o cara for um Asset converter para Data
			else if let value = self.value(forKey: key) as? CKAsset {
				result[key] = value.fileURL?.contentAsData
			}
			else if let value = self.value(forKey: key) as? [CKAsset] {
				result[key] = value.map{ $0.fileURL?.contentAsData }
			} else {
                result[key] = self.value(forKey: key)
			}
		}
		return result
	}
	var asReference:CKRecord.Reference {
		return CKRecord.Reference(recordID: self.recordID, action: .none)
	}
	
	func haveCycle(references:Set<String> = [])->Bool {
		var references = references
		references.insert(self.recordID.recordName)
		let childReferences = Set(self.allKeys().compactMap{(value(forKey: $0) as? CKRecord.Reference)?.recordID.recordName})

		// Se existe interseção, tem ciclo
		guard childReferences.intersection(references).count == 0 else {return true}
		
		let childRecords = childReferences.compactMap{CKMDefault.getFromCache($0)}
		let referencesUnion = childReferences.union(references)

		for item in childRecords {
			if item.haveCycle(references: referencesUnion) {
				return true
			}
		}
		return false
	}
}

extension CKRecord.Reference {
	func syncLoad()->[String:Any]? {
		let recordName: String = self.recordID.recordName
		// Executar o fetch
		
		
		
		if let record = CKMDefault.getFromCache(recordName) {
			if record.haveCycle() {
				// TODO: tratar criação de objeto com ciclo
				fatalError("Cannot have cycle in object... yet.")
			}
			return record.asDictionary
		}
	
		var result:[String:Any]? = nil
		CKMDefault.database.fetch(withRecordID: CKRecord.ID(recordName: recordName), completionHandler: { (record, error) -> Void in
			
			// Got error
			if let error = error {
				debugPrint("Cannot read associated record \(recordName), \(error)")

			} // Got Record
			 else if let record = record {
				CKMDefault.addToCache(record)
				result = record.asDictionary
			}
			CKMDefault.semaphore.signal()
		})
		CKMDefault.semaphore.wait()
		return result
	}
    
    @available(iOS 13.0.0, *)
    func asyncLoad() async -> [String: Any]?  {
        let recordName: String = self.recordID.recordName
        // Executar o fetch
        
        
        if let record = CKMDefault.getFromCache(recordName) {
            if record.haveCycle() {
                // TODO: tratar criação de objeto com ciclo
                fatalError("Cannot have cycle in object... yet.")
            }
            return await record.asDictionary()
        }
    
        let record = try? await CKMDefault.database.record(for: CKRecord.ID(recordName: recordName))
        if let record {
            return await record.asDictionary()
        }
        return nil
        
    }
}

public extension CKAsset {
	convenience init(data:Data) {
		let url = URL(fileURLWithPath: NSTemporaryDirectory().appending(UUID().uuidString+".data"))
		do {
			try data.write(to: url)
		} catch let e as NSError {
			debugPrint("Error! \(e)")
		}
		self.init(fileURL: url)
	}
	
	var data:Data? {
		return self.fileURL?.contentAsData
	}
}

public extension Optional where Wrapped == String {
	var isEmpty:Bool {
		return self?.isEmpty ?? true
	}
}

public extension String {
    func deleting(suffix: String) -> String {
        guard self.hasSuffix(suffix) else { return self }
        return String(self.dropLast(suffix.count))
    }
    
    var removingFirstUnderscore: String {
        guard self.hasPrefix("_") else { return self }
        return String(self.dropFirst())
    }
    
}


/**
- Description
	A String that have "⇩" as last character if it's SortDescriptor is descending
	set the descriptos as descending using (ckSort.descending)
*/
public typealias CKSortDescriptor = NSString
extension NSString {
	
	/// For use of SortDescriptor
	class CK {
		private var text:String
		var  isAscending:Bool { text.last != "⇩" }
		var isDescending:Bool { text.last == "⇩" }
		var    ascending:String { return  isAscending ? text : String(text.dropLast()) }
		var   v:String { return isDescending ? text : text+"⇩" }
		var   descriptor:NSSortDescriptor { NSSortDescriptor(key: ascending, ascending:isAscending) }
		init(_ text:NSString) { self.text = String(text) }
	}
	
	
	/**
	- Description:
	Elements for use of SortDescriptors
	*/
	var ckSort:CK {CK(self)}
	
	
}

public extension Array where Element == CKSortDescriptor {
	var ckSortDescriptors:[NSSortDescriptor] { self.map { $0.ckSort.descriptor }
	}
	
}

public extension Date {
	/// Initializes with specific date & format default format: ( yyyy/MM/dd HH:mm )
	init(date:String, format:String? = nil) {
		self.init()
		self.set(date: date, format: format)
	}
	
	mutating func set(date:String, format:String? = nil) {
		
		let format = format ?? (date.count == 16 ? "yyyy/MM/dd HH:mm" : "yyyy/MM/dd")
		let formatter = DateFormatter()
		formatter.dateFormat = format
		guard let newDate = formatter.date(from: date) else {
			debugPrint("date \(date) in format \(format) does not results in a valid date")
			return
		}
		self = newDate
	}
}


// Global Functions


/// Check if object Type is Element or Array of Number, String & Date
func isBasicType(_ value:Any)->Bool {
    let typeDescription = String(reflecting: type(of: value))
    guard typeDescription.contains("Swift") || typeDescription.contains("Foundation") else { return false }
    return typeDescription.contains("Int") || typeDescription.contains("Float") || typeDescription.contains("Double") || typeDescription.contains("String") || typeDescription.contains("Date") || typeDescription.contains("Bool")
}


public extension NSPointerArray {
	func addObject(_ object: AnyObject?) {
		guard let strongObject = object else { return }
		
		let pointer = Unmanaged.passUnretained(strongObject).toOpaque()
		addPointer(pointer)
	}
	
	func insertObject(_ object: AnyObject?, at index: Int) {
		guard index < count, let strongObject = object else { return }
		
		let pointer = Unmanaged.passUnretained(strongObject).toOpaque()
		insertPointer(pointer, at: index)
	}
	
	func replaceObject(at index: Int, withObject object: AnyObject?) {
		guard index < count, let strongObject = object else { return }
		
		let pointer = Unmanaged.passUnretained(strongObject).toOpaque()
		replacePointer(at: index, withPointer: pointer)
	}
	
	func object(at index: Int) -> AnyObject? {
		guard index < count, let pointer = self.pointer(at: index) else { return nil }
		return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
	}
	
	func removeObject(at index: Int) {
		guard index < count else { return }
		
		removePointer(at: index)
	}
}


public extension Optional {
	func wrappedType() -> Any.Type {
		return Wrapped.self
	}
}

@available(iOS 13.0.0, *)
extension CKMPreparedRecord {
    
    public func dispatchPending(for savedRecord: CKRecord) async throws -> CKRecord {
        // Me atualizar
        self.record = savedRecord
        self.objectSaving.recordName = record.recordID.recordName
        CKMDefault.addToCache(record)
        
        // Verificar se tá tudo bem com o recordName (unwrap)
        guard let _ = objectSaving.recordName else {
            throw PrepareRecordError.CannotDispatchPendingWithoutSavedRecord("Object \(objectSaving) must have a recordName")
        }
        
        // checar se há pendências
        guard !pending.isEmpty else { return record }
        
        // Se existem pendências,
        for item in pending {
            // Salva cada uma delas
            let savedBranchRecord = try await item.cyclicReferenceBranch.ckSave()
            
            guard let referenceID = savedBranchRecord.recordName else {
                throw PrepareRecordError.ErrorSavingReferenceObject("\(item.pendingCyclicReferenceName) in \(self.record.recordType) - Record saved without reference")
            }
            // Ao salvar faz o update do record referenciado
            if let ckRecord = try await self.updateRecord(with: referenceID, in: item) {
                return ckRecord
            }
            
        }
        return self.record
    }
    
    public func updateRecord(with reference: String, in item: CKMPreparedRecord.Reference) async throws -> CKRecord? {
        let reference = CKRecord.Reference(recordID: CKRecord.ID(recordName: reference), action: .none)
        let referenceField = item.pendingCyclicReferenceName
        // if item is Reference_Array
        if var referenceArray = self.record.value(forKey: referenceField) as? [CKRecord.Reference] {
            referenceArray.append(reference)
            self.record.setValue(referenceArray, forKey: referenceField)
        } else {
            // if item is single Reference
            self.record.setValue(reference, forKey: referenceField)
        }
        
        // Se acabaram as pendências
        if self.allPendingValuesFilled {
            // Atualiza o CKRecord no BD, e completa com o resultado
            let record = try await CKMDefault.database.save(self.record)
            CKMDefault.addToCache(record)
            return record
        }
        return nil
        
    }
    
    enum PrepareRecordError: Swift.Error {
        case CannotDispatchPendingWithoutSavedRecord(String)
        case ErrorSavingReferenceObject(String)
    }
}
