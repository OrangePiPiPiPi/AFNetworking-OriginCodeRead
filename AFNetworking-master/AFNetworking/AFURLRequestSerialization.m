// AFURLRequestSerialization.m
// Copyright (c) 2011–2016 Alamofire Software Foundation ( http://alamofire.org/ )
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "AFURLRequestSerialization.h"

#if TARGET_OS_IOS || TARGET_OS_WATCH || TARGET_OS_TV
#import <MobileCoreServices/MobileCoreServices.h>
#else
#import <CoreServices/CoreServices.h>
#endif

NSString * const AFURLRequestSerializationErrorDomain = @"com.alamofire.error.serialization.request";
NSString * const AFNetworkingOperationFailingURLRequestErrorKey = @"com.alamofire.serialization.request.error.response";

typedef NSString * (^AFQueryStringSerializationBlock)(NSURLRequest *request, id parameters, NSError *__autoreleasing *error);

/**
 
 为查询字符串键或值返回RFC 3986之后的百分比转义字符串。
 RFC 3986规定以下字符为“保留”字符。
 -常规分隔符：“：”、“#”、“[”、“]”、“@”、“？”, "/"
 -子分隔符：“！”, "$", "&", "'", "(", ")", "*", "+", ",", ";", "="
 
 在RFC 3986第3.4节中，规定“？”和“/”字符不应转义以允许
 包含URL的查询字符串。因此，所有“保留”字符，除了“？”和“/”
 应在查询字符串中转义百分比。
 -参数字符串：要转义百分比的字符串。
 -返回：转义字符串的百分比。
 Returns a percent-escaped string following RFC 3986 for a query string key or value.

 RFC 3986 states that the following characters are "reserved" characters.

    - General Delimiters: ":", "#", "[", "]", "@", "?", "/"
    - Sub-Delimiters: "!", "$", "&", "'", "(", ")", "*", "+", ",", ";", "="

 In RFC 3986 - Section 3.4, it states that the "?" and "/" characters should not be escaped to allow
 query strings to include a URL. Therefore, all "reserved" characters with the exception of "?" and "/"
 should be percent-escaped in the query string.
    - parameter string: The string to be percent-escaped.
    - returns: The percent-escaped string.
 
 https://blog.csdn.net/qq_32010299/article/details/51790407
 
 AFURLRequestSerialization主要实现了根据不同情况和参数初始化NSURLRequest对象的功能。只有AFHTTPSessionManager有requestSerialization，默认是AFHTTPRequestSerializer对象。
 对url进行utf-8编码
 */
/**
 ios7以后，stringByAddingPercentEncodingWithAllowedCharacters:方法，这个方法会对字符串进行更彻底的转义，但需要传递一个参数：一个字符集，处于这个字符集中的字符不会被转义。
 **/
//AFPercentEscapedStringFromString方法主要是对传入的字符串string进行转义
NSString * AFPercentEscapedStringFromString(NSString *string) {
    static NSString * const kAFCharactersGeneralDelimitersToEncode = @":#[]@"; // does not include "?" or "/" due to RFC 3986 - Section 3.4
    
    static NSString * const kAFCharactersSubDelimitersToEncode = @"!$&'()*+,;=";
    
    //allowedCharacterSet是url允许的所有字符集
    NSMutableCharacterSet * allowedCharacterSet = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    //removeCharactersInString去掉某些字符，从url允许的所有字符集中去掉所有“保留”字符（kAFCharactersGeneralDelimitersToEncode和kAFCharactersSubDelimitersToEncode）
    [allowedCharacterSet removeCharactersInString:[kAFCharactersGeneralDelimitersToEncode stringByAppendingString:kAFCharactersSubDelimitersToEncode]];

	// FIXME: https://github.com/AFNetworking/AFNetworking/pull/3028
    // return [string stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacterSet];
    /**
     注释:直接使用[string stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacterSet]在iOS7上可能
     存在crash
     **/
    

    static NSUInteger const batchSize = 50;

    NSUInteger index = 0;
    NSMutableString *escaped = @"".mutableCopy;

    while (index < string.length) {
        NSUInteger length = MIN(string.length - index, batchSize);
        NSRange range = NSMakeRange(index, length);

        // To avoid breaking up character sequences such as 👴🏻👮🏽
        range = [string rangeOfComposedCharacterSequencesForRange:range];

        NSString *substring = [string substringWithRange:range];
        NSString *encoded = [substring stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacterSet];
        [escaped appendString:encoded];

        index += range.length;
    }

	return escaped;
}

#pragma mark -

@interface AFQueryStringPair : NSObject
@property (readwrite, nonatomic, strong) id field;
@property (readwrite, nonatomic, strong) id value;

- (instancetype)initWithField:(id)field value:(id)value;

- (NSString *)URLEncodedStringValue;
@end

@implementation AFQueryStringPair

- (instancetype)initWithField:(id)field value:(id)value {
    self = [super init];
    if (!self) {
        return nil;
    }

    self.field = field;
    self.value = value;

    return self;
}

//AFN 的并不会直接将url进行转义，而是将parameters参数中的各个组件分别进行组装，然后再进行拼接。
- (NSString *)URLEncodedStringValue {
    if (!self.value || [self.value isEqual:[NSNull null]]) {
        return AFPercentEscapedStringFromString([self.field description]);
    } else {
        return [NSString stringWithFormat:@"%@=%@", AFPercentEscapedStringFromString([self.field description]), AFPercentEscapedStringFromString([self.value description])];
    }
}

@end

#pragma mark -

FOUNDATION_EXPORT NSArray * AFQueryStringPairsFromDictionary(NSDictionary *dictionary);
FOUNDATION_EXPORT NSArray * AFQueryStringPairsFromKeyAndValue(NSString *key, id value);

NSString * AFQueryStringFromParameters(NSDictionary *parameters) {
    NSMutableArray *mutablePairs = [NSMutableArray array];
    for (AFQueryStringPair *pair in AFQueryStringPairsFromDictionary(parameters)) {
        [mutablePairs addObject:[pair URLEncodedStringValue]];
    }

    return [mutablePairs componentsJoinedByString:@"&"];
}

NSArray * AFQueryStringPairsFromDictionary(NSDictionary *dictionary) {
    return AFQueryStringPairsFromKeyAndValue(nil, dictionary);
}

//返回了一个包含AFQueryStringPair实例的数组
NSArray * AFQueryStringPairsFromKeyAndValue(NSString *key, id value) {
    NSMutableArray *mutableQueryStringComponents = [NSMutableArray array];

    /**
     参数:
     key : 排序key, 某个对象的属性名称
     ascending : 是否升序, YES-升序, NO-降序
     selector : 自定义排序规则, 如果需要自己定义排序规则, 可传递此方法, 这个使用相对比较复杂; 如果待比较的属性是字符串(NSString)类型, 可使用其默认的方法: localizedStandardCompare:
     
     作者：流火绯瞳
     链接：https://www.jianshu.com/p/3e9f0884be6b
     来源：简书
     著作权归作者所有。商业转载请联系作者获得授权，非商业转载请注明出处。
     **/
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"description" ascending:YES selector:@selector(compare:)];

    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = value;
        // Sort dictionary keys to ensure consistent ordering in query string, which is important when deserializing potentially ambiguous sequences, such as an array of dictionaries
        for (id nestedKey in [dictionary.allKeys sortedArrayUsingDescriptors:@[ sortDescriptor ]]) {
            id nestedValue = dictionary[nestedKey];
            if (nestedValue) {
                [mutableQueryStringComponents addObjectsFromArray:AFQueryStringPairsFromKeyAndValue((key ? [NSString stringWithFormat:@"%@[%@]", key, nestedKey] : nestedKey), nestedValue)];
            }
        }
    } else if ([value isKindOfClass:[NSArray class]]) {
        NSArray *array = value;
        for (id nestedValue in array) {
            [mutableQueryStringComponents addObjectsFromArray:AFQueryStringPairsFromKeyAndValue([NSString stringWithFormat:@"%@[]", key], nestedValue)];
        }
    } else if ([value isKindOfClass:[NSSet class]]) {
        NSSet *set = value;
        for (id obj in [set sortedArrayUsingDescriptors:@[ sortDescriptor ]]) {
            [mutableQueryStringComponents addObjectsFromArray:AFQueryStringPairsFromKeyAndValue(key, obj)];
        }
    } else {
        [mutableQueryStringComponents addObject:[[AFQueryStringPair alloc] initWithField:key value:value]];
    }

    return mutableQueryStringComponents;
}

#pragma mark -

//AFStreamingMultipartFormData遵循了AFMultipartFormData协议
@interface AFStreamingMultipartFormData : NSObject <AFMultipartFormData>
- (instancetype)initWithURLRequest:(NSMutableURLRequest *)urlRequest
                    stringEncoding:(NSStringEncoding)encoding;

