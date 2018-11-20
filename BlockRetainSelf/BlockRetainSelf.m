//
//  BlockRetainSelf.m
//  blockRetainSelf
//
//  Created by 方阳 on 2018/7/30.
//  Copyright © 2018年 yy. All rights reserved.
//
#ifdef DEBUG
#import "BlockRetainSelf.h"
#import "BRStrongReferenceDetector.h"
#import "BRSIntercepter.h"
#import "BRSBase.h"
#import <objc/runtime.h>
#import "BRSStackChecker.h"

#define weakifySelf  __weak __typeof(&*self)weakSelf = self;
#define strongifySelf __strong __typeof(&*weakSelf)self = weakSelf;

static NSIndexSet *_GetBlockStrongLayout(void *block)
{
    struct BRSBlock_literal* blockLiteral = block;
    
    /**
     BLOCK_HAS_CTOR - Block has a C++ constructor/destructor, which gives us a good chance it retains
     objects that are not pointer aligned, so omit them.
     !BLOCK_HAS_COPY_DISPOSE - Block doesn't have a dispose function, so it does not retain objects and
     we are not able to blackbox it.
     */
    if ((blockLiteral->flags & BLOCK_HAS_CTOR)
        || !(blockLiteral->flags & BLOCK_HAS_COPY_DISPOSE)) {
        return nil;
    }
    
    void (*dispose_helper)(void *src) = blockLiteral->descriptor->dispose_helper;
    const size_t ptrSize = sizeof(void *);
    
    // Figure out the number of pointers it takes to fill out the object, rounding up.
    const size_t elements = (blockLiteral->descriptor->size + ptrSize - 1) / ptrSize;
    
    // Create a fake object of the appropriate length.
    void *obj[elements];
    void *detectors[elements];
    
    for (size_t i = 0; i < elements; ++i) {
        BRSStrongReferenceDetector *detector = [BRSStrongReferenceDetector new];
        obj[i] = detectors[i] = detector;
    }
    
    @autoreleasepool {
        dispose_helper(obj);
    }
    
    // Run through the release detectors and add each one that got released to the object's
    // strong ivar layout.
    NSMutableIndexSet *layout = [NSMutableIndexSet indexSet];
    
    for (size_t i = 0; i < elements; ++i) {
        BRSStrongReferenceDetector *detector = (BRSStrongReferenceDetector *)(detectors[i]);
        if (detector.isStrong) {
            [layout addIndex:i];
        }
        
        // Destroy detectors
        [detector trueRelease];
    }
    return layout;
}

@interface BlockRetainSelf()

@property (nonatomic,strong) NSMutableSet* prefixes;
@property (nonatomic,strong) NSMutableSet* excludedprefixes;
@property (nonatomic,strong) NSMutableSet* classnames;

@end

@implementation BlockRetainSelf

+ (instancetype)sharedChecker;
{
    static BlockRetainSelf* checker = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        checker = [BlockRetainSelf new];
    });
    return checker;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _prefixes = [NSMutableSet new];
        _excludedprefixes = [NSMutableSet new];
        _classnames = [NSMutableSet new];
    }
    return self;
}

- (NSArray*)blockRetains:(id)block;
{
    NSMutableArray *results = [NSMutableArray new];
    
    void **blockReference = (void**)block;
    NSIndexSet *strongLayout = _GetBlockStrongLayout(block);
    [strongLayout enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        void **reference = &blockReference[idx];
        
        if (reference && (*reference)) {
            id object = (id)(*reference);
            
            if (object) {
                [results addObject:object];
            }
        }
    }];
    if( 0 == results.count )
    {
        return nil;
    }
    return results;
}

