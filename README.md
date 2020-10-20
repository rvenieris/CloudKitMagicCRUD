# CloudKitMagic

## How to use it

### Configuring your project
1. Import this package
2. Enable iCloud on your project
1. Be sure that CloudKit service is marked
2. Select or Create a Container for the project
3. Be sure that you Container exists in your iCloud visiting  [https://icloud.developer.apple.com/dashboard/](https://icloud.developer.apple.com/dashboard/)
3. In AppDelegate, didFinishLaunchingWithOptions function add a line setting your container if needed as
> CKMDefault.containerIdentifyer = "iCloud.My.CloudContainer"
>
>  *If needed you can also start the notification Manager here*
>
> CKMDefault.notificationManager.start()


### Creating your data

1. Create your data Model classes or structs
2. import CloudKitMagicCRUD
3. Conform them with CKMRecord


CKMRecord has a mandatory field and sobe optional fields
-- Mandatory
recordName:String? -> When it's a saved record, contains the record ID
-- Optionals
createdBy:String -> Contains creator RecordName
createdAt:Date -> Conntains creation Date
modifiedBy:String -> Contains last modifier RecordName
modifiedAt:Date -> Conntainslast modificatio Date
changeTag:String -> a tag that changes at each modification

