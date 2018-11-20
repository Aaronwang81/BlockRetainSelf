//
//  BRSStackChecker.h
//  blockRetainSelf
//
//  Created by 方阳 on 2018/11/20.
//  Copyright © 2018年 yy. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BRSStackChecker : NSObject

+ (instancetype)sharedChecker;

- (NSString*)getClassNameAtFrame:(NSInteger)index;

@end

NS_ASSUME_NONNULL_END