- (NSMutableURLRequest *)requestByFinalizingMultipartFormData;
@end

#pragma mark -

//AFHTTPRequestSerializerObservedKeyPaths是一个数组，里面存放的是需要进行KVO观察的属性
static NSArray * AFHTTPRequestSerializerObservedKeyPaths() {
    static NSArray *_AFHTTPRequestSerializerObservedKeyPaths = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _AFHTTPRequestSerializerObservedKeyPaths = @[NSStringFromSelector(@selector(allowsCellularAccess)), NSStringFromSelector(@selector(cachePolicy)), NSStringFromSelector(@selector(HTTPShouldHandleCookies)), NSStringFromSelector(@selector(HTTPShouldUsePipelining)), NSStringFromSelector(@selector(networkServiceType)), NSStringFromSelector(@selector(timeoutInterval))];
    });

    return _AFHTTPRequestSerializerObservedKeyPaths;
}

//用于KVO的Context
static void *AFHTTPRequestSerializerObserverContext = &AFHTTPRequestSerializerObserverContext;

@interface AFHTTPRequestSerializer ()
//mutableObservedChangedKeyPaths:保存所有通过KVO观察到的属性，会设置给NSMutableURLRequest
@property (readwrite, nonatomic, strong) NSMutableSet *mutableObservedChangedKeyPaths;
//从外面传入的请求头数据会添加到mutableHTTPRequestHeaders字典里
@property (readwrite, nonatomic, strong) NSMutableDictionary *mutableHTTPRequestHeaders;
//并发队列
@property (readwrite, nonatomic, strong) dispatch_queue_t requestHeaderModificationQueue;
@property (readwrite, nonatomic, assign) AFHTTPRequestQueryStringSerializationStyle queryStringSerializationStyle;
//queryStringSerialization是一个block,该属性用于接收从外面传入可用户自定义传参的block
@property (readwrite, nonatomic, copy) AFQueryStringSerializationBlock queryStringSerialization;
@end

@implementation AFHTTPRequestSerializer

+ (instancetype)serializer {
    return [[self alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    //默认utf-8编码
    self.stringEncoding = NSUTF8StringEncoding;

    self.mutableHTTPRequestHeaders = [NSMutableDictionary dictionary];
    //创建一个并发队列
    self.requestHeaderModificationQueue = dispatch_queue_create("requestHeaderModificationQueue", DISPATCH_QUEUE_CONCURRENT);

    // Accept-Language HTTP Header; see http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.4
    //设置语言
    NSMutableArray *acceptLanguagesComponents = [NSMutableArray array];
    [[NSLocale preferredLanguages] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        float q = 1.0f - (idx * 0.1f);
        //根据系统的语言设置http请求头字段Accept-Language 的值，eg(zh-CN;q=0.8) 后面的q表示前面语言的权值，如果是多种语言，服务器可以根据圈值的大小优先响应哪种请求
        [acceptLanguagesComponents addObject:[NSString stringWithFormat:@"%@;q=%0.1g", obj, q]];
        *stop = q <= 0.5f;
    }];
    [self setValue:[acceptLanguagesComponents componentsJoinedByString:@", "] forHTTPHeaderField:@"Accept-Language"];

    /**
     User-Agent 首部包含了一个特征字符串，用来让网络协议的对端来识别发起请求的用户代理软件的应用类型、操作系统、软件开发商以及版本号
     User-Agent Header; see http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.43
     **/
    NSString *userAgent = nil;
#if TARGET_OS_IOS
    userAgent = [NSString stringWithFormat:@"%@/%@ (%@; iOS %@; Scale/%0.2f)", [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleExecutableKey] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleIdentifierKey], [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleVersionKey], [[UIDevice currentDevice] model], [[UIDevice currentDevice] systemVersion], [[UIScreen mainScreen] scale]];
#elif TARGET_OS_TV
    userAgent = [NSString stringWithFormat:@"%@/%@ (%@; tvOS %@; Scale/%0.2f)", [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleExecutableKey] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleIdentifierKey], [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleVersionKey], [[UIDevice currentDevice] model], [[UIDevice currentDevice] systemVersion], [[UIScreen mainScreen] scale]];
#elif TARGET_OS_WATCH
    userAgent = [NSString stringWithFormat:@"%@/%@ (%@; watchOS %@; Scale/%0.2f)", [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleExecutableKey] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleIdentifierKey], [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleVersionKey], [[WKInterfaceDevice currentDevice] model], [[WKInterfaceDevice currentDevice] systemVersion], [[WKInterfaceDevice currentDevice] screenScale]];
#elif defined(__MAC_OS_X_VERSION_MIN_REQUIRED)
    userAgent = [NSString stringWithFormat:@"%@/%@ (Mac OS X %@)", [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleExecutableKey] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleIdentifierKey], [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleVersionKey], [[NSProcessInfo processInfo] operatingSystemVersionString]];
#endif
    if (userAgent) {
        if (![userAgent canBeConvertedToEncoding:NSASCIIStringEncoding]) {
            NSMutableString *mutableUserAgent = [userAgent mutableCopy];
            if (CFStringTransform((__bridge CFMutableStringRef)(mutableUserAgent), NULL, (__bridge CFStringRef)@"Any-Latin; Latin-ASCII; [:^ASCII:] Remove", false)) {
                userAgent = mutableUserAgent;
            }
        }
        [self setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    }

    // HTTP Method Definitions; see http://www.w3.org/Protocols/rfc2616/rfc2616-sec9.html
    //默认的GET HEAD DELETE参数会被编码
    self.HTTPMethodsEncodingParametersInURI = [NSSet setWithObjects:@"GET", @"HEAD", @"DELETE", nil];

    self.mutableObservedChangedKeyPaths = [NSMutableSet set];
    //添加观察者
    for (NSString *keyPath in AFHTTPRequestSerializerObservedKeyPaths()) {
        if ([self respondsToSelector:NSSelectorFromString(keyPath)]) {
            //添加KVO观察者
            [self addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionNew context:AFHTTPRequestSerializerObserverContext];
        }
    }

    return self;
}

 //移除所有观察者
- (void)dealloc {
    for (NSString *keyPath in AFHTTPRequestSerializerObservedKeyPaths()) {
        if ([self respondsToSelector:NSSelectorFromString(keyPath)]) {
            [self removeObserver:self forKeyPath:keyPath context:AFHTTPRequestSerializerObserverContext];
        }
    }
}

#pragma mark -

//mutableHTTPRequestHeaders在此处用于生成HTTPRequestHeaders
- (NSDictionary *)HTTPRequestHeaders {
    NSDictionary __block *value;
    dispatch_sync(self.requestHeaderModificationQueue, ^{
        value = [NSDictionary dictionaryWithDictionary:self.mutableHTTPRequestHeaders];
    });
    return value;
}

//从外面传入的请求头会添加到mutableHTTPRequestHeaders字典里
- (void)setValue:(NSString *)value
forHTTPHeaderField:(NSString *)field
{
    dispatch_barrier_async(self.requestHeaderModificationQueue, ^{
        [self.mutableHTTPRequestHeaders setValue:value forKey:field];
    });
}

//取请求头的值
- (NSString *)valueForHTTPHeaderField:(NSString *)field {
    NSString __block *value;
    dispatch_sync(self.requestHeaderModificationQueue, ^{
        value = [self.mutableHTTPRequestHeaders valueForKey:field];
    });
    return value;
}

/**
 将username和password通过base64编码设置给请求头(key是Authorization)，先赋值给mutableHTTPRequestHeaders这个字典，
 一般用户认证服务
 **/
- (void)setAuthorizationHeaderFieldWithUsername:(NSString *)username
                                       password:(NSString *)password
{
    NSData *basicAuthCredentials = [[NSString stringWithFormat:@"%@:%@", username, password] dataUsingEncoding:NSUTF8StringEncoding];
    NSString *base64AuthCredentials = [basicAuthCredentials base64EncodedStringWithOptions:(NSDataBase64EncodingOptions)0];
    [self setValue:[NSString stringWithFormat:@"Basic %@", base64AuthCredentials] forHTTPHeaderField:@"Authorization"];
}

//清除请求头中用于认证的字段
- (void)clearAuthorizationHeader {
    dispatch_barrier_async(self.requestHeaderModificationQueue, ^{
        [self.mutableHTTPRequestHeaders removeObjectForKey:@"Authorization"];
    });
}

#pragma mark -

