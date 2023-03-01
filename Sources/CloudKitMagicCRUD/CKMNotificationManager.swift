//
//  CKNotificationManager.swift
//  CloudKitMagic
//
//  Created by Ricardo Venieris on 18/08/20.
//  Copyright © 2020 Ricardo Venieris. All rights reserved.
//

    // iOS, tvOS, and watchOS
#if canImport(UIKit)
import UIKit
import CloudKit
import UserNotifications

open class CKMNotificationManager: NSObject, UNUserNotificationCenterDelegate {
	open var observers:[CKRecord.RecordType:NSPointerArray] = [:]
    public static var shared = { CKMNotificationManager() }()
	
	
	private override init() {
		super.init()
		self.resgisterInNotificationCenter()
		debugPrint("CKNotificationManager started")
	}
	
	open func resgisterInNotificationCenter() {
		UNUserNotificationCenter.current().delegate = self
		UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound], completionHandler: { authorized, error in
			if authorized {
				DispatchQueue.main.async {
					//					let app = UIApplication.shared.delegate as! AppDelegate
//                    if #available(iOS 8, macCatalyst 13.1, tvOS 9, *)
                    UIApplication.shared.registerForRemoteNotifications()
				}
				
			}
		})
	}
	
	open func createNotification<T:CKMCloudable>(to recordObserver:CKMRecordObserver,
												 for recordType:T.Type,
												 options:CKQuerySubscription.Options? = nil,
												 predicate: NSPredicate? = nil,
												 alertBody:String? = nil,
                                                 completion: @escaping (Result<CKSubscription, Error>)->Void ) {
    
		let options = options ?? [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
		let predicate = predicate ?? NSPredicate(value: true)
//		let alertBody = alertBody ?? "\(recordType.ckRecordType): new record posted!"
		
		let info = CKSubscription.NotificationInfo()
		info.alertBody = alertBody
//		info.soundName = "default"
		info.category = recordType.ckRecordType
		info.shouldSendContentAvailable = true
		info.shouldSendMutableContent = true
		
		let subscription = CKQuerySubscription(recordType: recordType.ckRecordType, predicate: predicate, options:options)
		subscription.notificationInfo = info
        
		
		self.add(observer: recordObserver, to: recordType.ckRecordType)
		//TODO: Pegar as subscriptions que já existe e só adicionar se necessário
		CKMDefault.database.save(subscription, completionHandler: { subscription, error in
            if let subscription = subscription {
                // Subscription saved successfully
                completion(.success(subscription))
            }
            else if let error = error {
                // An error occurred
                completion(.failure(error))
                debugPrint("error in subscription", error)
			}
		})
	}
    
    open func deleteSubscription(with id:CKSubscription.ID, then completion:@escaping (Result<String, Error>)->Void) {
            CKMDefault.database.delete(withSubscriptionID: id, completionHandler: { message, error in
                if let message = message {
                    completion(.success(message))
                }
                else if let error = error {
                    completion(.failure(error))
                }
        })
    }
	private func add(observer:CKMRecordObserver, to identifier:String) {
		self.observers[identifier] = self.observers[identifier] ?? NSPointerArray.strongObjects()
		self.observers[identifier]?.addObject(observer as AnyObject)
	}
	
	open func notifyObserversFor(_ notification: UNNotification) {
		let recordTypeName = notification.request.content.categoryIdentifier
        
		self.observers.forEach {$0.value.compact()}
		let interestedObservers = observers.filter {$0.key == recordTypeName}
		for observers in interestedObservers {
			for observer in observers.value.allObjects {
                (observer as? CKMRecordObserver)?.onReceive(notification: CKMNotification(from: notification))
			}
		}
	}
	
	open func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
		completionHandler([]) //.alert, .sound, .badge
		notifyObserversFor(notification)
		//		completionHandler(UNNotificationPresentationOptions.badge)
	}
	
	open func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
		debugPrint(#function)
	}
	
	
	open func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		debugPrint(#function)
	}
	
}



/**
 A simplified UNNotification data
 
 - Parameter:
    - categoty: Date - The category of the notification, usualy a class name.
    - recordID:String? - The RecordID of the record that triggers the notification
    - subscriptionID:String? - The ID of subscription trigged
    - zoneID:String? - The zoneID of the pubscription that triggers notification
    - userID:String? - The user that make the changes
    - date: Date - The delivery date of the notification.
    - identifier:String : The unique identifier for this notification request.
    - title: String - A short description of the reason for the alert.
    -  subtitle: String - A secondary description of the reason for the alert.
    -  body: String - The message displayed in the notification alert.
    -  badge: NSNumber? - The number to display as the app’s icon badge.
    -  sound: UNNotificationSound? - The sound to play when the notification is delivered.
    -  launchImageName: String - The name of the launch image to display when your app is launched in response to the notification
 */
open class CKMNotification {
    
    public let category: String
    public let recordID:String?
    public let subscriptionID:String?
    public let zoneID:String?
    public let userID:String?
    public let date:Date
    public let identifier: String
    public let title: String
    public let subtitle: String
    public let body: String
    public let badge: NSNumber?
    public let sound: UNNotificationSound?
    public let launchImageName: String
//     -  userInfo: [AnyHashable : Any] - A dictionary of custom information associated with the notification.
//    public let userInfo: [AnyHashable : Any]
    
    public init(from notification: UNNotification) {
        self.category = notification.request.content.categoryIdentifier
        self.date = notification.date
        self.identifier = notification.request.identifier
        self.title = notification.request.content.title
        self.subtitle = notification.request.content.subtitle
        self.body = notification.request.content.body
        self.badge = notification.request.content.badge
        self.sound = notification.request.content.sound
        self.launchImageName = notification.request.content.launchImageName
        
        let userInfo = notification.request.content.userInfo
//        self.userInfo = userInfo

        let ck = userInfo["ck"] as? [AnyHashable:Any]
        self.userID = ck?["ckuserid"] as? String
        
        let qry = ck?["qry"] as? [AnyHashable:Any]
        self.recordID = qry?["rid"] as? String
        self.subscriptionID = qry?["sid"] as? String
        self.zoneID = qry?["zid"] as? String
        
    }
}


    /// Adding register observer method to CKMCloudable
extension CKMCloudable {
    public static func register(observer:CKMRecordObserver) {
        
    }
}

    /// Protocol for CK Notification Observers be warned when some register changed
public protocol CKMRecordObserver {
    func onReceive(notification: CKMNotification)
}


extension CKMDefault {
    public static var notificationManager:CKMNotificationManager! = CKMNotificationManager.shared
    
}

#endif
