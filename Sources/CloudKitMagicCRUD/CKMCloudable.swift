//
//  CKCloudable.swift
//  CloudKitMagic
//
//  Created by Ricardo Venieris on 22/08/20.
//  Copyright © 2020 Ricardo Venieris. All rights reserved.
//

import CloudKit

public protocol CKMCloudable:Codable {
	var recordName:String? { get set }
}

/// Basic Record Managment
extension CKMCloudable {
	
	public static var isClassType:Bool {return (Self.self is AnyClass)}
	public var isClassType:Bool {return Self.isClassType}
	
	/**
	Get or set the recordType name
	the default value is the type (class or struct) name
	*/
	public static var ckRecordType: String {
		get { CKMDefault.getRecordTypeFor(type: Self.self) }
		set { CKMDefault.setRecordTypeFor(type: Self.self, recordName: newValue) }
	}
	
	public static var ckIsCachable:Bool {
		get { CKMDefault.get(isCacheable: Self.self) }
		set { CKMDefault.set(type: Self.self, isCacheable: newValue) }
	}
	
	public var reference:CKRecord.Reference? {
		guard let recordName = self.recordName else {return nil}
		return CKRecord.Reference(recordID: CKRecord.ID(recordName: recordName), action: .none)
		
	}
	
	public var referenceInCacheOrNull:CKRecord.Reference? {
		if let reference = self.reference {
			if let _ = CKMDefault.getFromCache(reference.recordID.recordName) {
				return reference
			}
		} // else
		return nil
	}
	
	/// Return true if this type have cyclic reference
	public func haveCycle(with object:CKMCloudable? = nil, previousPath:[AnyObject] = [])->Bool {
		let object = object ?? self
		// Se não é classe nem perde tempo
		if !self.isClassType {return false}
		
		let mirror = Mirror(reflecting: self)
		for field in mirror.children {
			let value_object = field.value as AnyObject
			if let cloudRecord = value_object as? CKMCloudable {
				let value = cloudRecord as AnyObject
				if value === (object as AnyObject) { return true }
				if (previousPath.contains{value === $0}) { return false }
				var previousPath = previousPath
				previousPath.append(value)
				return cloudRecord.haveCycle(with: object, previousPath: previousPath)
			}
		}
		return false
	}
	
	public var referenceSavingRecordIfNull:CKRecord.Reference? {
		if let reference = self.referenceInCacheOrNull {
			return reference
		}
		// else
		var savedReference:CKRecord.Reference? = nil
		
		// Inicio assincrono
		self.ckSave(then: { result in
			switch result {
				case .success(let savedRecord):
					savedReference = (savedRecord as? CKMCloudable)?.reference
				case .failure(let error):
					debugPrint("error saving record \(self.recordName ?? "without recordName") \n\(error)")
			}
			CKMDefault.semaphore.signal()
		})
		// fim assincrono
		CKMDefault.semaphore.wait()
		
		return savedReference
		
	}
	
