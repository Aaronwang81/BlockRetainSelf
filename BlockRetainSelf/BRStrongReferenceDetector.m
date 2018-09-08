//
//  BLStrongReferenceDetector.m
//  blockRetainSelf
//
//  Created by 方阳 on 2018/7/30.
//  Copyright © 2018年 yy. All rights reserved.
//

#import "BRStrongReferenceDetector.h"
#import <objc/runtime.h>

static void byref_keep_nop(struct _block_byref_block *dst, struct _block_byref_block *src) {}
static void byref_dispose_nop(struct _block_byref_block *param) {}

@implementation BRSStrongReferenceDetector

- (oneway void)release
{
    _strong = YES;
}

- (id)retain
{
    return self;
}

+ (id)alloc
{
    BRSStrongReferenceDetector *obj = [super alloc];
    
    // Setting up block fakery
    obj->forwarding = obj;
    obj->byref_keep = byref_keep_nop;
    obj->byref_dispose = byref_dispose_nop;
    
    return obj;
}

- (oneway void)trueRelease
{
    [super release];
}

- (void *)forwarding
{
    return self->forwarding;
}

@end
