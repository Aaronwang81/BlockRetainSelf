//
//  BRSStackChecker.m
//  blockRetainSelf
//
//  Created by 方阳 on 2018/11/20.
//  Copyright © 2018年 yy. All rights reserved.
//

#import "BRSStackChecker.h"
#import "BRSBase.h"
#import <mach/mach.h>
#import <pthread.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>

#pragma -mark DEFINE MACRO FOR DIFFERENT CPU ARCHITECTURE
#if defined(__arm64__)
#define DETAG_INSTRUCTION_ADDRESS(A) ((A) & ~(3UL))
#define BRS_THREAD_STATE_COUNT  ARM_THREAD_STATE64_COUNT
#define BRS_THREAD_STATE        ARM_THREAD_STATE64
#define BRS_FRAME_POINTER       __fp
#define BRS_STACK_POINTER       __sp
#define BRS_INSTRUCTION_ADDRESS __pc

#elif defined(__arm__)
#define DETAG_INSTRUCTION_ADDRESS(A) ((A) & ~(1UL))
#define BRS_THREAD_STATE_COUNT  ARM_THREAD_STATE_COUNT
#define BRS_THREAD_STATE        ARM_THREAD_STATE
#define BRS_FRAME_POINTER       __r[7]
#define BRS_STACK_POINTER       __sp
#define BRS_INSTRUCTION_ADDRESS __pc

#elif defined(__x86_64__)
#define DETAG_INSTRUCTION_ADDRESS(A) (A)
#define BRS_THREAD_STATE_COUNT  x86_THREAD_STATE64_COUNT
#define BRS_THREAD_STATE        x86_THREAD_STATE64
#define BRS_FRAME_POINTER       __rbp
#define BRS_STACK_POINTER       __rsp
#define BRS_INSTRUCTION_ADDRESS __rip

#elif defined(__i386__)
#define DETAG_INSTRUCTION_ADDRESS(A) (A)
#define BRS_THREAD_STATE_COUNT  x86_THREAD_STATE32_COUNT
#define BRS_THREAD_STATE        x86_THREAD_STATE32
#define BRS_FRAME_POINTER       __ebp
#define BRS_STACK_POINTER       __esp
#define BRS_INSTRUCTION_ADDRESS __eip

#endif

typedef struct BRSStackFrameEntry{
    const struct BRSStackFrameEntry *const previous;
    const uintptr_t return_address;
} BRSStackFrameEntry;

kern_return_t brs_mach_copyFramePointer(const void *const src, void *const dst, const size_t numBytes){
    vm_size_t bytesCopied = 0;
    return vm_read_overwrite(mach_task_self(), (vm_address_t)src, (vm_size_t)numBytes, (vm_address_t)dst, &bytesCopied);
}

uintptr_t brs_firstCmdAfterHeader(const struct mach_header* const header) {
    switch(header->magic) {
        case MH_MAGIC:
        case MH_CIGAM:
            return (uintptr_t)(header + 1);
        case MH_MAGIC_64:
        case MH_CIGAM_64:
            return (uintptr_t)(((struct mach_header_64*)header) + 1);
        default:
            return 0;  // Header is corrupt
    }
}

static thread_t brsmainthread = 0;

@implementation BRSStackChecker

+ (void)load
{
    brsmainthread = mach_task_self();
}

+ (instancetype)sharedChecker;
{
    static BRSStackChecker* checker = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        checker = [BRSStackChecker new];
    });
    return checker;
}

