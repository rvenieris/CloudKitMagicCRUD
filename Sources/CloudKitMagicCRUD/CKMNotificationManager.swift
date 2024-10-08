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
import Combine

open class CKMNotificationManager: NSObject, UNUserNotificationCenterDelegate {
	open var observers:[CKRecord.RecordType:NSPointerArray] = [:]
    public static var shared = { CKMNotificationManager() }()
    @available(iOS 13.0, *)
    public static let receivedNotificationPublisher = PassthroughSubject<CKMNotification, Never>()
    
	
	private override init() {
		super.init()
		self.resgisterInNotificationCenter()
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
    
    @available(iOS 13.0, *)
    public static func notificationHandler(userInfo: [AnyHashable : Any]) {


        let aps = userInfo["aps"] as? [String: Any]
        let category = aps?["category"] as? String

        let ck = userInfo["ck"] as? [AnyHashable: Any]
        let userID = ck?["ckuserid"] as? String
        let qry = ck?["qry"] as? [AnyHashable: Any]
        let recordID = qry?["rid"] as? String
        let subscriptionID = qry?["sid"] as? String
        let zoneID = qry?["zid"] as? String
                
                
        Self.receivedNotificationPublisher.send(CKMNotification(category: category ?? "unknown", recordID: recordID, subscriptionID: subscriptionID, zoneID: zoneID, userID: userID, date: Date(), identifier: "", title: "", subtitle: "", body: "", badge: nil, sound: nil, launchImageName: ""))
                
            
        
    }
	open func createNotification<T:CKMCloudable>(to recordObserver:CKMRecordObserver,
												 for recordType:T.Type,
												 options:CKQuerySubscription.Options? = nil,
												 predicate: NSPredicate? = nil,
												 alertBody:String? = nil,
                                                 completion: @escaping (Result<CKSubscription, Error>)->Void ) {
#if !os(tvOS)

    
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
        #endif
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
#if !os(tvOS)

		let recordTypeName = notification.request.content.categoryIdentifier
        
		self.observers.forEach {$0.value.compact()}
		let interestedObservers = observers.filter {$0.key == recordTypeName}
		for observers in interestedObservers {
			for observer in observers.value.allObjects {
                (observer as? CKMRecordObserver)?.onReceive(notification: CKMNotification(from: notification))
			}
		}
        #endif
	}
	
	open func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
		completionHandler([]) //.alert, .sound, .badge
		notifyObserversFor(notification)
		//		completionHandler(UNNotificationPresentationOptions.badge)
	}
#if !os(tvOS)

	open func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
		debugPrint(#function)
	}
	
	
	open func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		debugPrint(#function)
	}
#endif
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
#if !os(tvOS)
    public let sound: UNNotificationSound?
#endif
    public let launchImageName: String
    //     -  userInfo: [AnyHashable : Any] - A dictionary of custom information associated with the notification.
    //    public let userInfo: [AnyHashable : Any]
    
    public init(from notification: UNNotification) {
#if !os(tvOS)
        
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
#else
        
        self.date = Date()
        self.identifier = ""
        self.title = ""
        self.subtitle = ""
        self.body = ""
        self.category = ""
        self.launchImageName = ""
        self.recordID = nil
        self.subscriptionID = nil
        self.zoneID = nil
        self.userID = nil
        self.badge = nil

        
        #endif
    }
    
    public init(category: String, recordID: String? = nil, subscriptionID: String? = nil, zoneID: String? = nil, userID: String? = nil, date: Date, identifier: String, title: String, subtitle: String, body: String, badge: NSNumber? = nil, sound: UNNotificationSound? = nil, launchImageName: String) {
        self.category = category
        self.recordID = recordID
        self.subscriptionID = subscriptionID
        self.zoneID = zoneID
        self.userID = userID
        self.date = date
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.badge = badge
        self.sound = sound
        self.launchImageName = launchImageName
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
