//
//  C64IAPHelper.m
//  CameraC64
//
//  Created by Thomas Conté on 10/9/12.
//  Copyright (c) 2012 Cell Phone. All rights reserved.
//

#import "C64IAPHelper.h"

@implementation C64IAPHelper

+ (C64IAPHelper *)sharedInstance {
    static dispatch_once_t once;
    static C64IAPHelper * sharedInstance;
    dispatch_once(&once, ^{
        NSSet * productIdentifiers = [NSSet setWithObjects:
                                      @"AXOLINK_C64_FILTERS",
                                      nil];
        sharedInstance = [[self alloc] initWithProductIdentifiers:productIdentifiers];
    });
    return sharedInstance;
}

@end