- (void)setQueryStringSerializationWithStyle:(AFHTTPRequestQueryStringSerializationStyle)style {
    /**
     通过该方法设置AFHTTPRequestQueryStringSerializationStyle，同时需要将self.queryStringSerialization这个block
     设置为nil，因为- (NSURLRequest *)requestBySerializingRequest:(NSURLRequest *)request
     withParameters:(id)parameters
     error:(NSError *__autoreleasing *)error方法中，关于参数的处理self.queryStringSerialization和self.queryStringSerializationStyle是互斥的，有self.queryStringSerialization这个block时，参数是通过这个block传递到外面处理，返回一个字符串，没有self.queryStringSerialization这个执行默认的处理
     **/
    self.queryStringSerializationStyle = style;
    self.queryStringSerialization = nil;
}

//通过暴露给外界的- (void)setQueryStringSerializationWithBlock:(NSString *(^)(NSURLRequest *, id, NSError *__autoreleasing *))block 方法获得block，可设置更多参数
- (void)setQueryStringSerializationWithBlock:(NSString *(^)(NSURLRequest *, id, NSError *__autoreleasing *))block {
    self.queryStringSerialization = block;
}

#pragma mark -

//生成一个NSMutableURLRequest，设置属性，添加请求头，处理外界传入的参数
- (NSMutableURLRequest *)requestWithMethod:(NSString *)method
                                 URLString:(NSString *)URLString
                                parameters:(id)parameters
                                     error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(method);
    NSParameterAssert(URLString);

    NSURL *url = [NSURL URLWithString:URLString];

    NSParameterAssert(url);

    NSMutableURLRequest *mutableRequest = [[NSMutableURLRequest alloc] initWithURL:url];
    mutableRequest.HTTPMethod = method;

    for (NSString *keyPath in AFHTTPRequestSerializerObservedKeyPaths()) {
        //通过KVO观察了AFHTTPRequestSerializerObservedKeyPaths里面所有的关于NSMutableURLRequest的属性，并设置给mutableRequest
        if ([self.mutableObservedChangedKeyPaths containsObject:keyPath]) {
            [mutableRequest setValue:[self valueForKeyPath:keyPath] forKey:keyPath];
        }
    }

    //requestBySerializingRequest: withParameters: error: 方法主要添加请求头和处理外界传入的parameters
    mutableRequest = [[self requestBySerializingRequest:mutableRequest withParameters:parameters error:error] mutableCopy];

	return mutableRequest;
}

//POST上传文件生成NSMutableURLRequest的方法
- (NSMutableURLRequest *)multipartFormRequestWithMethod:(NSString *)method
                                              URLString:(NSString *)URLString
                                             parameters:(NSDictionary *)parameters
                              constructingBodyWithBlock:(void (^)(id <AFMultipartFormData> formData))block
                                                  error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(method);
    NSParameterAssert(![method isEqualToString:@"GET"] && ![method isEqualToString:@"HEAD"]);

    NSMutableURLRequest *mutableRequest = [self requestWithMethod:method URLString:URLString parameters:nil error:error];

    //AFStreamingMultipartFormData类继承自NSObject，且遵循了AFMultipartFormData协议
    __block AFStreamingMultipartFormData *formData = [[AFStreamingMultipartFormData alloc] initWithURLRequest:mutableRequest stringEncoding:NSUTF8StringEncoding];

    if (parameters) {
        //AFQueryStringPairsFromDictionary返回了一个包含AFQueryStringPair实例的数组
        for (AFQueryStringPair *pair in AFQueryStringPairsFromDictionary(parameters)) {
            NSData *data = nil;
            if ([pair.value isKindOfClass:[NSData class]]) {
                data = pair.value;
            } else if ([pair.value isEqual:[NSNull null]]) {
                data = [NSData data];
            } else {
                data = [[pair.value description] dataUsingEncoding:self.stringEncoding];
            }

            if (data) {
                [formData appendPartWithFormData:data name:[pair.field description]];
            }
        }
    }

    if (block) {
        block(formData);
    }

    return [formData requestByFinalizingMultipartFormData];
}

/**
 将原来request中的HTTPBodyStream内容异步写入到指定文件中，随后调用completionHandler处理。最后返回新的request。
 @param request multipart形式的request，其中HTTPBodyStream属性不能为nil
 @param fileURL multipart request中的HTTPBodyStream内容写入的文件位置
 @param handler 用于处理的block
 @discussion NSURLSessionTask中有一个bug，当HTTP body的内容是来自NSStream的时候，request无法发送Content-Length到服务器端，此问题在Amazon S3的Web服务中尤为显著。作为一个解决方案，该函数的request参数使用的是multipartFormRequestWithMethod:URLString:parameters:constructingBodyWithBlock:error:构建出的request，或者其他HTTPBodyStream属性不为空的request。接着将HTTPBodyStream的内容先写到指定的文件中，再返回一个原来那个request的拷贝，其中该拷贝的HTTPBodyStream属性值要置为空。至此，可以使用AFURLSessionManager -uploadTaskWithRequest:fromFile:progress:completionHandler:函数构建一个上传任务，或者将文件内容转变为NSData类型，并且指定给新request的HTTPBody属性。
 @see https://github.com/AFNetworking/AFNetworking/issues/1398
 **/
- (NSMutableURLRequest *)requestWithMultipartFormRequest:(NSURLRequest *)request
                             writingStreamContentsToFile:(NSURL *)fileURL
                                       completionHandler:(void (^)(NSError *error))handler
{
    NSParameterAssert(request.HTTPBodyStream);
    NSParameterAssert([fileURL isFileURL]);

    NSInputStream *inputStream = request.HTTPBodyStream;
    NSOutputStream *outputStream = [[NSOutputStream alloc] initWithURL:fileURL append:NO];
    __block NSError *error = nil;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];

        [inputStream open];
        [outputStream open];

        while ([inputStream hasBytesAvailable] && [outputStream hasSpaceAvailable]) {
            uint8_t buffer[1024];

            NSInteger bytesRead = [inputStream read:buffer maxLength:1024];
            if (inputStream.streamError || bytesRead < 0) {
                error = inputStream.streamError;
                break;
            }

            NSInteger bytesWritten = [outputStream write:buffer maxLength:(NSUInteger)bytesRead];
            if (outputStream.streamError || bytesWritten < 0) {
                error = outputStream.streamError;
                break;
            }

            if (bytesRead == 0 && bytesWritten == 0) {
                break;
            }
        }

        [outputStream close];
        [inputStream close];

        if (handler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                handler(error);
            });
        }
    });

    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    mutableRequest.HTTPBodyStream = nil;

    return mutableRequest;
}

#pragma mark - AFURLRequestSerialization

- (NSURLRequest *)requestBySerializingRequest:(NSURLRequest *)request
                               withParameters:(id)parameters
                                        error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(request);

    NSMutableURLRequest *mutableRequest = [request mutableCopy];

    //遍历HTTPRequestHeaders，将未设置的参数设置给请求头
    [self.HTTPRequestHeaders enumerateKeysAndObjectsUsingBlock:^(id field, id value, BOOL * __unused stop) {
        if (![request valueForHTTPHeaderField:field]) {
            [mutableRequest setValue:value forHTTPHeaderField:field];
        }
    }];

    NSString *query = nil;
    if (parameters) {
        //如果有参数
        if (self.queryStringSerialization) {
            NSError *serializationError;
            //执行queryStringSerialization这个block返回一个NSString获得query
            query = self.queryStringSerialization(request, parameters, &serializationError);

            if (serializationError) {
                if (error) {
                    *error = serializationError;
                }

                return nil;
            }
        } else {
            switch (self.queryStringSerializationStyle) {
                    //将参数进行转码，调用方法拼接参数AFQueryStringFromParameters(parameters);
                case AFHTTPRequestQueryStringDefaultStyle:
                    query = AFQueryStringFromParameters(parameters);
                    break;
            }
        }
    }

    if ([self.HTTPMethodsEncodingParametersInURI containsObject:[[request HTTPMethod] uppercaseString]]) {
        //HTTPMethodsEncodingParametersInURI里默认包含[@"GET",@"HEAD",@"DELETE"],
        //这些参数query是放在url后面的
        if (query && query.length > 0) {
            /**
             hierarchical part
             ┌───────────────────┴─────────────────────┐
             authority               path
             ┌───────────────┴───────────────┐┌───┴────┐
             abc://username:password@example.com:123/path/data?key=value&key2=value2#fragid1
             └┬┘   └───────┬───────┘ └────┬────┘ └┬┘           └─────────┬─────────┘ └──┬──┘
             scheme  user information     host     port                  query         fragment
             
             urn:example:mammal:monotreme:echidna
             └┬┘ └────────────┬───────────────┘
             scheme              path
             **/
            mutableRequest.URL = [NSURL URLWithString:[[mutableRequest.URL absoluteString] stringByAppendingFormat:mutableRequest.URL.query ? @"&%@" : @"?%@", query]];
        }
    } else {
        // #2864: an empty string is a valid x-www-form-urlencoded payload
        if (!query) {
            query = @"";
        }
        //如果请求头没有设置Content-Type,则使用默认的application/x-www-form-urlencoded
        if (![mutableRequest valueForHTTPHeaderField:@"Content-Type"]) {
            [mutableRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
        }
        //非HTTPMethodsEncodingParametersInURI里的方法将参数query放在请求体里面
        [mutableRequest setHTTPBody:[query dataUsingEncoding:self.stringEncoding]];
    }

    return mutableRequest;
}

