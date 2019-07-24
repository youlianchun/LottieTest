/*
 Copyright (c) 2012-2019, Pierre-Olivier Latour
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * The name of Pierre-Olivier Latour may not be used to endorse
 or promote products derived from this software without specific
 prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL PIERRE-OLIVIER LATOUR BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#if !__has_feature(objc_arc)
#error GCDWebHDServer requires ARC
#endif

// WebDAV specifications: http://webdav.org/specs/rfc4918.html

// Requires "HEADER_SEARCH_PATHS = $(SDKROOT)/usr/include/libxml2" in Xcode build settings
#import <libxml/parser.h>

#import "GCDWebHDServer.h"
#import "GCDWebServerFunctions.h"

#import "GCDWebServerDataRequest.h"
#import "GCDWebServerFileRequest.h"
#import "GCDWebServerMultiPartFormRequest.h"
#import "GCDWebServerURLEncodedFormRequest.h"

#import "GCDWebServerDataResponse.h"
#import "GCDWebServerErrorResponse.h"
#import "GCDWebServerFileResponse.h"

#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <SystemConfiguration/SystemConfiguration.h>
#endif


#define kXMLParseOptions (XML_PARSE_NONET | XML_PARSE_RECOVER | XML_PARSE_NOBLANKS | XML_PARSE_COMPACT | XML_PARSE_NOWARNING | XML_PARSE_NOERROR)

typedef NS_ENUM(NSInteger, DAVProperties) {
    kDAVProperty_ResourceType = (1 << 0),
    kDAVProperty_CreationDate = (1 << 1),
    kDAVProperty_LastModified = (1 << 2),
    kDAVProperty_ContentLength = (1 << 3),
    kDAVAllProperties = kDAVProperty_ResourceType | kDAVProperty_CreationDate | kDAVProperty_LastModified | kDAVProperty_ContentLength
};

NSString* const GCDWebHDServerOption_HDDirectory = @"WebHDDirectory";

NS_ASSUME_NONNULL_BEGIN

@interface GCDWebHDServer (DAVMethods)
- (void)davInit;
@end

@interface GCDWebHDServer (UploaderMethods)
- (void)uploaderInitSiteBundle:(NSBundle *)siteBundle;
@end

NS_ASSUME_NONNULL_END

@implementation GCDWebHDServer

@dynamic delegate;

- (instancetype)init {
    return [self initWithSiteBundle:GCDWebHDServer.defaultSideBundle];
}

- (instancetype)initWithSiteBundle:(NSBundle *)siteBundle {
    if (self = [super init]) {
        _directory = NSHomeDirectory();
        [self davInit];
        [self uploaderInitSiteBundle:siteBundle];
    }
    return self;
}

- (BOOL)startWithDirectory:(NSString *)directory options:(NSDictionary<NSString *,id> *)options error:(NSError * _Nullable __autoreleasing *)error {
    if (directory.length == 0) return NO;
    _directory = directory;
    return [super startWithOptions:options error:error];
}

- (BOOL)startWithOptions:(NSDictionary<NSString*, id>*)options error:(NSError**)error {
    return [self startWithDirectory:options[GCDWebHDServerOption_HDDirectory] options:options error:error];
}

@end

@implementation GCDWebHDServer (SideBundle)
+ (NSBundle *)defaultSideBundle {
    NSString* bundlePath = [[NSBundle bundleForClass:[GCDWebHDServer class]] pathForResource:@"GCDWebHDServerSide" ofType:@"bundle"];
    return [NSBundle bundleWithPath:bundlePath];
}

@end

@implementation GCDWebHDServer (Check)
- (BOOL)_checkFileExtension:(NSString*)fileName {
    if (_allowedFileExtensions && ![_allowedFileExtensions containsObject:[[fileName pathExtension] lowercaseString]]) {
        return NO;
    }
    return YES;
}
@end

@implementation GCDWebHDServer (DAVMethods)

- (void)davInit {
    GCDWebHDServer* __unsafe_unretained server = self;
    
    // 9.1 PROPFIND method
    [self addDefaultHandlerForMethod:@"PROPFIND"
                        requestClass:[GCDWebServerDataRequest class]
                        processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                            return [server performPROPFIND:(GCDWebServerDataRequest*)request];
                        }];
    
    // 9.3 MKCOL Method
    [self addDefaultHandlerForMethod:@"MKCOL"
                        requestClass:[GCDWebServerDataRequest class]
                        processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                            return [server performMKCOL:(GCDWebServerDataRequest*)request];
                        }];
    
    // 9.4 GET & HEAD methods
    [self addDefaultHandlerForMethod:@"GET"
                        requestClass:[GCDWebServerRequest class]
                        processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                            return [server performGET:request];
                        }];
    
    // 9.6 DELETE method
    [self addDefaultHandlerForMethod:@"DELETE"
                        requestClass:[GCDWebServerRequest class]
                        processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                            return [server performDELETE:request];
                        }];
    
    // 9.7 PUT method
    [self addDefaultHandlerForMethod:@"PUT"
                        requestClass:[GCDWebServerFileRequest class]
                        processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                            return [server performPUT:(GCDWebServerFileRequest*)request];
                        }];
    
    // 9.8 COPY method
    [self addDefaultHandlerForMethod:@"COPY"
                        requestClass:[GCDWebServerRequest class]
                        processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                            return [server performCOPY:request isMove:NO];
                        }];
    
    // 9.9 MOVE method
    [self addDefaultHandlerForMethod:@"MOVE"
                        requestClass:[GCDWebServerRequest class]
                        processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                            return [server performCOPY:request isMove:YES];
                        }];
    
    // 9.10 LOCK method
    [self addDefaultHandlerForMethod:@"LOCK"
                        requestClass:[GCDWebServerDataRequest class]
                        processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                            return [server performLOCK:(GCDWebServerDataRequest*)request];
                        }];
    
    // 9.11 UNLOCK method
    [self addDefaultHandlerForMethod:@"UNLOCK"
                        requestClass:[GCDWebServerRequest class]
                        processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                            return [server performUNLOCK:request];
                        }];
    
    // 10.1 OPTIONS method / DAV Header
    [self addDefaultHandlerForMethod:@"OPTIONS"
                        requestClass:[GCDWebServerRequest class]
                        processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                            return [server performOPTIONS:request];
                        }];
}

static inline BOOL _IsMacFinder(GCDWebServerRequest* request) {
    NSString* userAgentHeader = [request.headers objectForKey:@"User-Agent"];
    return ([userAgentHeader hasPrefix:@"WebDAVFS/"] || [userAgentHeader hasPrefix:@"WebDAVLib/"]);  // OS X WebDAV client
}

- (GCDWebServerResponse*)performOPTIONS:(GCDWebServerRequest*)request {
    GCDWebServerResponse* response = [GCDWebServerResponse response];
    if (_IsMacFinder(request)) {
        [response setValue:@"1, 2" forAdditionalHeader:@"DAV"];  // Classes 1 and 2
    } else {
        [response setValue:@"1" forAdditionalHeader:@"DAV"];  // Class 1
    }
    return response;
}

- (GCDWebServerResponse*)performGET:(GCDWebServerRequest*)request {
    NSString* relativePath = request.path;
    NSString* absolutePath = [_directory stringByAppendingPathComponent:GCDWebServerNormalizePath(relativePath)];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
    }
    
    NSString* itemName = [absolutePath lastPathComponent];
    if (([itemName hasPrefix:@"."] && !_allowHiddenItems) || (!isDirectory && ![self _checkFileExtension:itemName])) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Downlading item name \"%@\" is not allowed", itemName];
    }
    
    // Because HEAD requests are mapped to GET ones, we need to handle directories but it's OK to return nothing per http://webdav.org/specs/rfc4918.html#rfc.section.9.4
    if (isDirectory) {
        return [GCDWebServerResponse response];
    }
    
    if ([self.delegate respondsToSelector:@selector(hdServer:didDownloadFileAtPath:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate hdServer:self didDownloadFileAtPath:absolutePath];
        });
    }
    
    if ([request hasByteRange]) {
        return [GCDWebServerFileResponse responseWithFile:absolutePath byteRange:request.byteRange];
    }
    
    return [GCDWebServerFileResponse responseWithFile:absolutePath];
}

- (GCDWebServerResponse*)performPUT:(GCDWebServerFileRequest*)request {
    if ([request hasByteRange]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"Range uploads not supported"];
    }
    
    NSString* relativePath = request.path;
    NSString* absolutePath = [_directory stringByAppendingPathComponent:GCDWebServerNormalizePath(relativePath)];
    BOOL isDirectory;
    if (![[NSFileManager defaultManager] fileExistsAtPath:[absolutePath stringByDeletingLastPathComponent] isDirectory:&isDirectory] || !isDirectory) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Conflict message:@"Missing intermediate collection(s) for \"%@\"", relativePath];
    }
    
    BOOL existing = [[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory];
    if (existing && isDirectory) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_MethodNotAllowed message:@"PUT not allowed on existing collection \"%@\"", relativePath];
    }
    
    NSString* fileName = [absolutePath lastPathComponent];
    if (([fileName hasPrefix:@"."] && !_allowHiddenItems) || ![self _checkFileExtension:fileName]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Uploading file name \"%@\" is not allowed", fileName];
    }
    
    if (![self shouldUploadFileAtPath:absolutePath withTemporaryFile:request.temporaryPath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Uploading file to \"%@\" is not permitted", relativePath];
    }
    
    [[NSFileManager defaultManager] removeItemAtPath:absolutePath error:NULL];
    NSError* error = nil;
    if (![[NSFileManager defaultManager] moveItemAtPath:request.temporaryPath toPath:absolutePath error:&error]) {
        return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed moving uploaded file to \"%@\"", relativePath];
    }
    
    if ([self.delegate respondsToSelector:@selector(hdServer:didUploadFileAtPath:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate hdServer:self didUploadFileAtPath:absolutePath];
        });
    }
    return [GCDWebServerResponse responseWithStatusCode:(existing ? kGCDWebServerHTTPStatusCode_NoContent : kGCDWebServerHTTPStatusCode_Created)];
}

- (GCDWebServerResponse*)performDELETE:(GCDWebServerRequest*)request {
    NSString* depthHeader = [request.headers objectForKey:@"Depth"];
    if (depthHeader && ![depthHeader isEqualToString:@"infinity"]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"Unsupported 'Depth' header: %@", depthHeader];
    }
    
    NSString* relativePath = request.path;
    NSString* absolutePath = [_directory stringByAppendingPathComponent:GCDWebServerNormalizePath(relativePath)];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
    }
    
    NSString* itemName = [absolutePath lastPathComponent];
    if (([itemName hasPrefix:@"."] && !_allowHiddenItems) || (!isDirectory && ![self _checkFileExtension:itemName])) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Deleting item name \"%@\" is not allowed", itemName];
    }
    
    if (![self shouldDeleteItemAtPath:absolutePath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Deleting \"%@\" is not permitted", relativePath];
    }
    
    NSError* error = nil;
    if (![[NSFileManager defaultManager] removeItemAtPath:absolutePath error:&error]) {
        return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed deleting \"%@\"", relativePath];
    }
    
    if ([self.delegate respondsToSelector:@selector(hdServer:didDeleteItemAtPath:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate hdServer:self didDeleteItemAtPath:absolutePath];
        });
    }
    return [GCDWebServerResponse responseWithStatusCode:kGCDWebServerHTTPStatusCode_NoContent];
}

- (GCDWebServerResponse*)performMKCOL:(GCDWebServerDataRequest*)request {
    if ([request hasBody] && (request.contentLength > 0)) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_UnsupportedMediaType message:@"Unexpected request body for MKCOL method"];
    }
    
    NSString* relativePath = request.path;
    NSString* absolutePath = [_directory stringByAppendingPathComponent:GCDWebServerNormalizePath(relativePath)];
    BOOL isDirectory;
    if (![[NSFileManager defaultManager] fileExistsAtPath:[absolutePath stringByDeletingLastPathComponent] isDirectory:&isDirectory] || !isDirectory) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Conflict message:@"Missing intermediate collection(s) for \"%@\"", relativePath];
    }
    
    NSString* directoryName = [absolutePath lastPathComponent];
    if (!_allowHiddenItems && [directoryName hasPrefix:@"."]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Creating directory name \"%@\" is not allowed", directoryName];
    }
    
    if (![self shouldCreateDirectoryAtPath:absolutePath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Creating directory \"%@\" is not permitted", relativePath];
    }
    
    NSError* error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:absolutePath withIntermediateDirectories:NO attributes:nil error:&error]) {
        return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed creating directory \"%@\"", relativePath];
    }
#ifdef __GCDWEBSERVER_ENABLE_TESTING__
    NSString* creationDateHeader = [request.headers objectForKey:@"X-GCDWebServer-CreationDate"];
    if (creationDateHeader) {
        NSDate* date = GCDWebServerParseISO8601(creationDateHeader);
        if (!date || ![[NSFileManager defaultManager] setAttributes:@{NSFileCreationDate : date} ofItemAtPath:absolutePath error:&error]) {
            return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed setting creation date for directory \"%@\"", relativePath];
        }
    }
#endif
    
    if ([self.delegate respondsToSelector:@selector(hdServer:didCreateDirectoryAtPath:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate hdServer:self didCreateDirectoryAtPath:absolutePath];
        });
    }
    return [GCDWebServerResponse responseWithStatusCode:kGCDWebServerHTTPStatusCode_Created];
}

- (GCDWebServerResponse*)performCOPY:(GCDWebServerRequest*)request isMove:(BOOL)isMove {
    if (!isMove) {
        NSString* depthHeader = [request.headers objectForKey:@"Depth"];  // TODO: Support "Depth: 0"
        if (depthHeader && ![depthHeader isEqualToString:@"infinity"]) {
            return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"Unsupported 'Depth' header: %@", depthHeader];
        }
    }
    
    NSString* srcRelativePath = request.path;
    NSString* srcAbsolutePath = [_directory stringByAppendingPathComponent:GCDWebServerNormalizePath(srcRelativePath)];
    
    NSString* dstRelativePath = [request.headers objectForKey:@"Destination"];
    NSRange range = [dstRelativePath rangeOfString:(NSString*)[request.headers objectForKey:@"Host"]];
    if ((dstRelativePath == nil) || (range.location == NSNotFound)) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"Malformed 'Destination' header: %@", dstRelativePath];
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    dstRelativePath = [[dstRelativePath substringFromIndex:(range.location + range.length)] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
#pragma clang diagnostic pop
    NSString* dstAbsolutePath = [_directory stringByAppendingPathComponent:GCDWebServerNormalizePath(dstRelativePath)];
    if (!dstAbsolutePath) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", srcRelativePath];
    }
    
    BOOL isDirectory;
    if (![[NSFileManager defaultManager] fileExistsAtPath:[dstAbsolutePath stringByDeletingLastPathComponent] isDirectory:&isDirectory] || !isDirectory) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Conflict message:@"Invalid destination \"%@\"", dstRelativePath];
    }
    
    NSString* itemName = [dstAbsolutePath lastPathComponent];
    if ((!_allowHiddenItems && [itemName hasPrefix:@"."]) || (!isDirectory && ![self _checkFileExtension:itemName])) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"%@ to item name \"%@\" is not allowed", isMove ? @"Moving" : @"Copying", itemName];
    }
    
    NSString* overwriteHeader = [request.headers objectForKey:@"Overwrite"];
    BOOL existing = [[NSFileManager defaultManager] fileExistsAtPath:dstAbsolutePath];
    if (existing && ((isMove && ![overwriteHeader isEqualToString:@"T"]) || (!isMove && [overwriteHeader isEqualToString:@"F"]))) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_PreconditionFailed message:@"Destination \"%@\" already exists", dstRelativePath];
    }
    
    if (isMove) {
        if (![self shouldMoveItemFromPath:srcAbsolutePath toPath:dstAbsolutePath]) {
            return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Moving \"%@\" to \"%@\" is not permitted", srcRelativePath, dstRelativePath];
        }
    } else {
        if (![self shouldCopyItemFromPath:srcAbsolutePath toPath:dstAbsolutePath]) {
            return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Copying \"%@\" to \"%@\" is not permitted", srcRelativePath, dstRelativePath];
        }
    }
    
    NSError* error = nil;
    if (isMove) {
        [[NSFileManager defaultManager] removeItemAtPath:dstAbsolutePath error:NULL];
        if (![[NSFileManager defaultManager] moveItemAtPath:srcAbsolutePath toPath:dstAbsolutePath error:&error]) {
            return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden underlyingError:error message:@"Failed copying \"%@\" to \"%@\"", srcRelativePath, dstRelativePath];
        }
    } else {
        if (![[NSFileManager defaultManager] copyItemAtPath:srcAbsolutePath toPath:dstAbsolutePath error:&error]) {
            return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden underlyingError:error message:@"Failed copying \"%@\" to \"%@\"", srcRelativePath, dstRelativePath];
        }
    }
    
    if (isMove) {
        if ([self.delegate respondsToSelector:@selector(hdServer:didMoveItemFromPath:toPath:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate hdServer:self didMoveItemFromPath:srcAbsolutePath toPath:dstAbsolutePath];
            });
        }
    } else {
        if ([self.delegate respondsToSelector:@selector(hdServer:didCopyItemFromPath:toPath:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate hdServer:self didCopyItemFromPath:srcAbsolutePath toPath:dstAbsolutePath];
            });
        }
    }
    
    return [GCDWebServerResponse responseWithStatusCode:(existing ? kGCDWebServerHTTPStatusCode_NoContent : kGCDWebServerHTTPStatusCode_Created)];
}

static inline xmlNodePtr _XMLChildWithName(xmlNodePtr child, const xmlChar* name) {
    while (child) {
        if ((child->type == XML_ELEMENT_NODE) && !xmlStrcmp(child->name, name)) {
            return child;
        }
        child = child->next;
    }
    return NULL;
}

- (void)_addPropertyResponseForItem:(NSString*)itemPath resource:(NSString*)resourcePath properties:(DAVProperties)properties xmlString:(NSMutableString*)xmlString {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CFStringRef escapedPath = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (__bridge CFStringRef)resourcePath, NULL, CFSTR("<&>?+"), kCFStringEncodingUTF8);
#pragma clang diagnostic pop
    if (escapedPath) {
        NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:itemPath error:NULL];
        NSString* type = [attributes objectForKey:NSFileType];
        BOOL isFile = [type isEqualToString:NSFileTypeRegular];
        BOOL isDirectory = [type isEqualToString:NSFileTypeDirectory];
        if ((isFile && [self _checkFileExtension:itemPath]) || isDirectory) {
            [xmlString appendString:@"<D:response>"];
            [xmlString appendFormat:@"<D:href>%@</D:href>", escapedPath];
            [xmlString appendString:@"<D:propstat>"];
            [xmlString appendString:@"<D:prop>"];
            
            if (properties & kDAVProperty_ResourceType) {
                if (isDirectory) {
                    [xmlString appendString:@"<D:resourcetype><D:collection/></D:resourcetype>"];
                } else {
                    [xmlString appendString:@"<D:resourcetype/>"];
                }
            }
            
            if ((properties & kDAVProperty_CreationDate) && [attributes objectForKey:NSFileCreationDate]) {
                [xmlString appendFormat:@"<D:creationdate>%@</D:creationdate>", GCDWebServerFormatISO8601((NSDate*)[attributes fileCreationDate])];
            }
            
            if ((properties & kDAVProperty_LastModified) && isFile && [attributes objectForKey:NSFileModificationDate]) {  // Last modification date is not useful for directories as it changes implicitely and 'Last-Modified' header is not provided for directories anyway
                [xmlString appendFormat:@"<D:getlastmodified>%@</D:getlastmodified>", GCDWebServerFormatRFC822((NSDate*)[attributes fileModificationDate])];
            }
            
            if ((properties & kDAVProperty_ContentLength) && !isDirectory && [attributes objectForKey:NSFileSize]) {
                [xmlString appendFormat:@"<D:getcontentlength>%llu</D:getcontentlength>", [attributes fileSize]];
            }
            
            [xmlString appendString:@"</D:prop>"];
            [xmlString appendString:@"<D:status>HTTP/1.1 200 OK</D:status>"];
            [xmlString appendString:@"</D:propstat>"];
            [xmlString appendString:@"</D:response>\n"];
        }
        CFRelease(escapedPath);
    } else {
        [self logError:@"Failed escaping path: %@", itemPath];
    }
}

- (GCDWebServerResponse*)performPROPFIND:(GCDWebServerDataRequest*)request {
    NSInteger depth;
    NSString* depthHeader = [request.headers objectForKey:@"Depth"];
    if ([depthHeader isEqualToString:@"0"]) {
        depth = 0;
    } else if ([depthHeader isEqualToString:@"1"]) {
        depth = 1;
    } else {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"Unsupported 'Depth' header: %@", depthHeader];  // TODO: Return 403 / propfind-finite-depth for "infinity" depth
    }
    
    DAVProperties properties = 0;
    if (request.data.length) {
        BOOL success = YES;
        xmlDocPtr document = xmlReadMemory(request.data.bytes, (int)request.data.length, NULL, NULL, kXMLParseOptions);
        if (document) {
            xmlNodePtr rootNode = _XMLChildWithName(document->children, (const xmlChar*)"propfind");
            xmlNodePtr allNode = rootNode ? _XMLChildWithName(rootNode->children, (const xmlChar*)"allprop") : NULL;
            xmlNodePtr propNode = rootNode ? _XMLChildWithName(rootNode->children, (const xmlChar*)"prop") : NULL;
            if (allNode) {
                properties = kDAVAllProperties;
            } else if (propNode) {
                xmlNodePtr node = propNode->children;
                while (node) {
                    if (!xmlStrcmp(node->name, (const xmlChar*)"resourcetype")) {
                        properties |= kDAVProperty_ResourceType;
                    } else if (!xmlStrcmp(node->name, (const xmlChar*)"creationdate")) {
                        properties |= kDAVProperty_CreationDate;
                    } else if (!xmlStrcmp(node->name, (const xmlChar*)"getlastmodified")) {
                        properties |= kDAVProperty_LastModified;
                    } else if (!xmlStrcmp(node->name, (const xmlChar*)"getcontentlength")) {
                        properties |= kDAVProperty_ContentLength;
                    } else {
                        [self logWarning:@"Unknown DAV property requested \"%s\"", node->name];
                    }
                    node = node->next;
                }
            } else {
                success = NO;
            }
            xmlFreeDoc(document);
        } else {
            success = NO;
        }
        if (!success) {
            NSString* string = [[NSString alloc] initWithData:request.data encoding:NSUTF8StringEncoding];
            return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"Invalid DAV properties:\n%@", string];
        }
    } else {
        properties = kDAVAllProperties;
    }
    
    NSString* relativePath = request.path;
    NSString* absolutePath = [_directory stringByAppendingPathComponent:GCDWebServerNormalizePath(relativePath)];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
    }
    
    NSString* itemName = [absolutePath lastPathComponent];
    if (([itemName hasPrefix:@"."] && !_allowHiddenItems) || (!isDirectory && ![self _checkFileExtension:itemName])) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Retrieving properties for item name \"%@\" is not allowed", itemName];
    }
    
    NSArray* items = nil;
    if (isDirectory) {
        NSError* error = nil;
        items = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:absolutePath error:&error] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
        if (items == nil) {
            return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed listing directory \"%@\"", relativePath];
        }
    }
    
    NSMutableString* xmlString = [NSMutableString stringWithString:@"<?xml version=\"1.0\" encoding=\"utf-8\" ?>"];
    [xmlString appendString:@"<D:multistatus xmlns:D=\"DAV:\">\n"];
    if (![relativePath hasPrefix:@"/"]) {
        relativePath = [@"/" stringByAppendingString:relativePath];
    }
    [self _addPropertyResponseForItem:absolutePath resource:relativePath properties:properties xmlString:xmlString];
    if (depth == 1) {
        if (![relativePath hasSuffix:@"/"]) {
            relativePath = [relativePath stringByAppendingString:@"/"];
        }
        for (NSString* item in items) {
            if (_allowHiddenItems || ![item hasPrefix:@"."]) {
                [self _addPropertyResponseForItem:[absolutePath stringByAppendingPathComponent:item] resource:[relativePath stringByAppendingString:item] properties:properties xmlString:xmlString];
            }
        }
    }
    [xmlString appendString:@"</D:multistatus>"];
    
    GCDWebServerDataResponse* response = [GCDWebServerDataResponse responseWithData:(NSData*)[xmlString dataUsingEncoding:NSUTF8StringEncoding]
                                                                        contentType:@"application/xml; charset=\"utf-8\""];
    response.statusCode = kGCDWebServerHTTPStatusCode_MultiStatus;
    return response;
}

- (GCDWebServerResponse*)performLOCK:(GCDWebServerDataRequest*)request {
    if (!_IsMacFinder(request)) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_MethodNotAllowed message:@"LOCK method only allowed for Mac Finder"];
    }
    
    NSString* relativePath = request.path;
    NSString* absolutePath = [_directory stringByAppendingPathComponent:GCDWebServerNormalizePath(relativePath)];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
    }
    
    NSString* depthHeader = [request.headers objectForKey:@"Depth"];
    NSString* timeoutHeader = [request.headers objectForKey:@"Timeout"];
    NSString* scope = nil;
    NSString* type = nil;
    NSString* owner = nil;
    NSString* token = nil;
    BOOL success = YES;
    xmlDocPtr document = xmlReadMemory(request.data.bytes, (int)request.data.length, NULL, NULL, kXMLParseOptions);
    if (document) {
        xmlNodePtr node = _XMLChildWithName(document->children, (const xmlChar*)"lockinfo");
        if (node) {
            xmlNodePtr scopeNode = _XMLChildWithName(node->children, (const xmlChar*)"lockscope");
            if (scopeNode && scopeNode->children && scopeNode->children->name) {
                scope = [NSString stringWithUTF8String:(const char*)scopeNode->children->name];
            }
            xmlNodePtr typeNode = _XMLChildWithName(node->children, (const xmlChar*)"locktype");
            if (typeNode && typeNode->children && typeNode->children->name) {
                type = [NSString stringWithUTF8String:(const char*)typeNode->children->name];
            }
            xmlNodePtr ownerNode = _XMLChildWithName(node->children, (const xmlChar*)"owner");
            if (ownerNode) {
                ownerNode = _XMLChildWithName(ownerNode->children, (const xmlChar*)"href");
                if (ownerNode && ownerNode->children && ownerNode->children->content) {
                    owner = [NSString stringWithUTF8String:(const char*)ownerNode->children->content];
                }
            }
        } else {
            success = NO;
        }
        xmlFreeDoc(document);
    } else {
        success = NO;
    }
    if (!success) {
        NSString* string = [[NSString alloc] initWithData:request.data encoding:NSUTF8StringEncoding];
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"Invalid DAV properties:\n%@", string];
    }
    
    if (![scope isEqualToString:@"exclusive"] || ![type isEqualToString:@"write"] || ![depthHeader isEqualToString:@"0"]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Locking request \"%@/%@/%@\" for \"%@\" is not allowed", scope, type, depthHeader, relativePath];
    }
    
    NSString* itemName = [absolutePath lastPathComponent];
    if ((!_allowHiddenItems && [itemName hasPrefix:@"."]) || (!isDirectory && ![self _checkFileExtension:itemName])) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Locking item name \"%@\" is not allowed", itemName];
    }
    
#ifdef __GCDWEBSERVER_ENABLE_TESTING__
    NSString* lockTokenHeader = [request.headers objectForKey:@"X-GCDWebServer-LockToken"];
    if (lockTokenHeader) {
        token = lockTokenHeader;
    }
#endif
    if (!token) {
        CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
        CFStringRef string = CFUUIDCreateString(kCFAllocatorDefault, uuid);
        token = [NSString stringWithFormat:@"urn:uuid:%@", (__bridge NSString*)string];
        CFRelease(string);
        CFRelease(uuid);
    }
    
    NSMutableString* xmlString = [NSMutableString stringWithString:@"<?xml version=\"1.0\" encoding=\"utf-8\" ?>"];
    [xmlString appendString:@"<D:prop xmlns:D=\"DAV:\">\n"];
    [xmlString appendString:@"<D:lockdiscovery>\n<D:activelock>\n"];
    [xmlString appendFormat:@"<D:locktype><D:%@/></D:locktype>\n", type];
    [xmlString appendFormat:@"<D:lockscope><D:%@/></D:lockscope>\n", scope];
    [xmlString appendFormat:@"<D:depth>%@</D:depth>\n", depthHeader];
    if (owner) {
        [xmlString appendFormat:@"<D:owner><D:href>%@</D:href></D:owner>\n", owner];
    }
    if (timeoutHeader) {
        [xmlString appendFormat:@"<D:timeout>%@</D:timeout>\n", timeoutHeader];
    }
    [xmlString appendFormat:@"<D:locktoken><D:href>%@</D:href></D:locktoken>\n", token];
    NSString* lockroot = [@"http://" stringByAppendingString:[(NSString*)[request.headers objectForKey:@"Host"] stringByAppendingString:[@"/" stringByAppendingString:relativePath]]];
    [xmlString appendFormat:@"<D:lockroot><D:href>%@</D:href></D:lockroot>\n", lockroot];
    [xmlString appendString:@"</D:activelock>\n</D:lockdiscovery>\n"];
    [xmlString appendString:@"</D:prop>"];
    
    [self logVerbose:@"WebDAV pretending to lock \"%@\"", relativePath];
    GCDWebServerDataResponse* response = [GCDWebServerDataResponse responseWithData:(NSData*)[xmlString dataUsingEncoding:NSUTF8StringEncoding]
                                                                        contentType:@"application/xml; charset=\"utf-8\""];
    return response;
}

- (GCDWebServerResponse*)performUNLOCK:(GCDWebServerRequest*)request {
    if (!_IsMacFinder(request)) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_MethodNotAllowed message:@"UNLOCK method only allowed for Mac Finder"];
    }
    
    NSString* relativePath = request.path;
    NSString* absolutePath = [_directory stringByAppendingPathComponent:GCDWebServerNormalizePath(relativePath)];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
    }
    
    NSString* tokenHeader = [request.headers objectForKey:@"Lock-Token"];
    if (!tokenHeader.length) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"Missing 'Lock-Token' header"];
    }
    
    NSString* itemName = [absolutePath lastPathComponent];
    if ((!_allowHiddenItems && [itemName hasPrefix:@"."]) || (!isDirectory && ![self _checkFileExtension:itemName])) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Unlocking item name \"%@\" is not allowed", itemName];
    }
    
    [self logVerbose:@"WebDAV pretending to unlock \"%@\"", relativePath];
    return [GCDWebServerResponse responseWithStatusCode:kGCDWebServerHTTPStatusCode_NoContent];
}

@end

@implementation GCDWebHDServer (UploaderMethods)

- (void)uploaderInitSiteBundle:(NSBundle *)siteBundle {
    if (!siteBundle) return;
    
    GCDWebHDServer* __unsafe_unretained server = self;
    
    // Resource files
    [self addGETHandlerForBasePath:@"/" directoryPath:(NSString*)[siteBundle resourcePath] indexFilename:nil cacheAge:3600 allowRangeRequests:NO];
    
    // Web page
    [self addHandlerForMethod:@"GET"
                         path:@"/"
                 requestClass:[GCDWebServerRequest class]
                 processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                     
#if TARGET_OS_IPHONE
                     NSString* device = [[UIDevice currentDevice] name];
#else
                     NSString* device = CFBridgingRelease(SCDynamicStoreCopyComputerName(NULL, NULL));
#endif
                     NSString* title = server.title;
                     if (title == nil) {
                         title = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
                         if (title == nil) {
                             title = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
                         }
#if !TARGET_OS_IPHONE
                         if (title == nil) {
                             title = [[NSProcessInfo processInfo] processName];
                         }
#endif
                     }
                     NSString* header = server.header;
                     if (header == nil) {
                         header = title;
                     }
                     NSString* prologue = server.prologue;
                     if (prologue == nil) {
                         prologue = [siteBundle localizedStringForKey:@"PROLOGUE" value:@"" table:nil];
                     }
                     NSString* epilogue = server.epilogue;
                     if (epilogue == nil) {
                         epilogue = [siteBundle localizedStringForKey:@"EPILOGUE" value:@"" table:nil];
                     }
                     NSString* footer = server.footer;
                     if (footer == nil) {
                         NSString* name = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
                         if (name == nil) {
                             name = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
                         }
                         NSString* version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
#if !TARGET_OS_IPHONE
                         if (!name && !version) {
                             name = @"OS X";
                             version = [[NSProcessInfo processInfo] operatingSystemVersionString];
                         }
#endif
                         footer = [NSString stringWithFormat:[siteBundle localizedStringForKey:@"FOOTER_FORMAT" value:@"" table:nil], name, version];
                     }
                     return [GCDWebServerDataResponse responseWithHTMLTemplate:(NSString*)[siteBundle pathForResource:@"index" ofType:@"html"]
                                                                     variables:@{
                                                                                 @"device" : device,
                                                                                 @"title" : title,
                                                                                 @"header" : header,
                                                                                 @"prologue" : prologue,
                                                                                 @"epilogue" : epilogue,
                                                                                 @"footer" : footer
                                                                                 }];
                 }];
    
    // File listing
    [self addHandlerForMethod:@"GET"
                         path:@"/list"
                 requestClass:[GCDWebServerRequest class]
                 processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                     return [server listDirectory:request];
                 }];
    
    // File download
    [self addHandlerForMethod:@"GET"
                         path:@"/download"
                 requestClass:[GCDWebServerRequest class]
                 processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                     return [server downloadFile:request];
                 }];
    
    // File upload
    [self addHandlerForMethod:@"POST"
                         path:@"/upload"
                 requestClass:[GCDWebServerMultiPartFormRequest class]
                 processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                     return [server uploadFile:(GCDWebServerMultiPartFormRequest*)request];
                 }];
    
    // File and folder moving
    [self addHandlerForMethod:@"POST"
                         path:@"/move"
                 requestClass:[GCDWebServerURLEncodedFormRequest class]
                 processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                     return [server copyItem:(GCDWebServerURLEncodedFormRequest*)request isMove:YES];
                 }];
    
    // File and folder copying
    [self addHandlerForMethod:@"POST"
                         path:@"/copy"
                 requestClass:[GCDWebServerURLEncodedFormRequest class]
                 processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                     return [server copyItem:(GCDWebServerURLEncodedFormRequest*)request isMove:NO];
                 }];
    
    // File and folder deletion
    [self addHandlerForMethod:@"POST"
                         path:@"/delete"
                 requestClass:[GCDWebServerURLEncodedFormRequest class]
                 processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                     return [server deleteItem:(GCDWebServerURLEncodedFormRequest*)request];
                 }];
    
    // Directory creation
    [self addHandlerForMethod:@"POST"
                         path:@"/create"
                 requestClass:[GCDWebServerURLEncodedFormRequest class]
                 processBlock:^GCDWebServerResponse*(GCDWebServerRequest* request) {
                     return [server createDirectory:(GCDWebServerURLEncodedFormRequest*)request];
                 }];
}

- (NSString*)_uniquePathForPath:(NSString*)path {
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSString* directory = [path stringByDeletingLastPathComponent];
        NSString* file = [path lastPathComponent];
        NSString* base = [file stringByDeletingPathExtension];
        NSString* extension = [file pathExtension];
        int retries = 0;
        do {
            if (extension.length) {
                path = [directory stringByAppendingPathComponent:(NSString*)[[base stringByAppendingFormat:@" (%i)", ++retries] stringByAppendingPathExtension:extension]];
            } else {
                path = [directory stringByAppendingPathComponent:[base stringByAppendingFormat:@" (%i)", ++retries]];
            }
        } while ([[NSFileManager defaultManager] fileExistsAtPath:path]);
    }
    return path;
}

- (GCDWebServerResponse*)listDirectory:(GCDWebServerRequest*)request {
    NSString* relativePath = [[request query] objectForKey:@"path"];
    NSString* absolutePath = [_directory stringByAppendingPathComponent:GCDWebServerNormalizePath(relativePath)];
    BOOL isDirectory = NO;
    if (!absolutePath || ![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
    }
    if (!isDirectory) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"\"%@\" is not a directory", relativePath];
    }
    
    NSString* directoryName = [absolutePath lastPathComponent];
    if (!_allowHiddenItems && [directoryName hasPrefix:@"."]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Listing directory name \"%@\" is not allowed", directoryName];
    }
    
    NSError* error = nil;
    NSArray* contents = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:absolutePath error:&error] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    if (contents == nil) {
        return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed listing directory \"%@\"", relativePath];
    }
    
    NSMutableArray* array = [NSMutableArray array];
    for (NSString* item in [contents sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        if (_allowHiddenItems || ![item hasPrefix:@"."]) {
            NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[absolutePath stringByAppendingPathComponent:item] error:NULL];
            NSString* type = [attributes objectForKey:NSFileType];
            if ([type isEqualToString:NSFileTypeRegular] && [self _checkFileExtension:item]) {
                [array addObject:@{
                                   @"path" : [relativePath stringByAppendingPathComponent:item],
                                   @"name" : item,
                                   @"size" : (NSNumber*)[attributes objectForKey:NSFileSize]
                                   }];
            } else if ([type isEqualToString:NSFileTypeDirectory]) {
                [array addObject:@{
                                   @"path" : [[relativePath stringByAppendingPathComponent:item] stringByAppendingString:@"/"],
                                   @"name" : item
                                   }];
            }
        }
    }
    return [GCDWebServerDataResponse responseWithJSONObject:array];
}

- (GCDWebServerResponse*)downloadFile:(GCDWebServerRequest*)request {
    NSString* relativePath = [[request query] objectForKey:@"path"];
    NSString* absolutePath = [_directory stringByAppendingPathComponent:GCDWebServerNormalizePath(relativePath)];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
    }
    if (isDirectory) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"\"%@\" is a directory", relativePath];
    }
    
    NSString* fileName = [absolutePath lastPathComponent];
    if (([fileName hasPrefix:@"."] && !_allowHiddenItems) || ![self _checkFileExtension:fileName]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Downlading file name \"%@\" is not allowed", fileName];
    }
    
    if ([self.delegate respondsToSelector:@selector(hdServer:didDownloadFileAtPath:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate hdServer:self didDownloadFileAtPath:absolutePath];
        });
    }
    return [GCDWebServerFileResponse responseWithFile:absolutePath isAttachment:YES];
}

- (GCDWebServerResponse*)uploadFile:(GCDWebServerMultiPartFormRequest*)request {
    NSRange range = [[request.headers objectForKey:@"Accept"] rangeOfString:@"application/json" options:NSCaseInsensitiveSearch];
    NSString* contentType = (range.location != NSNotFound ? @"application/json" : @"text/plain; charset=utf-8");  // Required when using iFrame transport (see https://github.com/blueimp/jQuery-File-Upload/wiki/Setup)
    
    GCDWebServerMultiPartFile* file = [request firstFileForControlName:@"files[]"];
    if ((!_allowHiddenItems && [file.fileName hasPrefix:@"."]) || ![self _checkFileExtension:file.fileName]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Uploaded file name \"%@\" is not allowed", file.fileName];
    }
    NSString* relativePath = [[request firstArgumentForControlName:@"path"] string];
    NSString* absolutePath = [self _uniquePathForPath:[[_directory stringByAppendingPathComponent:GCDWebServerNormalizePath(relativePath)] stringByAppendingPathComponent:file.fileName]];
    
    if (![self shouldUploadFileAtPath:absolutePath withTemporaryFile:file.temporaryPath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Uploading file \"%@\" to \"%@\" is not permitted", file.fileName, relativePath];
    }
    
    NSError* error = nil;
    if (![[NSFileManager defaultManager] moveItemAtPath:file.temporaryPath toPath:absolutePath error:&error]) {
        return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed moving uploaded file to \"%@\"", relativePath];
    }
    
    if ([self.delegate respondsToSelector:@selector(hdServer:didUploadFileAtPath:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate hdServer:self didUploadFileAtPath:absolutePath];
        });
    }
    return [GCDWebServerDataResponse responseWithJSONObject:@{} contentType:contentType];
}

- (GCDWebServerResponse*)copyItem:(GCDWebServerURLEncodedFormRequest*)request isMove:(BOOL)isMove {
    NSString* oldRelativePath = [request.arguments objectForKey:@"oldPath"];
    NSString* oldAbsolutePath = [_directory stringByAppendingPathComponent:GCDWebServerNormalizePath(oldRelativePath)];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:oldAbsolutePath isDirectory:&isDirectory]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", oldRelativePath];
    }
    
    NSString* newRelativePath = [request.arguments objectForKey:@"newPath"];
    NSString* newAbsolutePath = [self _uniquePathForPath:[_directory stringByAppendingPathComponent:GCDWebServerNormalizePath(newRelativePath)]];
    
    NSString* itemName = [newAbsolutePath lastPathComponent];
    if ((!_allowHiddenItems && [itemName hasPrefix:@"."]) || (!isDirectory && ![self _checkFileExtension:itemName])) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Moving to item name \"%@\" is not allowed", itemName];
    }
    
    if (isMove) {
        if (![self shouldMoveItemFromPath:oldAbsolutePath toPath:newAbsolutePath]) {
            return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Moving \"%@\" to \"%@\" is not permitted", oldRelativePath, newRelativePath];
        }
    } else {
        if (![self shouldCopyItemFromPath:oldAbsolutePath toPath:newAbsolutePath]) {
            return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Copying \"%@\" to \"%@\" is not permitted", oldRelativePath, newRelativePath];
        }
    }
    
    
    
    NSError* error = nil;
    if (isMove) {
        if (![[NSFileManager defaultManager] moveItemAtPath:oldAbsolutePath toPath:newAbsolutePath error:&error]) {
            return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed moving \"%@\" to \"%@\"", oldRelativePath, newRelativePath];
        }
    } else {
        if (![[NSFileManager defaultManager] copyItemAtPath:oldAbsolutePath toPath:newAbsolutePath error:&error]) {
            return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed copying \"%@\" to \"%@\"", oldRelativePath, newRelativePath];
        }
    }
    
    if (isMove) {
        if ([self.delegate respondsToSelector:@selector(hdServer:didMoveItemFromPath:toPath:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate hdServer:self didMoveItemFromPath:oldAbsolutePath toPath:newAbsolutePath];
            });
        }
    } else {
        if ([self.delegate respondsToSelector:@selector(hdServer:didMoveItemFromPath:toPath:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate hdServer:self didCopyItemFromPath:oldAbsolutePath toPath:newAbsolutePath];
            });
        }
    }
    
    return [GCDWebServerDataResponse responseWithJSONObject:@{}];
}

- (GCDWebServerResponse*)deleteItem:(GCDWebServerURLEncodedFormRequest*)request {
    NSString* relativePath = [request.arguments objectForKey:@"path"];
    NSString* absolutePath = [_directory stringByAppendingPathComponent:GCDWebServerNormalizePath(relativePath)];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
    }
    
    NSString* itemName = [absolutePath lastPathComponent];
    if (([itemName hasPrefix:@"."] && !_allowHiddenItems) || (!isDirectory && ![self _checkFileExtension:itemName])) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Deleting item name \"%@\" is not allowed", itemName];
    }
    
    if (![self shouldDeleteItemAtPath:absolutePath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Deleting \"%@\" is not permitted", relativePath];
    }
    
    NSError* error = nil;
    if (![[NSFileManager defaultManager] removeItemAtPath:absolutePath error:&error]) {
        return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed deleting \"%@\"", relativePath];
    }
    
    if ([self.delegate respondsToSelector:@selector(hdServer:didDeleteItemAtPath:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate hdServer:self didDeleteItemAtPath:absolutePath];
        });
    }
    return [GCDWebServerDataResponse responseWithJSONObject:@{}];
}

- (GCDWebServerResponse*)createDirectory:(GCDWebServerURLEncodedFormRequest*)request {
    NSString* relativePath = [request.arguments objectForKey:@"path"];
    NSString* absolutePath = [self _uniquePathForPath:[_directory stringByAppendingPathComponent:GCDWebServerNormalizePath(relativePath)]];
    
    NSString* directoryName = [absolutePath lastPathComponent];
    if (!_allowHiddenItems && [directoryName hasPrefix:@"."]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Creating directory name \"%@\" is not allowed", directoryName];
    }
    
    if (![self shouldCreateDirectoryAtPath:absolutePath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Creating directory \"%@\" is not permitted", relativePath];
    }
    
    NSError* error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:absolutePath withIntermediateDirectories:NO attributes:nil error:&error]) {
        return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed creating directory \"%@\"", relativePath];
    }
    
    if ([self.delegate respondsToSelector:@selector(hdServer:didCreateDirectoryAtPath:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate hdServer:self didCreateDirectoryAtPath:absolutePath];
        });
    }
    return [GCDWebServerDataResponse responseWithJSONObject:@{}];
}

@end

@implementation GCDWebHDServer (Subclassing)

- (BOOL)shouldUploadFileAtPath:(NSString*)path withTemporaryFile:(NSString*)tempPath {
    return YES;
}

- (BOOL)shouldMoveItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath {
    return YES;
}

- (BOOL)shouldCopyItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath {
    return YES;
}

- (BOOL)shouldDeleteItemAtPath:(NSString*)path {
    return YES;
}

- (BOOL)shouldCreateDirectoryAtPath:(NSString*)path {
    return YES;
}

@end
