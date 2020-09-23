//
//  CKCascadeTransactions.swift
//  CloudKitMagic
//
//  Created by Ricardo Venieris on 20/08/20.
//  Copyright © 2020 Ricardo Venieris. All rights reserved.
//

import CloudKit

open class CKMPreparedRecord {
	open var pending:[CKMPreparedRecord.Reference] = []
	open var objectSaving:CKMCloudable
	open var record:CKRecord
	
	open var allPendingValuesFilled:Bool {
		for item in pending {
			guard let _ = record.value(forKey: item.pendingCyclicReferenceName) else {return false}
		}
		return true
	}

	public init(for objectSaving:CKMCloudable, in record:CKRecord) {
		self.objectSaving = objectSaving
		self.record = record
	}
	
	open class Reference {
		open var cyclicReferenceBranch:CKMCloudable
		open var pendingCyclicReferenceName:String

		public init(value cyclicReferenceBranch:CKMCloudable,
			 forKey pendingCyclicReferenceName:String) {
			self.cyclicReferenceBranch = cyclicReferenceBranch
			self.pendingCyclicReferenceName = pendingCyclicReferenceName
			
		}
	}
	
	
	open func add(value cyclicReferenceBranch:CKMCloudable, forKey pendingCyclicReferenceName:String) {
		let new = CKMPreparedRecord.Reference(value: cyclicReferenceBranch, forKey: pendingCyclicReferenceName)
		pending.append(new)
	}
	
	open func dispatchPending(for savedRecord:CKRecord, then completion:@escaping (Result<CKRecord, Error>)->Void) {
		// Me atualizar
		self.record = savedRecord
		self.objectSaving.recordName = record.recordID.recordName
		CKMDefault.addToCache(record)
		
		// Verificar se tá tudo bem com o recordName (unwrap)
		guard let _ = objectSaving.recordName else {
			debugPrint("Cannot dispatch pending without a saved Record")
			debugPrint("Object \(objectSaving) must have a recordName")
			return
		}
		
		// checar se há pendências
		guard !pending.isEmpty else {
			completion(.success(record))
			return
		}
		
		// Se existem pendências,
		for item in pending {
			// Salva cada uma delas
			item.cyclicReferenceBranch.ckSave(then: { result in
				switch result {
					case .success(let savedBranchRecord):
						guard let referenceID = (savedBranchRecord as? CKMCloudable)?.recordName else {
							debugPrint("Error saving reference object for \(item.pendingCyclicReferenceName) in \(self.record.recordType) - Record saved without reference")
							dump(self.record)
							return
						}
						// Ao salvar faz o update do record referenciado
						self.updateRecord(with: referenceID, in: item, then: completion)
					case .failure(let error):
						debugPrint("Error saving reference object for \(item.pendingCyclicReferenceName) in \(self.record.recordType)")
						dump(error)
				}
			})
		}
	}
	
	open func updateRecord(with reference: String, in item: CKMPreparedRecord.Reference, then completion:@escaping (Result<CKRecord, Error>)->Void) {
		let reference = CKRecord.Reference(recordID: CKRecord.ID(recordName: reference), action: .none)
		let referenceField = item.pendingCyclicReferenceName
		// if item is Reference_Array
		if var referenceArray = self.record.value(forKey: referenceField) as? [CKRecord.Reference] {
			referenceArray.append(reference)
			self.record.setValue(referenceArray, forKey: referenceField)
		}
		// if item is single Reference
		else {
			self.record.setValue(reference, forKey: referenceField)
		}
		
		// Se acabaram as pendências
		if self.allPendingValuesFilled {
			// Atualiza o CKRecord no BD, e completa com o resultado
			CKMDefault.database.save(self.record, completionHandler: {
				(record,error) -> Void in
				
				// if Got error
				if let error = error {
					completion(.failure(error))
				}
				// if CKRecord Saved
				else if let record = record {
					CKMDefault.addToCache(record)
					completion(.success(record))
				}
			})
		}

	}
	
}