#pragma mark - NSKeyValueObserving
/**
 KVO的基本原理大概是这样的
 
 当一个对象被观察时, 系统会新建一个子类NSNotifying_A ,在子类中重写了对象被观察属性的 set方法,  并且改变了该对象的 isa 指针的指向(指向了新建的子类) , 当属性的值发生改变了, 会调用子类的set方法, 然后发出通知
 **/

#pragma mark -

// Workarounds for crashing behavior using Key-Value Observing with XCTest
// See https://github.com/AFNetworking/AFNetworking/issues/2523
//手动发通知
- (void)setAllowsCellularAccess:(BOOL)allowsCellularAccess {
    [self willChangeValueForKey:NSStringFromSelector(@selector(allowsCellularAccess))];
    _allowsCellularAccess = allowsCellularAccess;
    [self didChangeValueForKey:NSStringFromSelector(@selector(allowsCellularAccess))];
}

- (void)setCachePolicy:(NSURLRequestCachePolicy)cachePolicy {
    [self willChangeValueForKey:NSStringFromSelector(@selector(cachePolicy))];
    _cachePolicy = cachePolicy;
    [self didChangeValueForKey:NSStringFromSelector(@selector(cachePolicy))];
}

- (void)setHTTPShouldHandleCookies:(BOOL)HTTPShouldHandleCookies {
    [self willChangeValueForKey:NSStringFromSelector(@selector(HTTPShouldHandleCookies))];
    _HTTPShouldHandleCookies = HTTPShouldHandleCookies;
    [self didChangeValueForKey:NSStringFromSelector(@selector(HTTPShouldHandleCookies))];
}

- (void)setHTTPShouldUsePipelining:(BOOL)HTTPShouldUsePipelining {
    [self willChangeValueForKey:NSStringFromSelector(@selector(HTTPShouldUsePipelining))];
    _HTTPShouldUsePipelining = HTTPShouldUsePipelining;
    [self didChangeValueForKey:NSStringFromSelector(@selector(HTTPShouldUsePipelining))];
}

- (void)setNetworkServiceType:(NSURLRequestNetworkServiceType)networkServiceType {
    [self willChangeValueForKey:NSStringFromSelector(@selector(networkServiceType))];
    _networkServiceType = networkServiceType;
    [self didChangeValueForKey:NSStringFromSelector(@selector(networkServiceType))];
}

- (void)setTimeoutInterval:(NSTimeInterval)timeoutInterval {
    [self willChangeValueForKey:NSStringFromSelector(@selector(timeoutInterval))];
    _timeoutInterval = timeoutInterval;
    [self didChangeValueForKey:NSStringFromSelector(@selector(timeoutInterval))];
}


//系统默认该对象的所有属性 都能被观察到 ,重写下面方法, 可以单独设置某个属性不能被观察,此处AFHTTPRequestSerializerObservedKeyPaths所有对象不能被观察到，需要手动触发KVO
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key {
    if ([AFHTTPRequestSerializerObservedKeyPaths() containsObject:key]) {
        return NO;
    }

    return [super automaticallyNotifiesObserversForKey:key];
}

// 所观察的对象的keyPath 发生改变的时候, 会触发，将观察的属性添加到self.mutableObservedChangedKeyPaths中
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(__unused id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    if (context == AFHTTPRequestSerializerObserverContext) {
        if ([change[NSKeyValueChangeNewKey] isEqual:[NSNull null]]) {
            [self.mutableObservedChangedKeyPaths removeObject:keyPath];
        } else {
            [self.mutableObservedChangedKeyPaths addObject:keyPath];
        }
    }
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder {
    self = [self init];
    if (!self) {
        return nil;
    }

    self.mutableHTTPRequestHeaders = [[decoder decodeObjectOfClass:[NSDictionary class] forKey:NSStringFromSelector(@selector(mutableHTTPRequestHeaders))] mutableCopy];
    self.queryStringSerializationStyle = (AFHTTPRequestQueryStringSerializationStyle)[[decoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(queryStringSerializationStyle))] unsignedIntegerValue];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    dispatch_sync(self.requestHeaderModificationQueue, ^{
        [coder encodeObject:self.mutableHTTPRequestHeaders forKey:NSStringFromSelector(@selector(mutableHTTPRequestHeaders))];
    });
    [coder encodeObject:@(self.queryStringSerializationStyle) forKey:NSStringFromSelector(@selector(queryStringSerializationStyle))];
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone {
    AFHTTPRequestSerializer *serializer = [[[self class] allocWithZone:zone] init];
    dispatch_sync(self.requestHeaderModificationQueue, ^{
        serializer.mutableHTTPRequestHeaders = [self.mutableHTTPRequestHeaders mutableCopyWithZone:zone];
    });
    serializer.queryStringSerializationStyle = self.queryStringSerializationStyle;
    serializer.queryStringSerialization = self.queryStringSerialization;

    return serializer;
}

@end

#pragma mark -

// 使用两个十六进制随机数拼接在Boundary后面来表示分隔符
static NSString * AFCreateMultipartFormBoundary() {
    return [NSString stringWithFormat:@"Boundary+%08X%08X", arc4random(), arc4random()];
}
//换行符
static NSString * const kAFMultipartFormCRLF = @"\r\n";

//如果是开头分隔符的，那么只需在分隔符结尾加一个换行符
static inline NSString * AFMultipartFormInitialBoundary(NSString *boundary) {
    return [NSString stringWithFormat:@"--%@%@", boundary, kAFMultipartFormCRLF];
}

//如果是中间部分分隔符，那么需要分隔符前面和结尾都加换行符
static inline NSString * AFMultipartFormEncapsulationBoundary(NSString *boundary) {
    return [NSString stringWithFormat:@"%@--%@%@", kAFMultipartFormCRLF, boundary, kAFMultipartFormCRLF];
}

//如果是末尾，还得使用–分隔符–作为请求体的结束标志
static inline NSString * AFMultipartFormFinalBoundary(NSString *boundary) {
    return [NSString stringWithFormat:@"%@--%@--%@", kAFMultipartFormCRLF, boundary, kAFMultipartFormCRLF];
}

//根据文件后缀名可以获取对应的Content-Type
static inline NSString * AFContentTypeForPathExtension(NSString *extension) {
    NSString *UTI = (__bridge_transfer NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)extension, NULL);
    NSString *contentType = (__bridge_transfer NSString *)UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)UTI, kUTTagClassMIMEType);
    if (!contentType) {
        return @"application/octet-stream";
    } else {
        return contentType;
    }
}

NSUInteger const kAFUploadStream3GSuggestedPacketSize = 1024 * 16;
NSTimeInterval const kAFUploadStream3GSuggestedDelay = 0.2;

//AFHTTPBodyPart的作用相当于一个model
@interface AFHTTPBodyPart : NSObject
@property (nonatomic, assign) NSStringEncoding stringEncoding;
@property (nonatomic, strong) NSDictionary *headers;
@property (nonatomic, copy) NSString *boundary;
@property (nonatomic, strong) id body;
@property (nonatomic, assign) unsigned long long bodyContentLength;
@property (nonatomic, strong) NSInputStream *inputStream;

@property (nonatomic, assign) BOOL hasInitialBoundary;
@property (nonatomic, assign) BOOL hasFinalBoundary;

@property (readonly, nonatomic, assign, getter = hasBytesAvailable) BOOL bytesAvailable;
@property (readonly, nonatomic, assign) unsigned long long contentLength;

- (NSInteger)read:(uint8_t *)buffer
        maxLength:(NSUInteger)length;
@end

@interface AFMultipartBodyStream : NSInputStream <NSStreamDelegate>
@property (nonatomic, assign) NSUInteger numberOfBytesInPacket;
@property (nonatomic, assign) NSTimeInterval delay;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (readonly, nonatomic, assign) unsigned long long contentLength;
@property (readonly, nonatomic, assign, getter = isEmpty) BOOL empty;

- (instancetype)initWithStringEncoding:(NSStringEncoding)encoding;
- (void)setInitialAndFinalBoundaries;
- (void)appendHTTPBodyPart:(AFHTTPBodyPart *)bodyPart;
@end

