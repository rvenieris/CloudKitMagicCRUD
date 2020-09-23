//
//  CKNotificationManager.swift
//  CloudKitMagic
//
//  Created by Ricardo Venieris on 18/08/20.
//  Copyright © 2020 Ricardo Venieris. All rights reserved.
//

import UIKit
import CloudKit
import UserNotifications

open class CKMNotificationManager: NSObject, UNUserNotificationCenterDelegate {
	private(set) var started = false
	open var observers:[CKRecord.RecordType:NSPointerArray] = [:]
	
	
	public override init() {
		super.init()
		self.resgisterInNotificationCenter()
	}
	
	open func start(){
		debugPrint("CKNotificationManager started")
		started = true
	}
	
	open func resgisterInNotificationCenter() {
		UNUserNotificationCenter.current().delegate = self
		UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound], completionHandler: { authorized, error in
			if authorized {
				DispatchQueue.main.async {
//					let app = UIApplication.shared.delegate as! AppDelegate
					 UIApplication.shared.registerForRemoteNotifications()
				}
				
			}
		})
	}
	
//	func createNotification<T:CKCloudable>(to recordObserver:CKMRecordObserver,
//										   for recordType:T.Type,
//										   adding subscription:CKQuerySubscription,
//										   with notificationInfo:CKSubscription.NotificationInfo) {
//		let subscription = CKQuerySubscription(recordType: recordType.ckRecordType, predicate: predicate, options:options)
//		subscription.notificationInfo = info
//		
//		self.add(observer: recordObserver, to: recordType.ckRecordType)
//		//TODO: Pegar as subscriptions que já existe e só adicionar se necessário
//		CKDefault.database.save(subscription, completionHandler: { subscription, error in
//			if error == nil {
//				// Subscription saved successfully
//				print("subscribed")
//			} else {
//				// An error occurred
//				print("error in subscription", error ?? "no error")
//			}
//		})
//}
	
	open func createNotification<T:CKMCloudable>(to recordObserver:CKMRecordObserver,
										   for recordType:T.Type,
										   options:CKQuerySubscription.Options? = nil,
										   predicate: NSPredicate? = nil,
										   alertBody:String? = nil) {
		UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
		UIApplication.shared.applicationIconBadgeNumber = 0
		let options = options ?? [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
		let predicate = predicate ?? NSPredicate(value: true)
		let alertBody = alertBody ?? "\(recordType.ckRecordType): new record posted!"
		
		let info = CKSubscription.NotificationInfo()
		info.alertBody = alertBody
		info.soundName = "default"
		info.category = recordType.ckRecordType
		info.shouldSendContentAvailable = true
		info.shouldSendMutableContent = true
		
		let subscription = CKQuerySubscription(recordType: recordType.ckRecordType, predicate: predicate, options:options)
		subscription.notificationInfo = info
		
		self.add(observer: recordObserver, to: recordType.ckRecordType)
		//TODO: Pegar as subscriptions que já existe e só adicionar se necessário
		CKMDefault.database.save(subscription, completionHandler: { subscription, error in
			if error == nil {
				// Subscription saved successfully
				print("subscribed")
			} else {
				// An error occurred
				print("error in subscription", error ?? "no error")
			}
		})
	}
	
	private func add(observer:CKMRecordObserver, to identifier:String) {
		self.observers[identifier] = self.observers[identifier] ?? NSPointerArray.strongObjects()
		self.observers[identifier]?.addObject(observer as AnyObject)
	}
	
	open func notifyObserversFor(_ notification: UNNotification) {
		print(notification.request.content.categoryIdentifier)
		let recordTypeName = notification.request.content.categoryIdentifier
		self.observers.forEach {$0.value.compact()}
		let interestedObservers = observers.filter {$0.key == recordTypeName}
		for observers in interestedObservers {
			for observer in observers.value.allObjects {
				(observer as? CKMRecordObserver)?.onChange(ckRecordtypeName: recordTypeName)
			}
		}
	}
	
	
	open func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
		completionHandler([]) //.alert, .sound, .badge
		print(#function)
		print(notification.debugDescription)
		notifyObserversFor(notification)
//		completionHandler(UNNotificationPresentationOptions.badge)
	}
	
	open func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
		print(#function)
	}
	
	
	open func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		print(#function)
	}

}
