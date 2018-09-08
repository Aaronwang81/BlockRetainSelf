//
//  BRSIntercepter.h
//  blockRetainSelf
//
//  Created by 方阳 on 2018/7/30.
//  Copyright © 2018年 yy. All rights reserved.
//
#ifdef DEBUG
#import <Foundation/Foundation.h>
#import "BRSBase.h"

@interface NSObject(BRSIntercepter)

+ (void)hookSelector_BRSIntercepter:(SEL)selector withBlock:(id)block error:(NSError**)error;

@end

@interface BRSIntercepterInfo: NSObject

@property (nonatomic,assign) SEL selector;
@property (nonatomic,strong) id block;

@end
#endif