#pragma mark -

//该类用于POST上传文件,AFStreamingMultipartFormData继承自NSObject
@interface AFStreamingMultipartFormData ()
@property (readwrite, nonatomic, copy) NSMutableURLRequest *request;
@property (readwrite, nonatomic, assign) NSStringEncoding stringEncoding;
@property (readwrite, nonatomic, copy) NSString *boundary;
//AFMultipartBodyStream是NSInputStream的子类
@property (readwrite, nonatomic, strong) AFMultipartBodyStream *bodyStream;
@end

@implementation AFStreamingMultipartFormData

/**
 Multipart协议是基于post方法的组合实现，和post协议的主要区别在于请求头和请求体的不同
 multipart/form-data的请求头必须包含一个特殊的头信息：Content-Type，且其值也必须规定为multipart/form-data，同时还需要规定一个内容分割符用于分割请求体中的多个post的内容，如文件内容和文本内容自然需要分割开来，不然接收方就无法正常解析和还原这个文件了
 multipart/form-data的请求体也是一个字符串，不过和post的请求体不同的是它的构造方式，post是简单的name=value值连接，而multipart/form-data则是添加了分隔符等内容的构造体
 请求头（即request的HTTPHeaderField）中的Content-Type必须为multipart/form-data，
  [self.request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", self.boundary] forHTTPHeaderField:@"Content-Type"];
 请求体中也有一个Content-Type，这个content是体现文件类型的Content-Type，
 MIME (Multipurpose Internet Mail Extensions) 是描述消息内容类型的因特网标准，说白了也就是文件的媒体类型。浏览器可以根据它来区分文件，然后决定什么内容用什么形式来显示。
 媒体类型通常是通过 HTTP 协议，由 Web 服务器告知浏览器的，更准确地说，是通过 Content-Type 来表示的
 
 三、为什么要获取MIMEType
 
 关于为什么要获取MIMEType的原因，是因为在进行文件上传的时候，需要在POST请求体中传递相应的参数，来进行文件的上传操作
 说明：当然你也可以直接传递application/octet-stream，此参数表示通用的二进制类型。
 在HTTP中，MIME类型被定义在Content-Type header中。
 
 {".jpeg"后缀名的文件的mimeType是:  "image/jpeg"},
 {".jpg",  后缀名的文件的mimeType是:  "image/jpeg"},
 常见的MIME类型
 
 超文本标记语言文本 .html,.html text/html
 普通文本 .txt text/plain
 RTF文本 .rtf application/rtf
 GIF图形 .gif image/gif
 JPEG图形 .ipeg,.jpg image/jpeg
 au声音文件 .au audio/basic
 MIDI音乐文件 mid,.midi audio/midi,audio/x-midi
 RealAudio音乐文件 .ra, .ram audio/x-pn-realaudio
 MPEG文件 .mpg,.mpeg video/mpeg
 AVI文件 .avi video/x-msvideo
 GZIP文件 .gz application/x-gzip
 TAR文件 .tar application/x-tar
 
 eg:
 //“边界字符串 单独占一行
 --AaB03x
 //字段 field1。 content-disposition 个人理解为 内容特性 的意思。
 content-disposition: form-data; name="field1"
 //换行2次 空行，必须的
 
 Hello Boris! //字段的值   单独占一行
 
 --AaB03x //“边界字符串 单独占一行
 
 content-disposition: form-data; name="pic"; filename="boris.png" //字段 name 和 filename
 
 Content-Type: image/png //内容类型 与filename字段相对应
 //换行2次 空行，必须的
     
  <89504e47 ... 图片的二进制内容...>
  
  --AaB03x //“边界字符串 单独占一行
 ————————————————
 版权声明：本文为CSDN博主「sharehoney」的原创文章，遵循 CC 4.0 BY-SA 版权协议，转载请附上原文出处链接及本声明。
 原文链接：https://blog.csdn.net/shareapp/article/details/17198559
 
 版权声明：本文为CSDN博主「此生长安」的原创文章，遵循 CC 4.0 BY-SA 版权协议，转载请附上原文出处链接及本声明。
 原文链接：https://blog.csdn.net/cishengchangan/article/details/51939923
 **/
- (instancetype)initWithURLRequest:(NSMutableURLRequest *)urlRequest
                    stringEncoding:(NSStringEncoding)encoding
{
    self = [super init];
    if (!self) {
        return nil;
    }

    self.request = urlRequest;
    self.stringEncoding = encoding;
    //生成分隔符self.boundary
    self.boundary = AFCreateMultipartFormBoundary();
    
    //AFMultipartBodyStream是NSInputStream的子类
    self.bodyStream = [[AFMultipartBodyStream alloc] initWithStringEncoding:encoding];
    return self;
}

//重写self.request的set方法
- (void)setRequest:(NSMutableURLRequest *)request
{
    _request = [request mutableCopy];
}

//====================================协议方法start========================================================
//一下方法都是协议AFMultipartFormData的方法
- (BOOL)appendPartWithFileURL:(NSURL *)fileURL
                         name:(NSString *)name
                        error:(NSError * __autoreleasing *)error
{
    NSParameterAssert(fileURL);
    NSParameterAssert(name);

    NSString *fileName = [fileURL lastPathComponent];
    //通过AFContentTypeForPathExtension方法获取ContentType
    NSString *mimeType = AFContentTypeForPathExtension([fileURL pathExtension]);

    return [self appendPartWithFileURL:fileURL name:name fileName:fileName mimeType:mimeType error:error];
}

//上面方法会调用该方法
- (BOOL)appendPartWithFileURL:(NSURL *)fileURL
                         name:(NSString *)name
                     fileName:(NSString *)fileName
                     mimeType:(NSString *)mimeType
                        error:(NSError * __autoreleasing *)error
{
    NSParameterAssert(fileURL);
    NSParameterAssert(name);
    NSParameterAssert(fileName);
    NSParameterAssert(mimeType);

    if (![fileURL isFileURL]) {
        //不是文件url
        NSDictionary *userInfo = @{NSLocalizedFailureReasonErrorKey: NSLocalizedStringFromTable(@"Expected URL to be a file URL", @"AFNetworking", nil)};
        if (error) {
            *error = [[NSError alloc] initWithDomain:AFURLRequestSerializationErrorDomain code:NSURLErrorBadURL userInfo:userInfo];
        }

        return NO;
    } else if ([fileURL checkResourceIsReachableAndReturnError:error] == NO) {
        //checkResourceIsReachableAndReturnError:返回布尔值，说明 file URL 指向的文件资源是否可获取，若返回 NO，通过 error 参数可以获取更多信息
        NSDictionary *userInfo = @{NSLocalizedFailureReasonErrorKey: NSLocalizedStringFromTable(@"File URL not reachable.", @"AFNetworking", nil)};
        if (error) {
            *error = [[NSError alloc] initWithDomain:AFURLRequestSerializationErrorDomain code:NSURLErrorBadURL userInfo:userInfo];
        }

        return NO;
    }

    //到此可以获得文件
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path] error:error];
    if (!fileAttributes) {
        return NO;
    }

    NSMutableDictionary *mutableHeaders = [NSMutableDictionary dictionary];
    [mutableHeaders setValue:[NSString stringWithFormat:@"form-data; name=\"%@\"; filename=\"%@\"", name, fileName] forKey:@"Content-Disposition"];
    [mutableHeaders setValue:mimeType forKey:@"Content-Type"];

    //AFHTTPBodyPart相当起到一个model的作用
    AFHTTPBodyPart *bodyPart = [[AFHTTPBodyPart alloc] init];
    bodyPart.stringEncoding = self.stringEncoding;
    bodyPart.headers = mutableHeaders;
    bodyPart.boundary = self.boundary;
    //bodyPart.body设置的是文件路径fileURL
    bodyPart.body = fileURL;
    bodyPart.bodyContentLength = [fileAttributes[NSFileSize] unsignedLongLongValue];
    //self.bodyStream是一个AFMultipartBodyStream的对象
    [self.bodyStream appendHTTPBodyPart:bodyPart];

    return YES;
}

