//
//  BlockRetainSelf.h
//  blockRetainSelf
//
//  Created by 方阳 on 2018/7/30.
//  Copyright © 2018年 yy. All rights reserved.
//
#ifdef DEBUG
#import <Foundation/Foundation.h>

@interface BlockRetainSelf : NSObject

+ (instancetype)sharedChecker;

- (void)addPrefix:(NSString*)prefix;
- (void)addClassname:(NSString*)clsname;
- (void)handleBlockchecking;

@end
#endif
