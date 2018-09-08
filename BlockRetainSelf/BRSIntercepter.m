//
//  BRSIntercepter.m
//  blockRetainSelf
//
//  Created by 方阳 on 2018/7/30.
//  Copyright © 2018年 yy. All rights reserved.
//
#ifdef DEBUG
#import "BRSIntercepter.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import "BRStrongReferenceDetector.h"

static const char *BlockSig(id blockObj)
{
    struct BRSBlock_literal *block = (__bridge struct BRSBlock_literal *)blockObj;
    struct BRSBlock_descriptor *descriptor = block->descriptor;
    
    int copyDisposeFlag = 1 << 25;
    int signatureFlag = 1 << 30;
    
    assert(block->flags & signatureFlag);
    if( !(block->flags & signatureFlag) )
    {
        //        BL_LOG_INFO(@"BlockSig", @"fatal error:block no signatureflag");
        return NULL;
    }
    
    int index = 0;
    if(block->flags & copyDisposeFlag)
    {
        index += 2;
    }
    if( index == 0 )
    {
        return NULL;
    }

    return (char*)(descriptor->signature);
}

static SEL BRSAliasForSelector(SEL selector) {
    NSCParameterAssert(selector);
    return NSSelectorFromString([@"BRSIntercepter" stringByAppendingFormat:@"_%@", NSStringFromSelector(selector)]);
}

static BRSIntercepterInfo *BRSGetContainerForClass(Class klass, SEL selector) {
    NSCParameterAssert(klass);
    SEL aliasSelector = BRSAliasForSelector(selector);
    BRSIntercepterInfo* info = objc_getAssociatedObject(klass,aliasSelector);
    if (!info) {
        info = [BRSIntercepterInfo new];
        objc_setAssociatedObject(klass, aliasSelector, info, OBJC_ASSOCIATION_RETAIN);
    }
    return info;
}

static NSString *const BRSForwardInvocationSelectorName = @"__BRS_forwardInvocation:";

// This is the swizzled forwardInvocation: method.
static void __BRS_ARE_BEING_CALLED__(__unsafe_unretained NSObject *self, SEL selector, NSInvocation *invocation) {
    NSCParameterAssert(self);
    NSCParameterAssert(invocation);
    SEL originalSelector = invocation.selector;
    SEL aliasSelector = BRSAliasForSelector(invocation.selector);
    invocation.selector = aliasSelector;
    BRSIntercepterInfo *info = BRSGetContainerForClass(object_getClass(self), aliasSelector);
    if( info.block && invocation.methodSignature.numberOfArguments > 2 )
    {
        for( int i = 2; i < invocation.methodSignature.numberOfArguments; ++i )
        {
            const char* typeencoding = [invocation.methodSignature getArgumentTypeAtIndex:i];
            if( strcmp(typeencoding, "@?") == 0 )
            {
                __unsafe_unretained id block = nil;
                [invocation getArgument:&block atIndex:(NSInteger)i];
                
                const char* signature = BlockSig(info.block);
                NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:[NSMethodSignature signatureWithObjCTypes:signature]];
                [invocation setArgument:&block atIndex:1];
                [invocation invokeWithTarget:info.block];
            }
        }
    }
    
    BOOL respondsToAlias = YES;
    {
        Class klass = object_getClass(invocation.target);
        do {
            if ((respondsToAlias = [klass instancesRespondToSelector:aliasSelector])) {
                [invocation invoke];
                break;
            }
        }while (!respondsToAlias && (klass = class_getSuperclass(klass)));
    }
    
    // If no hooks are installed, call original implementation (usually to throw an exception)
    if (!respondsToAlias) {
        invocation.selector = originalSelector;
        SEL originalForwardInvocationSEL = NSSelectorFromString(BRSForwardInvocationSelectorName);
        if ([self respondsToSelector:originalForwardInvocationSEL]) {
            ((void( *)(id, SEL, NSInvocation *))objc_msgSend)(self, originalForwardInvocationSEL, invocation);
        }else {
            [self doesNotRecognizeSelector:invocation.selector];
        }
    }
}

