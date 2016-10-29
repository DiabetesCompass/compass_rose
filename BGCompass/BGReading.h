//
//  BGReading.h
//  Compass
//
//  Created by macbookpro on 4/14/13.
//  Copyright (c) 2013 Clif Alferness. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "Reading.h"


@interface BGReading : Reading

extern NSString *const stringForUnitsInMoles;
extern NSString *const stringForUnitsInMilligrams;

//@property (nonatomic, retain) NSString * name;
@property (nonatomic, retain) NSNumber * quantity;
//@property (nonatomic, retain) NSDate * timeStamp;
//@property (nonatomic, retain) NSNumber * isFavorite;

+(NSString *) displayString:(NSNumber*) value withConversion:(BOOL)convert;
-(NSString *) displayString;
+(BOOL) isInMoles;

//-(NSString *) itemValue;
-(void) setQuantity:(NSNumber *)quantity withConversion:(BOOL)action;
+ (float) getValue:(float)value withConversion: (BOOL) convert;

@end
