//
//  Extensions.swift
//  CloudKitExample
//
//  Created by Ricardo Venieris on 26/07/20.
//  Copyright © 2020 Ricardo Venieris. All rights reserved.
//

import CloudKit
import CodableExtensions

extension CKRecord {
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
    guard typeDescription.hasPrefix("Swift") || typeDescription.hasPrefix("Foundation") { return false }
    return typeDescription.hasSuffix("Int") || typeDescription.hasSuffix("Float") || typeDescription.hasSuffix("Double") || typeDescription.hasSuffix("String") || typeDescription.hasSuffix("Date") || typeDescription.hasSuffix("Bool")
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
