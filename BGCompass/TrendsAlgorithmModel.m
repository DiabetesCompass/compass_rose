//
//  TrendsAlgorithmModel.m
//  CompassRose
//
//  Created by Christopher Balcells on 11/22/13.
//  Copyright (c) 2014 Clif Alferness. All rights reserved.
//

#import "TrendsAlgorithmModel.h"
#import "Constants.h"

// import <project name>-Swift.h so Objective C can see Swift code
// note don't import <class name>-Swift.h, that won't work
// http://stackoverflow.com/questions/24078043/call-swift-function-from-objective-c-class#24087280
#import "BGCompass-Swift.h"

@interface TrendsAlgorithmModel()

@end

@implementation TrendsAlgorithmModel

NSTimeInterval hemoglobinLifespanSeconds = 0.0;

+ (id)sharedInstance {
    static TrendsAlgorithmModel *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        self.trend_queue = dispatch_queue_create("trend_queue", DISPATCH_QUEUE_SERIAL);
        [self addObservers];
        [self loadArrays];

        hemoglobinLifespanSeconds = 100.0 * HOURS_IN_ONE_DAY * SECONDS_IN_ONE_HOUR;
    }
    return self;
}

// - observer
- (void)addObservers {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNotifications:) name:NOTE_REJECTED object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNotifications:) name:NOTE_SETTINGS_CHANGED object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNotifications:) name:NOTE_BGREADING_ADDED object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNotifications:) name:NOTE_BGREADING_EDITED object:nil];
}

- (void) handleNotifications:(NSNotification*) note {
    NSLog(@"Received notification name: %@", [note name]);
    if ([[note name] isEqualToString:NOTE_BGREADING_ADDED]) {
        NSDate* new_timeStamp = [note.userInfo valueForKey:@"timeStamp"];
        dispatch_async(self.trend_queue, ^{
            [self correctTrendReadingsAfterDate:new_timeStamp];
        });
    } else if ([[note name] isEqualToString:NOTE_BGREADING_EDITED]) {
        NSDate* timeStamp = [note.userInfo valueForKey:@"timeStamp"];
        dispatch_async(self.trend_queue, ^{
            [self correctTrendReadingsAfterDate:timeStamp];
        });
    }
}

- (void) loadArrays {
    self.ha1cArray = [Ha1cReading MR_findAllSortedBy:@"timeStamp" ascending:YES inContext:[NSManagedObjectContext MR_defaultContext]];
    self.bgArray = [BGReading MR_findAllSortedBy:@"timeStamp" ascending:YES inContext:[NSManagedObjectContext MR_defaultContext]];
}

//count HA1c readings?
- (NSNumber*) ha1cArrayCount {
    NSNumber* result;
    if (self.ha1cArray) {
        result = @([self.ha1cArray count]);
        NSLog(@"There are HA1c readings:%@", result);
    } else {
        result = @(0);
    }
    return result;
}

//count BG readings?
- (NSNumber*) bgArrayCount {
    NSNumber* result;
    if (self.bgArray) {
        result = @([self.bgArray count]);
    } else {
        result = @(0);
    }
    return result;
}

 //fetch previous HA1c readings?
- (Ha1cReading*) getFromHa1cArray:(NSUInteger)index {
    Ha1cReading* result;
    if (self.ha1cArray) {
        result = [self.ha1cArray objectAtIndex:index];
    } else {
        result = nil;
    }
    return result;
}

//fetch previous BG readings?
- (BGReading*) getFromBGArray:(NSUInteger)index {
    BGReading* result;
    if (self.bgArray && self.bgArray.count != 0) {
        result = [self.bgArray objectAtIndex:index];
    } else {
        result = nil;
    }
    return result;
}

