## blockRetainSelf 是一套 iOS 检测block强引用self检测方案:
* 支持运行期检测准确度极高的block强引用self检测
* 开启后对app运行并无大的影响，方便在测试功能的同时检测期间代码中block强引用self内存泄漏情况

## Usage
~~~~

    [[BlockRetainSelf sharedChecker] addPrefix:@"XY"];
    [[BlockRetainSelf sharedChecker] handleBlockchecking];
~~~~