//传入的是输入流
- (void)appendPartWithInputStream:(NSInputStream *)inputStream
                             name:(NSString *)name
                         fileName:(NSString *)fileName
                           length:(int64_t)length
                         mimeType:(NSString *)mimeType
{
    NSParameterAssert(name);
    NSParameterAssert(fileName);
    NSParameterAssert(mimeType);

    NSMutableDictionary *mutableHeaders = [NSMutableDictionary dictionary];
    [mutableHeaders setValue:[NSString stringWithFormat:@"form-data; name=\"%@\"; filename=\"%@\"", name, fileName] forKey:@"Content-Disposition"];
    [mutableHeaders setValue:mimeType forKey:@"Content-Type"];

   //AFHTTPBodyPart相当起到一个model的作用,与上面不同的是此处没有fileURL，bodyPart.body直接设置的是输入流inputStream
    AFHTTPBodyPart *bodyPart = [[AFHTTPBodyPart alloc] init];
    bodyPart.stringEncoding = self.stringEncoding;
    bodyPart.headers = mutableHeaders;
    bodyPart.boundary = self.boundary;
    bodyPart.body = inputStream;

    bodyPart.bodyContentLength = (unsigned long long)length;

    [self.bodyStream appendHTTPBodyPart:bodyPart];
}

/**
 传入的是文件二进制数据data,最终调用下面的- (void)appendPartWithHeaders:(NSDictionary *)headers
 body:(NSData *)body方法
 **/
- (void)appendPartWithFileData:(NSData *)data
                          name:(NSString *)name
                      fileName:(NSString *)fileName
                      mimeType:(NSString *)mimeType
{
    NSParameterAssert(name);
    NSParameterAssert(fileName);
    NSParameterAssert(mimeType);

    NSMutableDictionary *mutableHeaders = [NSMutableDictionary dictionary];
    [mutableHeaders setValue:[NSString stringWithFormat:@"form-data; name=\"%@\"; filename=\"%@\"", name, fileName] forKey:@"Content-Disposition"];
    [mutableHeaders setValue:mimeType forKey:@"Content-Type"];

    [self appendPartWithHeaders:mutableHeaders body:data];
}

/**
 和上面的方法相似，传入的是文件二进制数据data，只是没有fileName和mimeType，最终调用下面的- (void)appendPartWithHeaders:(NSDictionary *)headers
 body:(NSData *)body方法
 该方法没有设置Content-Type
 **/
- (void)appendPartWithFormData:(NSData *)data
                          name:(NSString *)name
{
    NSParameterAssert(name);

    NSMutableDictionary *mutableHeaders = [NSMutableDictionary dictionary];
    [mutableHeaders setValue:[NSString stringWithFormat:@"form-data; name=\"%@\"", name] forKey:@"Content-Disposition"];

    [self appendPartWithHeaders:mutableHeaders body:data];
}

//上面两个方法会调用该方法
- (void)appendPartWithHeaders:(NSDictionary *)headers
                         body:(NSData *)body
{
    NSParameterAssert(body);

    AFHTTPBodyPart *bodyPart = [[AFHTTPBodyPart alloc] init];
    bodyPart.stringEncoding = self.stringEncoding;
    bodyPart.headers = headers;
    bodyPart.boundary = self.boundary;
    bodyPart.bodyContentLength = [body length];
    // bodyPart.body设置的是文件的二进制数据
    bodyPart.body = body;

    [self.bodyStream appendHTTPBodyPart:bodyPart];
}

/**
 通过限制包的大小来控制请求带宽，为从上传流中读取每个大块添加延迟。
 当通过3G或EDGE链接上传时，请求可能报“请求体流耗尽”的失败。依据建议的值（kAFUploadStreamGSuggestedPacketSize和 kAFUploadStream3GSuggestedDelay）设置一个最大的包大小和延迟，降低输入流分配过多的带宽的风险。同时，不建议你只基于网络可达性来限制带宽。替代的，你应该考虑在一个失败的块中检查“请求体流耗尽”，同时用限制带宽来重试请求。
 numberOfBytes:包的最大字节数。默认的输入流包大小为16kb。
 delay:每次读取一个包的延时间隔。默认情况下，不设置延时。
 
 作者：_阿南_
 链接：https://www.jianshu.com/p/9670769cc72b
 来源：简书
 著作权归作者所有。商业转载请联系作者获得授权，非商业转载请注明出处。
 **/
- (void)throttleBandwidthWithPacketSize:(NSUInteger)numberOfBytes
                                  delay:(NSTimeInterval)delay
{
    self.bodyStream.numberOfBytesInPacket = numberOfBytes;
    self.bodyStream.delay = delay;
}
//====================================协议方法end========================================================

- (NSMutableURLRequest *)requestByFinalizingMultipartFormData {
    if ([self.bodyStream isEmpty]) {
        return self.request;
    }

    // Reset the initial and final boundaries to ensure correct Content-Length
    [self.bodyStream setInitialAndFinalBoundaries];
    //
    [self.request setHTTPBodyStream:self.bodyStream];

    [self.request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", self.boundary] forHTTPHeaderField:@"Content-Type"];
    [self.request setValue:[NSString stringWithFormat:@"%llu", [self.bodyStream contentLength]] forHTTPHeaderField:@"Content-Length"];

    return self.request;
}

@end

#pragma mark -

@interface NSStream ()
@property (readwrite) NSStreamStatus streamStatus;
@property (readwrite, copy) NSError *streamError;
@end

@interface AFMultipartBodyStream () <NSCopying>
@property (readwrite, nonatomic, assign) NSStringEncoding stringEncoding;
@property (readwrite, nonatomic, strong) NSMutableArray *HTTPBodyParts;
@property (readwrite, nonatomic, strong) NSEnumerator *HTTPBodyPartEnumerator;
@property (readwrite, nonatomic, strong) AFHTTPBodyPart *currentHTTPBodyPart;
@property (readwrite, nonatomic, strong) NSOutputStream *outputStream;
@property (readwrite, nonatomic, strong) NSMutableData *buffer;
@end

@implementation AFMultipartBodyStream
#if (defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000) || (defined(__MAC_OS_X_VERSION_MAX_ALLOWED) && __MAC_OS_X_VERSION_MAX_ALLOWED >= 1100)
@synthesize delegate;
#endif
@synthesize streamStatus;
@synthesize streamError;

- (instancetype)initWithStringEncoding:(NSStringEncoding)encoding {
    self = [super init];
    if (!self) {
        return nil;
    }

    self.stringEncoding = encoding;
    self.HTTPBodyParts = [NSMutableArray array];
    //NSIntegerMax:The maximum value for an NSInteger.NSInteger的最大值
    self.numberOfBytesInPacket = NSIntegerMax;

    return self;
}

//设置self.HTTPBodyParts数组中第一个model,AFHTTPBodyPart *bodyPart的hasInitialBoundary为yes,最后一个model的hasFinalBoundary为yes
- (void)setInitialAndFinalBoundaries {
    if ([self.HTTPBodyParts count] > 0) {
        for (AFHTTPBodyPart *bodyPart in self.HTTPBodyParts) {
            bodyPart.hasInitialBoundary = NO;
            bodyPart.hasFinalBoundary = NO;
        }

        [[self.HTTPBodyParts firstObject] setHasInitialBoundary:YES];
        [[self.HTTPBodyParts lastObject] setHasFinalBoundary:YES];
    }
}

- (void)appendHTTPBodyPart:(AFHTTPBodyPart *)bodyPart {
    [self.HTTPBodyParts addObject:bodyPart];
}

- (BOOL)isEmpty {
    return [self.HTTPBodyParts count] == 0;
}

//=======================================NSInputStream start====================================================
#pragma mark - NSInputStream
/**
 // NSInputStream is an abstract class representing the base functionality of a read stream.
 // Subclassers are required to implement these methods.
 **/
- (NSInteger)read:(uint8_t *)buffer
        maxLength:(NSUInteger)length
{
    // 输入流关闭状态，无法读取
    if ([self streamStatus] == NSStreamStatusClosed) {
        return 0;
    }

    NSInteger totalNumberOfBytesRead = 0;

    // 一般来说都是直接读取length长度的数据，但是考虑到最后一次需要读出的数据长度(self.numberOfBytesInPacket)一般是小于length
    // 所以此处使用了MIN(length, self.numberOfBytesInPacket)
    while ((NSUInteger)totalNumberOfBytesRead < MIN(length, self.numberOfBytesInPacket)) {
        // 类似于我们构建request的逆向过程，我们对于HTTPBodyStream的读取也是分成一个一个AFHTTPBodyPart来的
        // 如果当前AFHTTPBodyPart对象读取完成，那么就使用enumerator读取下一个AFHTTPBodyPart
        if (!self.currentHTTPBodyPart || ![self.currentHTTPBodyPart hasBytesAvailable]) {
            if (!(self.currentHTTPBodyPart = [self.HTTPBodyPartEnumerator nextObject])) {
                break;
            }
        } else {
              // 读取当前AFHTTPBodyPart对象
            NSUInteger maxLength = MIN(length, self.numberOfBytesInPacket) - (NSUInteger)totalNumberOfBytesRead;
              // 使用的是AFHTTPBodyPart的read:maxLength:函数
            NSInteger numberOfBytesRead = [self.currentHTTPBodyPart read:&buffer[totalNumberOfBytesRead] maxLength:maxLength];
              // 读取出错
            if (numberOfBytesRead == -1) {
                self.streamError = self.currentHTTPBodyPart.inputStream.streamError;
                break;
            } else {
                  // totalNumberOfBytesRead表示目前已经读取的字节数，可以作为读取后的数据放置于buffer的起始位置，如buffer[totalNumberOfBytesRead]
                totalNumberOfBytesRead += numberOfBytesRead;

                if (self.delay > 0.0f) {
                    [NSThread sleepForTimeInterval:self.delay];
                }
            }
        }
    }

    return totalNumberOfBytesRead;
}

- (BOOL)getBuffer:(__unused uint8_t **)buffer
           length:(__unused NSUInteger *)len
{
    return NO;
}

- (BOOL)hasBytesAvailable {
    return [self streamStatus] == NSStreamStatusOpen;
}

//=======================================NSInputStream end====================================================


//=======================================NSStream start====================================================
/**
 // NSStream is an abstract class encapsulating the common API to NSInputStream and NSOutputStream.
 // Subclassers of NSInputStream and NSOutputStream must also implement these methods.
 **/
#pragma mark - NSStream

- (void)open {
    if (self.streamStatus == NSStreamStatusOpen) {
        return;
    }

    self.streamStatus = NSStreamStatusOpen;

    [self setInitialAndFinalBoundaries];
    self.HTTPBodyPartEnumerator = [self.HTTPBodyParts objectEnumerator];
}

- (void)close {
    self.streamStatus = NSStreamStatusClosed;
}

- (id)propertyForKey:(__unused NSString *)key {
    return nil;
}

- (BOOL)setProperty:(__unused id)property
             forKey:(__unused NSString *)key
{
    return NO;
}

- (void)scheduleInRunLoop:(__unused NSRunLoop *)aRunLoop
                  forMode:(__unused NSString *)mode
{}

- (void)removeFromRunLoop:(__unused NSRunLoop *)aRunLoop
                  forMode:(__unused NSString *)mode
{}

- (unsigned long long)contentLength {
    unsigned long long length = 0;
    for (AFHTTPBodyPart *bodyPart in self.HTTPBodyParts) {
        length += [bodyPart contentLength];
    }

    return length;
}

#pragma mark - Undocumented CFReadStream Bridged Methods

- (void)_scheduleInCFRunLoop:(__unused CFRunLoopRef)aRunLoop
                     forMode:(__unused CFStringRef)aMode
{}

- (void)_unscheduleFromCFRunLoop:(__unused CFRunLoopRef)aRunLoop
                         forMode:(__unused CFStringRef)aMode
{}

- (BOOL)_setCFClientFlags:(__unused CFOptionFlags)inFlags
                 callback:(__unused CFReadStreamClientCallBack)inCallback
                  context:(__unused CFStreamClientContext *)inContext {
    return NO;
}

//=======================================NSStream end====================================================

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone {
    AFMultipartBodyStream *bodyStreamCopy = [[[self class] allocWithZone:zone] initWithStringEncoding:self.stringEncoding];

    for (AFHTTPBodyPart *bodyPart in self.HTTPBodyParts) {
        [bodyStreamCopy appendHTTPBodyPart:[bodyPart copy]];
    }

    [bodyStreamCopy setInitialAndFinalBoundaries];

    return bodyStreamCopy;
}

@end

#pragma mark -

typedef enum {
    AFEncapsulationBoundaryPhase = 1,
    AFHeaderPhase                = 2,
    AFBodyPhase                  = 3,
    AFFinalBoundaryPhase         = 4,
} AFHTTPBodyPartReadPhase;

@interface AFHTTPBodyPart () <NSCopying> {
    AFHTTPBodyPartReadPhase _phase;
    NSInputStream *_inputStream;
    unsigned long long _phaseReadOffset;
}

- (BOOL)transitionToNextPhase;
- (NSInteger)readData:(NSData *)data
           intoBuffer:(uint8_t *)buffer
            maxLength:(NSUInteger)length;
@end

@implementation AFHTTPBodyPart

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    [self transitionToNextPhase];

    return self;
}

