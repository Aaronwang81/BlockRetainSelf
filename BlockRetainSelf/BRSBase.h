//
//  BRSBase.h
//  blockRetainSelf
//
//  Created by 方阳 on 2018/7/31.
//  Copyright © 2018年 yy. All rights reserved.
//

#ifndef BRSBase_h
#define BRSBase_h

#define CHECK(condition)                        do{                                             \
if(!(condition))                          \
{                                         \
return ;                                \
}                                         \
}while(0)

#define CHECKANDRET(condition,ret)             do{                                             \
if(!(condition))                          \
{                                         \
return ret;                              \
}                                         \
}while(0)

#define CHECKANDCONTINUE(condition)             if(!(condition))   continue

#endif /* BRSBase_h */