- (NSArray*)containConcernedClass:(NSArray*)arr;
{
    if( !arr.count )
    {
        return nil;
    }
    NSMutableArray* ret = [NSMutableArray new];
    for( id obj in arr )
    {
        NSString* pre = NSStringFromClass([obj class]);
        for( NSString* prefix in self.prefixes )
        {
            if( [pre hasPrefix:prefix] )
            {
                [ret addObject:obj];
            }
        }
    }
    if( 0 == ret.count )
    {
        return nil;
    }
    return ret;
}

- (void)addPrefix:(NSString*)prefix;
{
    [_prefixes addObject:prefix];
}

- (void)excludePrefix:(NSString*)prefix;
{
    [_excludedprefixes addObject:prefix];
}

- (void)addClassname:(NSString*)clsname;
{
    [_classnames addObject:clsname];
}

- (BOOL)isBlock:(id)block retainObserver:(id)observer
{
    NSArray *results = [self blockRetains:block];
    CHECKANDRET([results containsObject:observer], NO);
    return YES;
}

- (void)handleBlockchecking;
{
    unsigned int clscount = 0;
    Class* classes = objc_copyClassList(&clscount);
    for ( int j = 0; j < clscount; ++j )
    {
        Class cls = classes[j];
        CHECKANDCONTINUE(cls);
        
        const char* clsname = class_getName(cls);
        NSString* classname = [NSString stringWithUTF8String:clsname];
        
        BOOL hit = NO;
        if( [self.classnames containsObject:classname] )
        {
            hit = YES;
        }
        else
        {
            for( NSString* prefix in self.prefixes )
            {
                if( [classname hasPrefix:prefix] )
                {
                    hit = YES;
                }
            }
        }
        CHECKANDCONTINUE(hit);
        
        [self handleBlockCheckingForCls:cls];
    }
    if( classes )
    {
        free(classes);
    }
}

- (void)handleBlockCheckingForCls:(Class)cls;
{
    unsigned int mcount = 0;
    Method* methodlist = class_copyMethodList(cls, &mcount);
    for( int i = 0; i < mcount; ++i )
    {
        const char* methodencoding = method_getTypeEncoding(methodlist[i]);
        CHECKANDCONTINUE([[NSString stringWithUTF8String:methodencoding] containsString:@"@?"]);
        SEL selector = method_getName(methodlist[i]);
        NSMethodSignature* signature = [NSMethodSignature signatureWithObjCTypes:methodencoding];
        //            const char* rettype = signature.methodReturnType;
        for( int i = 2; i < signature.numberOfArguments ;++i )
        {
            const char* type = [signature getArgumentTypeAtIndex:i];
            CHECKANDCONTINUE(strcmp(type,"@?") == 0);
            
            weakifySelf
            NSError* error = nil;
            [cls hookSelector_BRSIntercepter:selector withBlock:[^(id block){
                strongifySelf
                NSString* clsname = [[BRSStackChecker sharedChecker] getClassNameAtFrame:10];
                CHECK(block);
                NSArray* origretains = [self blockRetains:block];
                CHECK(origretains.count);
                NSArray* retains = [self containConcernedClass:origretains];
                [origretains release];
                CHECK(retains.count);
                for( id obj in retains)
                {
                    if( [obj class] == NSClassFromString(clsname) )
                    {
                        [[NSException exceptionWithName:@"block retain self" reason:nil userInfo:nil] raise];
                    }
                }
//                NSArray<NSString*>* stack = [NSThread callStackSymbols];
//                NSString* stackline = stack[7];
//                NSRange range = [stackline rangeOfString:@"-["];
//                if( range.location != NSNotFound )
//                {
//                    NSRange whiterange = [stackline rangeOfString:@" " options:NSCaseInsensitiveSearch range:NSMakeRange(range.location, stackline.length-range.location)];
//                    NSString* clsname = [stackline substringWithRange:NSMakeRange(range.location+2, whiterange.location-range.location-2)];
//
//                }
                [retains release];
            } copy] error:&error];
        }
    }
    if( methodlist )
    {
        free(methodlist);
    }
}

@end

#endif
