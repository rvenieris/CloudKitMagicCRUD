//
//  Enums.swift
//  CloudKitExample
//
//  Created by Ricardo Venieris on 26/07/20.
//  Copyright © 2020 Ricardo Venieris. All rights reserved.
//

import Foundation


public enum CRUDError:Int, Error {
	case invalidRecord
	case invalidRecordID
	case cannnotMapAllRecords
	case cannotDeleteRecord
	case cannotMapRecordToObject
	case noSurchRecord
	case needToSaveRefferencedRecord
	case invalidFieldType_Dictionary
	
}