- (void)dealloc {
    if (_inputStream) {
        [_inputStream close];
        _inputStream = nil;
    }
}

- (NSInputStream *)inputStream {
    if (!_inputStream) {
        if ([self.body isKindOfClass:[NSData class]]) {
            _inputStream = [NSInputStream inputStreamWithData:self.body];
        } else if ([self.body isKindOfClass:[NSURL class]]) {
            _inputStream = [NSInputStream inputStreamWithURL:self.body];
        } else if ([self.body isKindOfClass:[NSInputStream class]]) {
            _inputStream = self.body;
        } else {
            _inputStream = [NSInputStream inputStreamWithData:[NSData data]];
        }
    }

    return _inputStream;
}

- (NSString *)stringForHeaders {
    NSMutableString *headerString = [NSMutableString string];
    for (NSString *field in [self.headers allKeys]) {
        [headerString appendString:[NSString stringWithFormat:@"%@: %@%@", field, [self.headers valueForKey:field], kAFMultipartFormCRLF]];
    }
    [headerString appendString:kAFMultipartFormCRLF];

    return [NSString stringWithString:headerString];
}

- (unsigned long long)contentLength {
    unsigned long long length = 0;

    NSData *encapsulationBoundaryData = [([self hasInitialBoundary] ? AFMultipartFormInitialBoundary(self.boundary) : AFMultipartFormEncapsulationBoundary(self.boundary)) dataUsingEncoding:self.stringEncoding];
    length += [encapsulationBoundaryData length];

    NSData *headersData = [[self stringForHeaders] dataUsingEncoding:self.stringEncoding];
    length += [headersData length];

    length += _bodyContentLength;

    NSData *closingBoundaryData = ([self hasFinalBoundary] ? [AFMultipartFormFinalBoundary(self.boundary) dataUsingEncoding:self.stringEncoding] : [NSData data]);
    length += [closingBoundaryData length];

    return length;
}

- (BOOL)hasBytesAvailable {
    // Allows `read:maxLength:` to be called again if `AFMultipartFormFinalBoundary` doesn't fit into the available buffer
    if (_phase == AFFinalBoundaryPhase) {
        return YES;
    }

    switch (self.inputStream.streamStatus) {
        case NSStreamStatusNotOpen:
        case NSStreamStatusOpening:
        case NSStreamStatusOpen:
        case NSStreamStatusReading:
        case NSStreamStatusWriting:
            return YES;
        case NSStreamStatusAtEnd:
        case NSStreamStatusClosed:
        case NSStreamStatusError:
        default:
            return NO;
    }
}

- (NSInteger)read:(uint8_t *)buffer
        maxLength:(NSUInteger)length
{
    NSInteger totalNumberOfBytesRead = 0;
    // 使用分隔符将对应bodyPart数据封装起来
    if (_phase == AFEncapsulationBoundaryPhase) {
        NSData *encapsulationBoundaryData = [([self hasInitialBoundary] ? AFMultipartFormInitialBoundary(self.boundary) : AFMultipartFormEncapsulationBoundary(self.boundary)) dataUsingEncoding:self.stringEncoding];
        totalNumberOfBytesRead += [self readData:encapsulationBoundaryData intoBuffer:&buffer[totalNumberOfBytesRead] maxLength:(length - (NSUInteger)totalNumberOfBytesRead)];
    }
    
  // 如果读取到的是bodyPart对应的header部分，那么使用stringForHeaders获取到对应header，并读取到buffer中
    if (_phase == AFHeaderPhase) {
        NSData *headersData = [[self stringForHeaders] dataUsingEncoding:self.stringEncoding];
        totalNumberOfBytesRead += [self readData:headersData intoBuffer:&buffer[totalNumberOfBytesRead] maxLength:(length - (NSUInteger)totalNumberOfBytesRead)];
    }

      // 如果读取到的是bodyPart的内容主体，即inputStream，那么就直接使用inputStream写入数据到buffer中
    if (_phase == AFBodyPhase) {
        NSInteger numberOfBytesRead = 0;

         // 使用系统自带的NSInputStream的read:maxLength:函数读取
        numberOfBytesRead = [self.inputStream read:&buffer[totalNumberOfBytesRead] maxLength:(length - (NSUInteger)totalNumberOfBytesRead)];
        if (numberOfBytesRead == -1) {
            return -1;
        } else {
            totalNumberOfBytesRead += numberOfBytesRead;

            // 如果内容主体都读取完了，那么很有可能下一次读取的就是下一个bodyPart的header
            // 所以此处要调用transitionToNextPhase，调整对应_phase
            if ([self.inputStream streamStatus] >= NSStreamStatusAtEnd) {
                [self transitionToNextPhase];
            }
        }
    }

      // 如果是最后一个AFHTTPBodyPart对象，那么就需要添加在末尾”--分隔符--"
    if (_phase == AFFinalBoundaryPhase) {
        NSData *closingBoundaryData = ([self hasFinalBoundary] ? [AFMultipartFormFinalBoundary(self.boundary) dataUsingEncoding:self.stringEncoding] : [NSData data]);
        totalNumberOfBytesRead += [self readData:closingBoundaryData intoBuffer:&buffer[totalNumberOfBytesRead] maxLength:(length - (NSUInteger)totalNumberOfBytesRead)];
    }

    return totalNumberOfBytesRead;
}