- (NSString*)getClassNameAtFrame:(NSInteger)index;
{
    thread_t curthread = mach_thread_self();// 或者 [self machthreadOf:[NSThread currentThread]]
    uintptr_t bt[index+2];
    int i = 0;
    _STRUCT_MCONTEXT context;
    mach_msg_type_number_t statecount = BRS_THREAD_STATE_COUNT;
    kern_return_t ret = thread_get_state(curthread, BRS_THREAD_STATE, (thread_state_t)&context.__ss, &statecount);
    CHECKANDRET(ret == KERN_SUCCESS, nil);
    bt[i++] = context.__ss.BRS_INSTRUCTION_ADDRESS;
    uintptr_t lr = [self linkRegister:&context];
    if( lr )
    {
        bt[i++] = lr;
    }
    CHECKANDRET(bt[0], nil);
    BRSStackFrameEntry entry = {0};
    uint64_t fp = context.__ss.BRS_FRAME_POINTER;
    for( --i; i < index+1 ; ++i )
    {
        brs_mach_copyFramePointer((void*)fp, &entry, sizeof(entry));
        bt[i+1] = entry.return_address;
        fp = (uint64_t)entry.previous;
    }
    Dl_info dlinfo;
    dlinfo.dli_sname = NULL;
//    NSString* stack = @"";
//    for( int i = 0; i< index +2 ; ++i )
//    {
//        dladdr((void*)bt[i], &dlinfo);
//        stack = [NSString stringWithFormat:@"%@%s    %s\n",stack,dlinfo.dli_fname,dlinfo.dli_sname];
//    }
//    uint32_t imgindex = UINT_MAX;
    dladdr((void*)bt[index+1], &dlinfo);
    CHECKANDRET(dlinfo.dli_sname, nil);
    NSString* stackline = [NSString stringWithUTF8String:dlinfo.dli_sname];
    NSRange range = [stackline rangeOfString:@"-["];
    if( stackline && range.location != NSNotFound )
    {
        NSRange whiterange = [stackline rangeOfString:@" " options:NSCaseInsensitiveSearch range:NSMakeRange(range.location, stackline.length-range.location)];
        NSString* clsname = [stackline substringWithRange:NSMakeRange(range.location+2, whiterange.location-range.location-2)];
        range = [clsname rangeOfString:@"("];
        if( range.location != NSNotFound )
        {
            clsname = [clsname substringToIndex:range.location];
        }
        return clsname;
    }
//    //get image index
//    const uint32_t imgCount = _dyld_image_count();
//    const struct mach_header* header = NULL;
//    for ( uint32_t i = 0; i < imgCount ; i++ )
//    {
//        header = _dyld_get_image_header(i);
//        CHECKANDCONTINUE(header);
//        uintptr_t slide = bt[7]-(uintptr_t)_dyld_get_image_vmaddr_slide(i);
//        uintptr_t cmdptr = brs_firstCmdAfterHeader(header);
//        CHECKANDCONTINUE(cmdptr);
//        for ( uint32_t cmd = 0; cmd < header->ncmds; ++cmd )
//        {
//            const struct load_command* loadcmd = (struct load_command*)cmdptr;
//            uint64_t vmaddr = 0,vmsize = 0;
//            if( loadcmd->cmd == LC_SEGMENT )
//            {
//                const struct segment_command* segcmd = (struct segment_command*)cmdptr;
//                vmaddr = segcmd->vmaddr;
//                vmsize = segcmd->vmsize;
//            }
//            else if( loadcmd->cmd == LC_SEGMENT_64 ){
//                const struct segment_command_64* segcmd = (struct segment_command_64*)cmdptr;
//                vmaddr = segcmd->vmaddr;
//                vmsize = segcmd->vmsize;
//            }
//            if( slide < vmaddr+vmsize && slide >= vmaddr )
//            {
//                imgindex = cmd;
//                break;
//            }
//            cmdptr += loadcmd->cmdsize;
//        }
//    }
//    //image index
//    CHECKANDRET(imgindex!=UINT_MAX, nil);
    
    
    return nil;
}

- (uintptr_t)linkRegister:(mcontext_t const) machineContext{
#if defined(__i386__) || defined(__x86_64__)
    return 0;
#else
    return machineContext->__ss.__lr;
#endif
}

- (thread_t)machthreadOf:(NSThread*)thread;
{
    CHECKANDRET(thread, 0);
    if( thread.isMainThread )
    {
        return brsmainthread;
    }
    char name[1024];
    mach_msg_type_number_t count;
    thread_act_array_t list;
    task_threads(mach_task_self(), &list, &count);
    CFAbsoluteTime ts = CFAbsoluteTimeGetCurrent();
    NSString* origTName = thread.name;
    NSString* tmpName = @(ts).stringValue;
    thread.name = tmpName;
    thread_t dstThread = mach_thread_self();
    for ( unsigned int i = 0; i < count ; ++i ) {
        pthread_t pthread = pthread_from_mach_thread_np(list[i]);
        CHECKANDCONTINUE(pthread);
        pthread_getname_np(pthread, name, sizeof(name));
        CHECKANDCONTINUE(!strcmp(name, tmpName.UTF8String));
        dstThread = list[i];
        break;
    }
    thread.name = origTName;
    return dstThread;
}
@end