- (void) correctTrendReadingsAfterDate:(NSDate*) lowerBound {
//    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"timeStamp >= %@", lowerBound];
    
    NSArray *fetchedReadings = [BGReading MR_findAllSortedBy:@"timeStamp" ascending:YES inContext:[NSManagedObjectContext MR_defaultContext]];
    NSLog(@"%lu readings", (unsigned long)fetchedReadings.count);
    NSArray *fetchedHa1c = [Ha1cReading MR_findAllSortedBy:@"timeStamp" ascending:YES inContext:[NSManagedObjectContext MR_defaultContext]];
    for (Ha1cReading* reading in fetchedHa1c) {
        [reading MR_deleteEntityInContext:[NSManagedObjectContext MR_defaultContext]];
    }

    for (BGReading* reading in fetchedReadings) {
        NSLog(@"Correcting reading for %f", MG_PER_DL_PER_MMOL_PER_L*reading.quantity.floatValue);
        [self calculateHa1c:reading];
    }
}

- (void) calculateHa1c:(BGReading*) bgReading {

    [self loadArrays];

    // bloodGlucoseRecentReadingsWithCurrentReading defined in TrendsAlgorithmModelExtension.swift
    NSArray *recentBGReadings =
    [self bloodGlucoseRecentReadingsWithCurrentReading: bgReading
                                              readings: self.bgArray
                             hemoglobinLifespanSeconds: hemoglobinLifespanSeconds];

    if ((recentBGReadings == nil) || (recentBGReadings.count == 0)) {
        return;
    }

    // Interpolate readings
    /////////////////////////////////////////////////////////////////////

    // TODO: Extract some Objective C code below to
    // TrendsAlgorithmModelExtension.swift methods like ha1cValueForBgReadings
    // Call Swift methods here to get an interpolated value,
    // then within Obj C change values observed by MagicalRecord

    int interval = 10; // interpolated array will be at 10 minute intervals.
    int arraysize = (int) (hemoglobinLifespanSeconds / interval) + 1;

    // The array will contain up to 100 days of readings.
    float interpolated[arraysize];
    BGReading* previousReading = nil;
    int bigIndex = 0;
    float ramp = 1.0;
    float delta = 1 / hemoglobinLifespanSeconds;
    float sum =0.0;
    float sumRamp = 0.0;
    float twBGAve = 0.0;
    float twHA1c = 0.0;
    for (BGReading* reading in recentBGReadings) {

        if (recentBGReadings.count == 1) {
            interpolated[bigIndex] =reading.quantity.floatValue;
            sum = interpolated[bigIndex];
            sumRamp = sumRamp + ramp;
            ramp = ramp - delta;
            bigIndex++;

        } else {
            if (previousReading) {
                int minutesBetweenReadings = (int)[reading.timeStamp timeIntervalSinceDate:previousReading.timeStamp]/(SECONDS_IN_ONE_MINUTE);
                minutesBetweenReadings = abs(minutesBetweenReadings);
                if (minutesBetweenReadings < interval) {
                    continue; // If two readings are within an interval of each other ignore this one. Move to the next.
                }
                for (int index = 0; index < minutesBetweenReadings/interval; index++ ) {
                    interpolated[bigIndex] = previousReading.quantity.floatValue + index*(reading.quantity.floatValue - previousReading.quantity.floatValue)/(minutesBetweenReadings/interval);
                    sum = sum + interpolated[bigIndex ]*ramp;
                    sumRamp = sumRamp + ramp;
                    ramp = ramp - delta;
                    bigIndex++;
                }
            }
            NSLog(@"BG indexed: %f", MG_PER_DL_PER_MMOL_PER_L*reading.quantity.floatValue);
            previousReading = reading;
        }
        twBGAve = (sum)/sumRamp;
    }

    NSLog(@"weighted average BG: %f", MG_PER_DL_PER_MMOL_PER_L*twBGAve);
    twHA1c = (46.7 + MG_PER_DL_PER_MMOL_PER_L*twBGAve)/28.7;
    //log &Add final result to CoreData
    NSLog(@"weighted average HA1c: %f", twHA1c);
    
    /////////////////////////////////////////////////////////////////////


    Ha1cReading* reading = [Ha1cReading MR_createEntityInContext:[NSManagedObjectContext MR_defaultContext]];
    reading.quantity = @(twHA1c);

    //set the timestamp of this HA1c to the timestamp of the last BG reading??
    // NOTE: if they are exactly equal this might cause problem with predicate/filtering
    // reading.timeStamp = [self lastBGReading.timeStamp;
    
    [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreAndWait];
    [self loadArrays];
}

@end
