/*

 File: LeDataService.m
 
 Abstract: Data Service Code - Connect to a peripheral
 and send and receive data.
 
 
 */



#import "LeDataService.h"
#import "LeDiscovery.h"


NSString *kDataServiceUUIDString = @"FFF0";
NSString *kWriteCharacteristicUUIDString = @"FFF2";
NSString *kReadCharacteristicUUIDString = @"FFF1";

NSString *kDataServiceEnteredBackgroundNotification = @"kDataServiceEnteredBackgroundNotification";
NSString *kDataServiceEnteredForegroundNotification = @"kDataServiceEnteredForegroundNotification";

@interface LeDataService() <CBPeripheralDelegate> {
@private
    CBPeripheral		*servicePeripheral;
    
    CBService			*dataService;
    
    CBCharacteristic    *writeCharacteristic;
    CBCharacteristic    *readCharacteristic;
    
    CBUUID              *readUUID;
    CBUUID              *writeUUID;

    id<LeDataProtocol>	peripheralDelegate;
}
@end



@implementation LeDataService


@synthesize peripheral = servicePeripheral;


#pragma mark -
#pragma mark Init
/****************************************************************************/
/*								Init										*/
/****************************************************************************/
- (id) initWithPeripheral:(CBPeripheral *)peripheral controller:(id<LeDataProtocol>)controller
{
    self = [super init];
    if (self) {
        
        servicePeripheral = [peripheral retain];
        [servicePeripheral setDelegate:self];
		peripheralDelegate = controller;
        
        writeUUID	= [[CBUUID UUIDWithString:kWriteCharacteristicUUIDString] retain];
        readUUID	= [[CBUUID UUIDWithString:kReadCharacteristicUUIDString] retain];
	}
    return self;
}


- (void) dealloc {
	if (servicePeripheral) {
		[servicePeripheral setDelegate:[LeDiscovery sharedInstance]];
		[servicePeripheral release];
		servicePeripheral = nil;
        
        [writeUUID release];
        [readUUID release];
        
    }
    [super dealloc];
}


- (void) reset
{
	if (servicePeripheral) {
		[servicePeripheral release];
		servicePeripheral = nil;
	}
}



#pragma mark -
#pragma mark Service interaction
/****************************************************************************/
/*							Service Interactions							*/
/****************************************************************************/
- (void) setController:(id<LeDataProtocol>)controller
{
    peripheralDelegate = controller;

}

- (void) start
{
	CBUUID	*serviceUUID	= [CBUUID UUIDWithString:kDataServiceUUIDString];
	NSArray	*serviceArray	= [NSArray arrayWithObjects:serviceUUID, nil];

    [servicePeripheral discoverServices:serviceArray];
}

- (void) peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
	NSArray		*services	= nil;
	NSArray		*uuids	= [NSArray arrayWithObjects:writeUUID, // Write Characteristic
								   readUUID, // Read Characteristic
								   nil];

	if (peripheral != servicePeripheral) {
		NSLog(@"Wrong Peripheral.\n");
		return ;
	}
    
    if (error != nil) {
        NSLog(@"Error %@\n", error);
		return ;
	}

	services = [peripheral services];
	if (!services || ![services count]) {
		return ;
	}

	dataService = nil;
    
	for (CBService *service in services) {
		if ([[service UUID] isEqual:[CBUUID UUIDWithString:kDataServiceUUIDString]]) {
			dataService = service;
			break;
		}
	}

	if (dataService) {
		[peripheral discoverCharacteristics:uuids forService:dataService];
	}
}


- (void) peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error;
{
	NSArray		*characteristics	= [service characteristics];
	CBCharacteristic *characteristic;
    
	if (peripheral != servicePeripheral) {
		NSLog(@"Wrong Peripheral.\n");
		return ;
	}
	
	if (service != dataService) {
		NSLog(@"Wrong Service.\n");
		return ;
	}
    
    if (error != nil) {
		NSLog(@"Error %@\n", error);
		return ;
	}
    
	for (characteristic in characteristics) {
        NSLog(@"discovered characteristic %@", [characteristic UUID]);
        
		if ([[characteristic UUID] isEqual:readUUID]) { // Read
            NSLog(@"Discovered Read Characteristic");
			readCharacteristic = [characteristic retain];
            [peripheral setNotifyValue:YES forCharacteristic:characteristic];
		}
        else if ([[characteristic UUID] isEqual:writeUUID]) { // Write
            NSLog(@"Discovered Write Characteristic");
			writeCharacteristic = [characteristic retain];
		} 
	}
}



#pragma mark -
#pragma mark Characteristics interaction
/****************************************************************************/
/*						Characteristics Interactions						*/
/****************************************************************************/
- (void) write:(NSData *)data
{
    
    if (!servicePeripheral) {
        NSLog(@"Not connected to a peripheral");
		return ;
    }

    if (!writeCharacteristic) {
        NSLog(@"No valid write characteristic");
        return;
    }
    
    if (!data) {
        NSLog(@"Nothing to write");
        return;
    }

    [servicePeripheral writeValue:data forCharacteristic:writeCharacteristic type:CBCharacteristicWriteWithResponse];
}


/** If we're connected, we don't want to be getting temperature change notifications while we're in the background.
 We will want read notifications, so we don't turn those off.
 */
- (void)enteredBackground
{
    // Find the fishtank service
    for (CBService *service in [servicePeripheral services]) {
        if ([[service UUID] isEqual:[CBUUID UUIDWithString:kDataServiceUUIDString]]) {
            
            // Find the temperature characteristic
            for (CBCharacteristic *characteristic in [service characteristics]) {
                if ( [[characteristic UUID] isEqual:[CBUUID UUIDWithString:kWriteCharacteristicUUIDString]] ) {
                    
                    // And STOP getting notifications from it
                    [servicePeripheral setNotifyValue:NO forCharacteristic:characteristic];
                }
            }
        }
    }
}

/** Coming back from the background, we want to register for notifications again for the temperature changes */
- (void)enteredForeground
{
    // Find the fishtank service
    for (CBService *service in [servicePeripheral services]) {
        if ([[service UUID] isEqual:[CBUUID UUIDWithString:kDataServiceUUIDString]]) {
            
            // Find the temperature characteristic
            for (CBCharacteristic *characteristic in [service characteristics]) {
                if ( [[characteristic UUID] isEqual:[CBUUID UUIDWithString:kWriteCharacteristicUUIDString]] ) {
                    
                    // And START getting notifications from it
                    [servicePeripheral setNotifyValue:YES forCharacteristic:characteristic];
                }
            }
        }
    }
}


- (void) peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{

	if (peripheral != servicePeripheral) {
		NSLog(@"Wrong peripheral\n");
		return ;
	}

    if ([error code] != 0) {
		NSLog(@"Error %@\n", error);
		return ;
	}
    
    /* Data to read */
    if ([[characteristic UUID] isEqual:readUUID]) {
        
        [peripheralDelegate serviceDidReceiveData:[readCharacteristic value] fromService:self];
        return;
    }

}


- (void) peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    /* When a write occurs, need to set off a re-read of the local CBCharacteristic to update its value */
    [peripheral readValueForCharacteristic:characteristic];

}
@end