// 上面那个函数中大量使用了read:intoBuffer:maxLength:函数
// 这里我们将read:intoBuffer:maxLength:理解成一种将NSData类型的data转化为(uint8_t *)类型的buffer的手段，核心是使用了NSData的getBytes:range:函数
- (NSInteger)readData:(NSData *)data
           intoBuffer:(uint8_t *)buffer
            maxLength:(NSUInteger)length
{
      // 求取range，需要考虑文件末尾比maxLength会小的情况
    NSRange range = NSMakeRange((NSUInteger)_phaseReadOffset, MIN([data length] - ((NSUInteger)_phaseReadOffset), length));
       // 核心：NSData *---->uint8_t*
    [data getBytes:buffer range:range];

    _phaseReadOffset += range.length;

       // 读取完成就更新_phase的状态
    if (((NSUInteger)_phaseReadOffset) >= [data length]) {
        [self transitionToNextPhase];
    }

    return (NSInteger)range.length;
}

- (BOOL)transitionToNextPhase {
    if (![[NSThread currentThread] isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self transitionToNextPhase];
        });
        return YES;
    }

    switch (_phase) {
        case AFEncapsulationBoundaryPhase:
            _phase = AFHeaderPhase;
            break;
        case AFHeaderPhase:
            [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
            [self.inputStream open];
            _phase = AFBodyPhase;
            break;
        case AFBodyPhase:
            [self.inputStream close];
            _phase = AFFinalBoundaryPhase;
            break;
        case AFFinalBoundaryPhase:
        default:
            _phase = AFEncapsulationBoundaryPhase;
            break;
    }
    _phaseReadOffset = 0;

    return YES;
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone {
    AFHTTPBodyPart *bodyPart = [[[self class] allocWithZone:zone] init];

    bodyPart.stringEncoding = self.stringEncoding;
    bodyPart.headers = self.headers;
    bodyPart.bodyContentLength = self.bodyContentLength;
    bodyPart.body = self.body;
    bodyPart.boundary = self.boundary;

    return bodyPart;
}

@end

#pragma mark -

@implementation AFJSONRequestSerializer

+ (instancetype)serializer {
    return [self serializerWithWritingOptions:(NSJSONWritingOptions)0];
}

+ (instancetype)serializerWithWritingOptions:(NSJSONWritingOptions)writingOptions
{
    AFJSONRequestSerializer *serializer = [[self alloc] init];
    serializer.writingOptions = writingOptions;

    return serializer;
}

#pragma mark - AFURLRequestSerialization

- (NSURLRequest *)requestBySerializingRequest:(NSURLRequest *)request
                               withParameters:(id)parameters
                                        error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(request);

    if ([self.HTTPMethodsEncodingParametersInURI containsObject:[[request HTTPMethod] uppercaseString]]) {
        /**
         此时表示对参数需要进行编码，HTTPMethodsEncodingParametersInURI里默认是`GET`, `HEAD`, and `DELETE` ，这些请求方式参数放在url里，如果是post请求不使用AFJSONRequestSerializer或者AFPropertyListRequestSerializer，则会调用默认的请求头Content-Type,为application/x-www-form-urlencoded，所有参数以键值对方法拼接成一个字符串，然后转成NSData,放在请求体
         **/
        return [super requestBySerializingRequest:request withParameters:parameters error:error];
    }
    

    NSMutableURLRequest *mutableRequest = [request mutableCopy];

    //设置请求头
    [self.HTTPRequestHeaders enumerateKeysAndObjectsUsingBlock:^(id field, id value, BOOL * __unused stop) {
        if (![request valueForHTTPHeaderField:field]) {
            [mutableRequest setValue:value forHTTPHeaderField:field];
        }
    }];

    if (parameters) {
        //处理传入的参数，将参数处理成json,放入请求体
        if (![mutableRequest valueForHTTPHeaderField:@"Content-Type"]) {
            [mutableRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        }

        if (![NSJSONSerialization isValidJSONObject:parameters]) {
            if (error) {
                NSDictionary *userInfo = @{NSLocalizedFailureReasonErrorKey: NSLocalizedStringFromTable(@"The `parameters` argument is not valid JSON.", @"AFNetworking", nil)};
                *error = [[NSError alloc] initWithDomain:AFURLRequestSerializationErrorDomain code:NSURLErrorCannotDecodeContentData userInfo:userInfo];
            }
            return nil;
        }

        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:parameters options:self.writingOptions error:error];
        
        if (!jsonData) {
            return nil;
        }
        
        [mutableRequest setHTTPBody:jsonData];
    }

    return mutableRequest;
}

#pragma mark - NSSecureCoding

- (instancetype)initWithCoder:(NSCoder *)decoder {
    self = [super initWithCoder:decoder];
    if (!self) {
        return nil;
    }

    self.writingOptions = [[decoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(writingOptions))] unsignedIntegerValue];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [super encodeWithCoder:coder];

    [coder encodeObject:@(self.writingOptions) forKey:NSStringFromSelector(@selector(writingOptions))];
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone {
    AFJSONRequestSerializer *serializer = [super copyWithZone:zone];
    serializer.writingOptions = self.writingOptions;

    return serializer;
}

@end

#pragma mark -

//AFPropertyListRequestSerializer的参数也是放在请求体内，因为这个对应的是POST请求
@implementation AFPropertyListRequestSerializer

+ (instancetype)serializer {
    return [self serializerWithFormat:NSPropertyListXMLFormat_v1_0 writeOptions:0];
}

+ (instancetype)serializerWithFormat:(NSPropertyListFormat)format
                        writeOptions:(NSPropertyListWriteOptions)writeOptions
{
    AFPropertyListRequestSerializer *serializer = [[self alloc] init];
    serializer.format = format;
    serializer.writeOptions = writeOptions;

    return serializer;
}

#pragma mark - AFURLRequestSerializer

- (NSURLRequest *)requestBySerializingRequest:(NSURLRequest *)request
                               withParameters:(id)parameters
                                        error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(request);

    if ([self.HTTPMethodsEncodingParametersInURI containsObject:[[request HTTPMethod] uppercaseString]]) {
          //此时表示对参数需要进行编码，HTTPMethodsEncodingParametersInURI里默认是`GET`, `HEAD`, and `DELETE` ，这些参数放在url里
        return [super requestBySerializingRequest:request withParameters:parameters error:error];
    }

    NSMutableURLRequest *mutableRequest = [request mutableCopy];

    //设置请求头
    [self.HTTPRequestHeaders enumerateKeysAndObjectsUsingBlock:^(id field, id value, BOOL * __unused stop) {
        if (![request valueForHTTPHeaderField:field]) {
            [mutableRequest setValue:value forHTTPHeaderField:field];
        }
    }];

    if (parameters) {
        if (![mutableRequest valueForHTTPHeaderField:@"Content-Type"]) {
            [mutableRequest setValue:@"application/x-plist" forHTTPHeaderField:@"Content-Type"];
        }

        NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:parameters format:self.format options:self.writeOptions error:error];
        
        if (!plistData) {
            return nil;
        }
        
        [mutableRequest setHTTPBody:plistData];
    }

    return mutableRequest;
}

#pragma mark - NSSecureCoding

- (instancetype)initWithCoder:(NSCoder *)decoder {
    self = [super initWithCoder:decoder];
    if (!self) {
        return nil;
    }

    self.format = (NSPropertyListFormat)[[decoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(format))] unsignedIntegerValue];
    self.writeOptions = [[decoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(writeOptions))] unsignedIntegerValue];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [super encodeWithCoder:coder];

    [coder encodeObject:@(self.format) forKey:NSStringFromSelector(@selector(format))];
    [coder encodeObject:@(self.writeOptions) forKey:NSStringFromSelector(@selector(writeOptions))];
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone {
    AFPropertyListRequestSerializer *serializer = [super copyWithZone:zone];
    serializer.format = self.format;
    serializer.writeOptions = self.writeOptions;

    return serializer;
}

@end