	public func prepareCKRecord()throws ->CKMPreparedRecord {
		let ckRecord:CKRecord = {
			var ckRecord:CKRecord?
			if let recordName = self.recordName {
				CKMDefault.database.fetch(withRecordID: CKRecord.ID(recordName: recordName), completionHandler: { (record, error) -> Void in
					
					ckRecord = record
					CKMDefault.semaphore.signal()
				})
				
				CKMDefault.semaphore.wait()
				if let record = ckRecord {return record}
				// else
				return CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: recordName))
			} // else
			return CKRecord(recordType: Self.ckRecordType)
		}()
		let preparedRecord = CKMPreparedRecord(for: self, in:ckRecord)
		let mirror = Mirror(reflecting: self)
		
		for field in mirror.children{
			// Trata valores à partir dde um mirroing
			
			var value = field.value
			guard !"\(value)".elementsEqual("nil") else {continue} // se valor nil nem perde tempo
			guard let key = field.label else { fatalError("Type \(mirror) have field without label.") }
			
			//MARK: Tratamento de todos os tipos possíveis
			
			if field.label?.elementsEqual("recordName") ?? false
				|| field.label?.elementsEqual("createdBy") ?? false
				|| field.label?.elementsEqual("createdAt") ?? false
				|| field.label?.elementsEqual("modifiedBy") ?? false
				|| field.label?.elementsEqual("modifiedAt") ?? false
				|| field.label?.elementsEqual("changeTag") ?? false {
				// do nothing
			}
			
			// Se o campo é um básico (Numero, String, Date ou Array desses elementos)
			else if  isBasicType(field.value) {
				ckRecord.setValue(value, forKey: key)
			}
			
			// Se o campo é Data ou [Data], converte pra Asset ou [Asset]
			else if let data = value as? Data {
				value = CKAsset(data: data)
				ckRecord.setValue(value, forKey: key)
			}
			
			else if let datas = value as? [Data] {
				value = datas.map {CKAsset(data: $0)}
				ckRecord.setValue(value, forKey: key)
			}
			
			// se campo é CKCloudable, pega a referência
			else if let value = (field.value as AnyObject) as? CKMCloudable {
				// Se a referência não está com recordName nulo, tá tudo bem.
				if let reference = value.referenceInCacheOrNull {
					ckRecord.setValue(reference, forKey: key)
				}
				// se não, se meu  recordName tá preenchido, salva a dependencia e segue
				else if let _ = self.recordName {
					if let reference = value.referenceSavingRecordIfNull {
						ckRecord.setValue(reference, forKey: key)
					} else {
						debugPrint("----------------------------------")
						debugPrint("Cannot save record for \(key) in \(Self.ckRecordType)")
						dump(value)
						debugPrint("----------------------------------")
					}
				}
				/// Se meu recordName não tá preenchido e tem referência cíclica, guarda o objeto para salvar depois
				else if value.haveCycle(with: self) {
					preparedRecord.add(value: value, forKey: key)
				}
			}
			
			// se campo é [CKCloudable] Pega a referência
			else if let value = field.value as? [CKMCloudable] {
				var references:[CKRecord.Reference] = []
				for item in value {
					if let reference = item.referenceSavingRecordIfNull {
						references.append(reference)
					} else {
						debugPrint("Invalid Field in \(mirror).\(key) \n Data:")
						dump(item)
						throw CRUDError.invalidRecordID
					}
				}
				ckRecord.setValue(references, forKey: key)
				
			}
			
			else {
				debugPrint("WARNING: Untratable type\n    \(key): \(type(of: field.value)) = \(field.value)")
				continue
			}
		}
		
		return preparedRecord
	}
	
	/**
	Saves the object in iCloud, returning in a completion a Result Type
		Cases:
			.success(let record:CKMRecord) -> The saved record, with correct Object Type, in a Any shell.  Just cast this to it's original type.
			.failure(let error) an error
	*/
	public func ckSave(then completion:@escaping (Result<Any, Error>)->Void) {
		var ckPreparedRecord:CKMPreparedRecord
		do {
			ckPreparedRecord = try self.prepareCKRecord()
		} catch let error {
			completion(.failure(error))
			return
		}
		
		CKMDefault.database.save(ckPreparedRecord.record, completionHandler: {
			(record,error) -> Void in
			
			// Got error
			if let error = error {
				completion(.failure(error))
				return
			}
			
			// else
			if let record = record {
				// Executar as pendências, se houver
				ckPreparedRecord.dispatchPending(for: record, then: { result in
					switch result {
						case .success(let record):
							do {
								let object = try Self.load(from: record.asDictionary)
								completion(.success(object))
							} catch {
								completion(.failure(CRUDError.cannotMapRecordToObject))
							}
						case .failure(let error):
							completion(.failure(error))
					}
				})
			}
		})
	}
	
	/**
	Read all records from a type
	- Parameters:
	- sortedBy a array of  SortDescriptors
	- returns: a (Result<Any, Error>) where Any contais a type objects array [T] in a completion handler
	*/
	public static func ckLoadAll(sortedBy sortKeys:[CKSortDescriptor] = [], predicate:NSPredicate = NSPredicate(value:true), then completion:@escaping (Result<Any, Error>)->Void) {
		//Preparara a query
		let query = CKQuery(recordType: Self.ckRecordType, predicate: predicate)
		query.sortDescriptors = sortKeys.ckSortDescriptors
		
		
		// Executar a query
		CKMDefault.database.perform(query, inZoneWith: nil, completionHandler: { (records, error) -> Void in
			
			// Got error
			if let error = error {
				completion(.failure(error))
				return
			}
			
			// else
			if let records = records {
				let result:[Self] = records.compactMap{
					let dictionary = $0.asDictionary
					
					return try? Self.load(from: dictionary)}
				
				guard records.count == result.count else {
					completion(.failure(CRUDError.cannnotMapAllRecords))
					return
				}
				CKMDefault.addToCache(records)
				completion(.success(result))
			}
			
		})
		
	}
	
	/**
	Read all records from a type
	- Parameters:
	- recordName an iCloud recordName id for fetch
	- returns: a (Result<Any, Error>) where Any contais a CKMRecord type object  in a completion handler
	*/
	public static func ckLoad(with recordName: String , then completion:@escaping (Result<Any, Error>)->Void) {
		
		// Executar o fetch
		
		// try get from cache
		if let record = CKMDefault.getFromCache(recordName) {
			do {
				//				let result:Self = try Self.ckLoad(from: record)
				let result:Self = try Self.load(from: record.asDictionary)
				completion(.success(result))
			} catch {
				completion(.failure(CRUDError.cannotMapRecordToObject))
				return
			}
		}
		
		// else get from database
		CKMDefault.database.fetch(withRecordID: CKRecord.ID(recordName: recordName), completionHandler: { (record, error) -> Void in
			
			// Got error
			if let error = error {
				completion(.failure(error))
				return
			}
			
			
			// else
			if let record = record {
				do {
					CKMDefault.addToCache(record)
					let result:Self = try Self.load(from: record)
					completion(.success(result))
					return
				} catch {
					CKMDefault.removeFromCache(record.recordID.recordName)
					completion(.failure(CRUDError.cannotMapRecordToObject))
					return
				}
			} else {
				completion(.failure(CRUDError.noSurchRecord))
			}
			
		})
		
	}
	
	public func ckDelete(then completion:@escaping (Result<String, Error>)->Void) {
		guard let recordName = self.recordName else { return }
		
		CKMDefault.database.delete(withRecordID: CKRecord.ID(recordName: recordName), completionHandler: { (_, error) -> Void in
			
			// Got error
			if let error = error {
				completion(.failure(error))
				return
			}
			// else
			completion(.success(recordName))
			CKMDefault.removeFromCache(recordName)
		})
	}
    
    //TODO: Make it Works
    public func ckDeleteCascade(then completion:@escaping (Result<String, Error>)->Void) {
        guard let recordName = self.recordName else { return }
        
        CKMDefault.database.delete(withRecordID: CKRecord.ID(recordName: recordName), completionHandler: { (_, error) -> Void in
            
            // Got error
            if let error = error {
                completion(.failure(error))
                return
            }
            // else
            completion(.success(recordName))
            CKMDefault.removeFromCache(recordName)
        })
    }
	
	public static func load(from record:CKRecord)throws->Self {
		if record.haveCycle() {
			//TODO: Trata criação de objeto com ciclo
			fatalError("Cannot have cycle loading object... yet")
		} // else
		
		let result:Self = try Self.load(from: record.asDictionary)
		return result
	}
	
    
    public mutating func reloadIgnoringFail(completion: ()->Void) {
        guard let recordName = self.recordName else { return }
        DispatchQueue.global().sync {
            var result:Self = self
            CKMDefault.database.fetch(withRecordID: CKRecord.ID(recordName: recordName), completionHandler: { (record, error) -> Void in

                // else
                if let record = record {
                    do {
                        CKMDefault.addToCache(record)
                        result = try Self.load(from: record)
                        CKMDefault.semaphore.signal()
                    } catch {}
                }

            })
            CKMDefault.semaphore.wait()
            self = result
            completion()
        }
    }
    
    public mutating func refresh(completion: ()->Void) {
        CKMDefault.removeFromCacheCascade(self.recordName ?? "_")
        self.reloadIgnoringFail(completion: completion)
    }
    public func syncRefresh()->Self {
        var refreshedRecord = self
        CKMDefault.removeFromCacheCascade(self.recordName ?? "_")
        refreshedRecord.reloadIgnoringFail(completion: {
            CKMDefault.semaphore.signal()
        })
        CKMDefault.semaphore.wait()
        return refreshedRecord
    }


}

/// Notification Managment
extension CKMCloudable {
	public static func register(observer:CKMRecordObserver) {
		
	}
}

/// Protocol for CK Notification Observers be warned when some register changed
public protocol CKMRecordObserver {
    func onReceive(notification: CKMNotification)
}