static void BRSSwizzleForwardInvocation(Class klass) {
    NSCParameterAssert(klass);
    // If there is no method, replace will act like class_addMethod.
    IMP originalImplementation = class_replaceMethod(klass, @selector(forwardInvocation:), (IMP)__BRS_ARE_BEING_CALLED__, "v@:@");
    if (originalImplementation) {
        class_addMethod(klass, NSSelectorFromString(BRSForwardInvocationSelectorName), originalImplementation, "v@:@");
    }
}

static IMP BRSGetMsgForwardIMP(NSObject *self, SEL selector) {
    IMP msgForwardIMP = _objc_msgForward;
#if !defined(__arm64__)
    // As an ugly internal runtime implementation detail in the 32bit runtime, we need to determine of the method we hook returns a struct or anything larger than id.
    // https://developer.apple.com/library/mac/documentation/DeveloperTools/Conceptual/LowLevelABI/000-Introduction/introduction.html
    // https://github.com/ReactiveCocoa/ReactiveCocoa/issues/783
    // http://infocenter.arm.com/help/topic/com.arm.doc.ihi0042e/IHI0042E_aapcs.pdf (Section 5.4)
    Method method = class_getInstanceMethod(self.class, selector);
    const char *encoding = method_getTypeEncoding(method);
    BOOL methodReturnsStructValue = encoding[0] == _C_STRUCT_B;
    if (methodReturnsStructValue) {
        @try {
            NSUInteger valueSize = 0;
            NSGetSizeAndAlignment(encoding, &valueSize, NULL);
            
            if (valueSize == 1 || valueSize == 2 || valueSize == 4 || valueSize == 8) {
                methodReturnsStructValue = NO;
            }
        } @catch (NSException *e) {}
    }
    if (methodReturnsStructValue) {
        msgForwardIMP = (IMP)_objc_msgForward_stret;
    }
#endif
    return msgForwardIMP;
}

static BOOL BRSIsMsgForwardIMP(IMP impl) {
    return impl == _objc_msgForward
#if !defined(__arm64__)
    || impl == (IMP)_objc_msgForward_stret
#endif
    ;
}

static void BRSHookSelector(Class self, SEL selector, NSError **error) {
    NSCParameterAssert(selector);
    BRSSwizzleForwardInvocation(self);
    Class klass = self;
    Method targetMethod = class_getInstanceMethod(klass, selector);
    if( !BRSIsMsgForwardIMP(method_getImplementation(targetMethod)) )
    {
        // Make a method alias for the existing method implementation, it not already copied.
        const char *typeEncoding = method_getTypeEncoding(targetMethod);
        SEL aliasSelector = BRSAliasForSelector(selector);
        //        if (![klass instancesRespondToSelector:aliasSelector] )
        {
            __unused BOOL addedAlias = class_addMethod(klass, aliasSelector, method_getImplementation(targetMethod), typeEncoding);
            NSCAssert(addedAlias, @"Original implementation for %@ is already copied to %@ on %@", NSStringFromSelector(selector), NSStringFromSelector(aliasSelector), klass);
        }
        
        // We use forwardInvocation to hook in.
        class_replaceMethod(klass, selector, BRSGetMsgForwardIMP((id)self, selector), typeEncoding);
    }
}

@implementation NSObject(BRSIntercepter)

+ (void)hookSelector_BRSIntercepter:(SEL)selector withBlock:(id)block error:(NSError**)error;
{
    NSCParameterAssert(self);
    NSCParameterAssert(selector);
    NSCParameterAssert(block);
    
    static NSSet *disallowedSelectorList;
    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        disallowedSelectorList = [NSSet setWithObjects:@"webView:decidePolicyForNavigationAction:decisionHandler:",@"dealloc:", nil];
    });
    
    NSString* selectorName = NSStringFromSelector(selector);
    CHECK(![disallowedSelectorList containsObject:selectorName]);
    
    SEL aliasSelector = BRSAliasForSelector(selector);
    BRSIntercepterInfo* info = BRSGetContainerForClass(self,aliasSelector);
    if( info )
    {
        info.block = block;
    }
    BRSHookSelector(self,selector,error);
}

@end

@implementation BRSIntercepterInfo

@end

#endif
