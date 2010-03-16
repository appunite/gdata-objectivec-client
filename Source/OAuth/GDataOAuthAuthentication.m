/* Copyright (c) 2010 Google Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#if !GDATA_REQUIRE_SERVICE_INCLUDES || GDATA_INCLUDE_OAUTH

#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5

// HMAC digest
#import <CommonCrypto/CommonHMAC.h>

// RSA SHA-1 signing
#if GDATA_OAUTH_SUPPORTS_RSASHA1_SIGNING
#include <openssl/sha.h>
#include <openssl/pem.h>
#include <openssl/err.h>
#endif

#define GDATAOAUTHAUTHENTICATION_DEFINE_GLOBALS 1
#import "GDataOAuthAuthentication.h"

// standard OAuth keys
static NSString *const kOAuthConsumerKey          = @"oauth_consumer_key";
static NSString *const kOAuthTokenKey             = @"oauth_token";
static NSString *const kOAuthCallbackKey          = @"oauth_callback";
static NSString *const kOAuthCallbackConfirmedKey = @"oauth_callback_confirmed";
static NSString *const kOAuthTokenSecretKey       = @"oauth_token_secret";
static NSString *const kOAuthSignatureMethodKey   = @"oauth_signature_method";
static NSString *const kOAuthSignatureKey         = @"oauth_signature";
static NSString *const kOAuthTimestampKey         = @"oauth_timestamp";
static NSString *const kOAuthNonceKey             = @"oauth_nonce";
static NSString *const kOAuthVerifierKey          = @"oauth_verifier";
static NSString *const kOAuthVersionKey           = @"oauth_version";

// GetRequestToken extensions
static NSString *const kOAuthDisplayNameKey       = @"xoauth_displayname";
static NSString *const kOAuthScopeKey             = @"scope";

// AuthorizeToken extensions
static NSString *const kOAuthHostedDomainKey      = @"hd";
static NSString *const kOAuthLanguageKey          = @"hl";
static NSString *const kOAuthMobileKey            = @"btmpl";

// additional persistent keys
static NSString *const kServiceProviderKey        = @"serviceProvider";

@interface GDataOAuthAuthentication (PrivateMethods)

- (void)addAuthorizationHeaderToRequest:(NSMutableURLRequest *)request
                                forKeys:(NSArray *)keys;
- (void)addParamsForKeys:(NSArray *)keys
               toRequest:(NSMutableURLRequest *)request;

- (NSString *)normalizedRequestURLStringForRequest:(NSURLRequest *)request;

- (NSString *)paramStringForParams:(NSArray *)params
                            joiner:(NSString *)joiner
                       shouldQuote:(BOOL)shouldQuote
                        shouldSort:(BOOL)shouldSort;

- (NSString *)signatureForParams:(NSMutableArray *)params
                         request:(NSURLRequest *)request;

#if GDATA_OAUTH_SUPPORTS_RSASHA1_SIGNING
+ (NSString *)signedRSASHA1HashForString:(NSString *)source
                     privateKeyPEMString:(NSString *)key;
#endif

+ (NSString *)HMACSHA1HashForKey:(NSString *)key body:(NSString *)body;
@end

// OAuthParameter is a local class that exists just to make it easier to
// sort descriptor pairs by name and encoded value
@interface OAuthParameter : NSObject {
 @private
  NSString *name_;
  NSString *value_;
}

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *value;

+ (OAuthParameter *)parameterWithName:(NSString *)name
                                value:(NSString *)value;

+ (NSArray *)sortDescriptors;
@end

@implementation GDataOAuthAuthentication

@synthesize realm = realm_;
@synthesize privateKey = privateKey_;
@synthesize serviceProvider = serviceProvider_;
@synthesize userData = userData_;

// create an authentication object, with hardcoded values for installed apps
// of HMAC-SHA1 as signature method, and "anonymous" as the consumer key and
// consumer secret (private key)
+ (GDataOAuthAuthentication *)authForInstalledApp {
  // installed apps have fixed parameters
  return [[[self alloc] initWithSignatureMethod:@"HMAC-SHA1"
                                    consumerKey:@"anonymous"
                                     privateKey:@"anonymous"] autorelease];
}

// create an authentication object, specifying the consumer key and
// private key (both "anonymous" for installed apps) and the signature method
// ("HMAC-SHA1" for installed apps)
//
// for signature method "RSA-SHA1", a proper consumer key and private key
// must be supplied
- (id)initWithSignatureMethod:(NSString *)signatureMethod
                  consumerKey:(NSString *)consumerKey
                   privateKey:(NSString *)privateKey {

  self = [super init];
  if (self != nil) {
    paramValues_ = [[NSMutableDictionary alloc] init];

    [self setConsumerKey:consumerKey];
    [self setSignatureMethod:signatureMethod];
    [self setPrivateKey:privateKey];

    [self setVersion:@"1.0"];
  }
  return self;
}

- (void)dealloc {
  [paramValues_ release];
  [realm_ release];
  [privateKey_ release];
  [serviceProvider_ release];
  [timestamp_ release];
  [nonce_ release];
  [userData_ release];
  [super dealloc];
}

#pragma mark -

- (NSMutableArray *)paramsForKeys:(NSArray *)keys
                          request:(NSURLRequest *)request {
  // this is the magic routine that collects the parameters for the specified
  // keys, and signs them
  NSMutableArray *params = [NSMutableArray array];

  for (NSString *key in keys) {
    NSString *value = [paramValues_ objectForKey:key];
    if ([value length] > 0) {
      [params addObject:[OAuthParameter parameterWithName:key
                                                    value:value]];
    }
  }

  // nonce and timestamp are generated on-the-fly by the getters
  if ([keys containsObject:kOAuthNonceKey]) {
    NSString *nonce = [self nonce];
    [params addObject:[OAuthParameter parameterWithName:kOAuthNonceKey
                                                  value:nonce]];
  }

  if ([keys containsObject:kOAuthTimestampKey]) {
    NSString *timestamp = [self timestamp];
    [params addObject:[OAuthParameter parameterWithName:kOAuthTimestampKey
                                                  value:timestamp]];
  }

  // finally, compute the signature, if requested; the params
  // must be complete for this
  if ([keys containsObject:kOAuthSignatureKey]) {
    NSString *signature = [self signatureForParams:params
                                           request:request];
    [params addObject:[OAuthParameter parameterWithName:kOAuthSignatureKey
                                                  value:signature]];
  }

  return params;
}

- (void)addQueryFromRequest:(NSURLRequest *)request
                   toParams:(NSMutableArray *)array {
  // make param objects from the request's query parameters, and add them
  // to the supplied array

  // look for a query like foo=cat&bar=dog
  NSString *query = [[request URL] query];
  if ([query length] > 0) {
    // remove percent-escapes from the query components; they'll be
    // added back by OAuthParameter
    query = [[self class] unencodedOAuthParameterForString:query];

    // separate and step through the assignments
    NSArray *items = [query componentsSeparatedByString:@"&"];

    for (NSString *item in items) {
      NSArray *components = [item componentsSeparatedByString:@"="];
      if ([components count] == 2) {
        NSString *name = [components objectAtIndex:0];
        NSString *value = [components objectAtIndex:1];

        [array addObject:[OAuthParameter parameterWithName:name
                                                     value:value]];
      }
    }
  }
}

- (NSString *)signatureForParams:(NSMutableArray *)params
                         request:(NSURLRequest *)request {
  // construct signature base string per
  // http://oauth.net/core/1.0a/#signing_process
  NSString *requestURLStr = [self normalizedRequestURLStringForRequest:request];
  NSString *method = [[request HTTPMethod] uppercaseString];
  if ([method length] == 0) {
    method = @"GET";
  }

  // the signature params exclude the signature
  NSMutableArray *signatureParams = [NSMutableArray arrayWithArray:params];

  // add request query parameters
  [self addQueryFromRequest:request toParams:signatureParams];

  NSString *paramStr = [self paramStringForParams:signatureParams
                                           joiner:@"&"
                                      shouldQuote:NO
                                       shouldSort:YES];

  // the base string includes the method, normalized request URL, and params
  NSString *requestURLStrEnc = [[self class] encodedOAuthParameterForString:requestURLStr];
  NSString *paramStrEnc = [[self class] encodedOAuthParameterForString:paramStr];

  NSString *sigBaseString = [NSString stringWithFormat:@"%@&%@&%@",
                             method, requestURLStrEnc, paramStrEnc];

  NSString *privateKey = [self privateKey];
  NSString *signatureMethod = [self signatureMethod];
  NSString *signature = nil;

#if GDATA_DEBUG_OAUTH_SIGNING
  NSLog(@"signing request: %@\n", request);
  NSLog(@"signing params: %@\n", params);
#endif

  if ([signatureMethod isEqual:kGDataOAuthSignatureMethodHMAC_SHA1]) {
    NSString *tokenSecret = [self tokenSecret];
    NSString *encodedTokenSecret = [[self class] encodedOAuthParameterForString:tokenSecret];

    NSString *secrets = [NSString stringWithFormat:@"%@&%@",
                         privateKey ? privateKey : @"",
                         encodedTokenSecret ? encodedTokenSecret : @""];
    signature = [[self class] HMACSHA1HashForKey:secrets
                                            body:sigBaseString];
#if GDATA_DEBUG_OAUTH_SIGNING
    NSLog(@"hashing: %@", secrets);
    NSLog(@"base string: %@", sigBaseString);
    NSLog(@"signature: %@", signature);
#endif
  }

#if GDATA_OAUTH_SUPPORTS_RSASHA1_SIGNING
  else if ([signatureMethod isEqual:kGDataOAuthSignatureMethodRSA_SHA1]) {
    signature = [[self class] signedRSASHA1HashForString:sigBaseString
                                     privateKeyPEMString:privateKey];
  }
#endif

  return signature;
}

- (NSString *)paramStringForParams:(NSArray *)params
                            joiner:(NSString *)joiner
                       shouldQuote:(BOOL)shouldQuote
                        shouldSort:(BOOL)shouldSort {
  // create a string by joining the supplied param objects

  if (shouldSort) {
    // sort params by name and value
    NSArray *descs = [OAuthParameter sortDescriptors];
    params = [params sortedArrayUsingDescriptors:descs];
  }

  // make an array of the encoded name=value items
  NSArray *encodedArray;
  if (shouldQuote) {
    encodedArray = [params valueForKey:@"quotedEncodedParam"];
  } else {
    encodedArray = [params valueForKey:@"encodedParam"];
  }

  // join the items
  NSString *result = [encodedArray componentsJoinedByString:joiner];
  return result;
}

- (NSString *)normalizedRequestURLStringForRequest:(NSURLRequest *)request {
  // http://oauth.net/core/1.0a/#anchor13

  NSURL *url = [[request URL] absoluteURL];

  NSString *scheme = [[url scheme] lowercaseString];
  NSString *host = [[url host] lowercaseString];
  int port = [[url port] intValue];
  NSString *path = [url path];

  // NSURL's path changes %40 to @, which isn't what we want in the
  // normalized string
  //
  // Open question: should this more generally percent-encode the path?
  path = [path stringByReplacingOccurrencesOfString:@"@"
                                         withString:@"%40"];

  // include only non-standard ports for http or https
  NSString *portStr;
  if (port == 0
      || ([scheme isEqual:@"http"] && port == 80)
      || ([scheme isEqual:@"https"] && port == 443)) {
    portStr = @"";
  } else {
    portStr = [NSString stringWithFormat:@":%u", port];
  }

  if ([path length] == 0) {
    path = @"/";
  }

  NSString *result = [NSString stringWithFormat:@"%@://%@%@%@",
                      scheme, host, portStr, path];
  return result;
}

+ (NSArray *)tokenRequestKeys {
  // keys for obtaining a request token, http://oauth.net/core/1.0a/#auth_step1
  NSArray *keys = [NSArray arrayWithObjects:
                   kOAuthConsumerKey,
                   kOAuthSignatureMethodKey,
                   kOAuthSignatureKey,
                   kOAuthTimestampKey,
                   kOAuthNonceKey,
                   kOAuthVersionKey,
                   kOAuthCallbackKey,
                   // extensions
                   kOAuthDisplayNameKey,
                   kOAuthScopeKey,
                   nil];
  return keys;
}

+ (NSArray *)tokenAuthorizeKeys {
  // keys for opening the authorize page, http://oauth.net/core/1.0a/#auth_step2
  NSArray *keys = [NSArray arrayWithObjects:
                   kOAuthTokenKey,
                   // extensions
                   kOAuthHostedDomainKey,
                   kOAuthLanguageKey,
                   kOAuthMobileKey,
                   nil];
  return keys;
}

+ (NSArray *)tokenAccessKeys {
  // keys for obtaining an access token, http://oauth.net/core/1.0a/#auth_step3
  NSArray *keys = [NSArray arrayWithObjects:
                   kOAuthConsumerKey,
                   kOAuthTokenKey,
                   kOAuthSignatureMethodKey,
                   kOAuthSignatureKey,
                   kOAuthTimestampKey,
                   kOAuthNonceKey,
                   kOAuthVersionKey,
                   kOAuthVerifierKey, nil];
  return keys;
}

+ (NSArray *)tokenResourceKeys {
  // keys for accessing a protected resource,
  // http://oauth.net/core/1.0a/#anchor12
  NSArray *keys = [NSArray arrayWithObjects:
                   kOAuthConsumerKey,
                   kOAuthTokenKey,
                   kOAuthSignatureMethodKey,
                   kOAuthSignatureKey,
                   kOAuthTimestampKey,
                   kOAuthNonceKey,
                   kOAuthVersionKey, nil];
  return keys;
}

#pragma mark -

- (void)setKeysForResponseDictionary:(NSDictionary *)dict {
  NSString *token = [dict objectForKey:kOAuthTokenKey];
  if (token) {
    NSString *plainToken = [[self class] unencodedOAuthParameterForString:token];
    [self setToken:plainToken];
  }

  NSString *secret = [dict objectForKey:kOAuthTokenSecretKey];
  if (secret) {
    NSString *plainSecret = [[self class] unencodedOAuthParameterForString:secret];
    [self setTokenSecret:plainSecret];
  }

  NSString *callbackConfirmed = [dict objectForKey:kOAuthCallbackConfirmedKey];
  if (callbackConfirmed) {
    [self setCallbackConfirmed:callbackConfirmed];
  }

  NSString *verifier = [dict objectForKey:kOAuthVerifierKey];
  if (verifier) {
    NSString *plainVerifier = [[self class] unencodedOAuthParameterForString:verifier];
    [self setVerifier:plainVerifier];
  }

  NSString *provider = [dict objectForKey:kServiceProviderKey];
  if (provider) {
    [self setServiceProvider:provider];
  }
}

- (void)setKeysForResponseData:(NSData *)data {
  NSDictionary *dict = [[self class] dictionaryWithResponseData:data];
  [self setKeysForResponseDictionary:dict];
}

- (void)setKeysForResponseString:(NSString *)str {
  NSDictionary *dict = [[self class] dictionaryWithResponseString:str];
  [self setKeysForResponseDictionary:dict];
}

#pragma mark -

//
// Methods for adding OAuth parameters either to queries or as a request header
//

- (void)addRequestTokenHeaderToRequest:(NSMutableURLRequest *)request {
  // add request token params to the request's header
  NSArray *keys = [[self class] tokenRequestKeys];
  [self addAuthorizationHeaderToRequest:request
                                forKeys:keys];
}

- (void)addRequestTokenParamsToRequest:(NSMutableURLRequest *)request {
  // add request token params to the request URL (not to the header)
  NSArray *keys = [[self class] tokenRequestKeys];
  [self addParamsForKeys:keys toRequest:request];
}

- (void)addAuthorizeTokenHeaderToRequest:(NSMutableURLRequest *)request {
  // add authorize token params to the request's header
  NSArray *keys = [[self class] tokenAuthorizeKeys];
  [self addAuthorizationHeaderToRequest:request
                                forKeys:keys];
}

- (void)addAuthorizeTokenParamsToRequest:(NSMutableURLRequest *)request {
  // add authorize token params to the request URL (not to the header)
  NSArray *keys = [[self class] tokenAuthorizeKeys];
  [self addParamsForKeys:keys toRequest:request];
}

- (void)addAccessTokenHeaderToRequest:(NSMutableURLRequest *)request {
  // add access token params to the request's header
  NSArray *keys = [[self class] tokenAccessKeys];
  [self addAuthorizationHeaderToRequest:request
                                forKeys:keys];
}

- (void)addAccessTokenParamsToRequest:(NSMutableURLRequest *)request {
  // add access token params to the request URL (not to the header)
  NSArray *keys = [[self class] tokenAccessKeys];
  [self addParamsForKeys:keys toRequest:request];
}

- (void)addResourceTokenHeaderToRequest:(NSMutableURLRequest *)request {
  // add resource access token params to the request's header
  NSArray *keys = [[self class] tokenResourceKeys];
  [self addAuthorizationHeaderToRequest:request
                                forKeys:keys];
}

- (void)addResourceTokenParamsToRequest:(NSMutableURLRequest *)request {
  // add resource access token params to the request URL (not to the header)
  NSArray *keys = [[self class] tokenResourceKeys];
  [self addParamsForKeys:keys toRequest:request];
}

//
// underlying methods for constructing query parameters or request headers
//

- (void)addParams:(NSArray *)params toRequest:(NSMutableURLRequest *)request {
  NSString *paramStr = [self paramStringForParams:params
                                           joiner:@"&"
                                      shouldQuote:NO
                                       shouldSort:NO];
  NSURL *oldURL = [request URL];
  NSString *query = [oldURL query];
  if ([query length] > 0) {
    query = [query stringByAppendingFormat:@"&%@", paramStr];
  } else {
    query = paramStr;
  }

  NSString *portStr = ([oldURL port] != nil ? [[oldURL port] stringValue] : @"");

  NSString *qMark = [query length] > 0 ? @"?" : @"";
  NSString *newURLStr = [NSString stringWithFormat:@"%@://%@%@%@%@%@",
                         [oldURL scheme], [oldURL host], portStr,
                         [oldURL path], qMark, query];

  [request setURL:[NSURL URLWithString:newURLStr]];
}

- (void)addParamsForKeys:(NSArray *)keys toRequest:(NSMutableURLRequest *)request {
  // For the specified keys, add the keys and values to the request URL.

  NSMutableArray *params = [self paramsForKeys:keys request:request];
  [self addParams:params toRequest:request];
}

- (void)addAuthorizationHeaderToRequest:(NSMutableURLRequest *)request
                                forKeys:(NSArray *)keys {
  // make all the parameters, including a signature for all
  NSMutableArray *params = [self paramsForKeys:keys request:request];

  // split the params into "oauth_" params which go into the Auth header
  // and others which get added to the query
  NSMutableArray *oauthParams = [NSMutableArray array];
  NSMutableArray *extendedParams = [NSMutableArray array];

  for (OAuthParameter *param in params) {
    NSString *name = [param name];
    BOOL hasPrefix = [name hasPrefix:@"oauth_"];
    if (hasPrefix) {
      [oauthParams addObject:param];
    } else {
      [extendedParams addObject:param];
    }
  }

  NSString *paramStr = [self paramStringForParams:oauthParams
                                           joiner:@", "
                                      shouldQuote:YES
                                       shouldSort:NO];

  // include the realm string, if any, in the auth header
  // http://oauth.net/core/1.0a/#auth_header
  NSString *realmParam = @"";
  NSString *realm = [self realm];
  if ([realm length] > 0) {
    NSString *encodedVal = [[self class] encodedOAuthParameterForString:realm];
    realmParam = [NSString stringWithFormat:@"realm=\"%@\", ", encodedVal];
  }

  // add the parameters for "oauth_" keys and the realm
  // to the authorization header
  NSString *authHdr = [NSString stringWithFormat:@"OAuth %@%@",
                      realmParam, paramStr];
  [request addValue:authHdr forHTTPHeaderField:@"Authorization"];

  // add any other params as URL query parameters
  if ([extendedParams count] > 0) {
    [self addParams:extendedParams toRequest:request];
  }

#if GDATA_DEBUG_OAUTH_SIGNING
  NSLog(@"adding auth header: %@", authHdr);
  NSLog(@"final request: %@", request);
#endif
}

// general entry point for GData library
- (BOOL)authorizeRequest:(NSMutableURLRequest *)request {
  NSString *token = [self token];
  if ([token length] == 0) {
    return NO;
  } else {
    [self addResourceTokenHeaderToRequest:request];
    return YES;
  }
}

- (BOOL)canAuthorize {
  // this method's is just a higher-level version of hasAccessToken
  return [self hasAccessToken];
}

#pragma mark -

// this returns a "response string" that can be passed later to
// setKeysForResponseString: to reuse an old access token in a new auth object
- (NSString *)persistenceResponseString {
  NSString *accessToken = [self accessToken];
  NSString *tokenSecret = [self tokenSecret];

  NSString *encodedToken = [GDataOAuthAuthentication encodedOAuthParameterForString:accessToken];
  NSString *encodedTokenSecret = [GDataOAuthAuthentication encodedOAuthParameterForString:tokenSecret];

  NSString *responseStr = [NSString stringWithFormat:@"%@=%@&%@=%@",
                           kOAuthTokenKey, encodedToken,
                           kOAuthTokenSecretKey, encodedTokenSecret];

  // we save the service provider too since knowing this is a Google auth token
  // will let us know later that it can be revoked via AuthSubRevokeToken
  NSString *provider = [self serviceProvider];
  if ([provider length] > 0) {
    responseStr = [responseStr stringByAppendingFormat:@"&%@=%@",
                   kServiceProviderKey, provider];
  }

  return responseStr;
}

#pragma mark Accessors

- (NSString *)scope {
  return [paramValues_ objectForKey:kOAuthScopeKey];
}

- (void)setScope:(NSString *)str {
  [paramValues_ setValue:str
                  forKey:kOAuthScopeKey];
}

- (NSString *)displayName {
  return [paramValues_ objectForKey:kOAuthDisplayNameKey];
}

- (void)setDisplayName:(NSString *)str {
  [paramValues_ setValue:str
                  forKey:kOAuthDisplayNameKey];
}

- (NSString *)hostedDomain {
  return [paramValues_ objectForKey:kOAuthHostedDomainKey];
}

- (void)setHostedDomain:(NSString *)str {
  [paramValues_ setValue:str
                  forKey:kOAuthHostedDomainKey];
}

- (NSString *)language {
  return [paramValues_ objectForKey:kOAuthLanguageKey];
}

- (void)setLanguage:(NSString *)str {
  [paramValues_ setValue:str
                  forKey:kOAuthLanguageKey];
}

- (NSString *)mobile {
  return [paramValues_ objectForKey:kOAuthMobileKey];
}

- (void)setMobile:(NSString *)str {
  [paramValues_ setValue:str
                  forKey:kOAuthMobileKey];
}

- (NSString *)signatureMethod {
  return [paramValues_ objectForKey:kOAuthSignatureMethodKey];
}

- (void)setSignatureMethod:(NSString *)str {
  [paramValues_ setValue:str
                  forKey:kOAuthSignatureMethodKey];
}

- (NSString *)consumerKey {
  return [paramValues_ objectForKey:kOAuthConsumerKey];
}

- (void)setConsumerKey:(NSString *)str {
  [paramValues_ setValue:str
                  forKey:kOAuthConsumerKey];
}

- (NSString *)token {
  return [paramValues_ objectForKey:kOAuthTokenKey];
}

- (void)setToken:(NSString *)str {
  [paramValues_ setValue:str
                  forKey:kOAuthTokenKey];
}

- (NSString *)callback {
  return [paramValues_ objectForKey:kOAuthCallbackKey];
}


- (void)setCallback:(NSString *)str {
  [paramValues_ setValue:str
                  forKey:kOAuthCallbackKey];
}

- (NSString *)verifier {
  return [paramValues_ objectForKey:kOAuthVerifierKey];
}

- (void)setVerifier:(NSString *)str {
  [paramValues_ setValue:str
                  forKey:kOAuthVerifierKey];
}

- (NSString *)tokenSecret {
  return [paramValues_ objectForKey:kOAuthTokenSecretKey];
}

- (void)setTokenSecret:(NSString *)str {
  [paramValues_ setValue:str
                  forKey:kOAuthTokenSecretKey];
}

- (NSString *)callbackConfirmed {
  return [paramValues_ objectForKey:kOAuthCallbackConfirmedKey];
}

- (void)setCallbackConfirmed:(NSString *)str {
  [paramValues_ setValue:str
                  forKey:kOAuthCallbackConfirmedKey];
}

- (NSString *)version {
  return [paramValues_ objectForKey:kOAuthVersionKey];
}

- (void)setVersion:(NSString *)str {
  [paramValues_ setValue:str
                  forKey:kOAuthVersionKey];
}

- (NSString *)timestamp {

  if (timestamp_) return timestamp_; // for testing only

  NSTimeInterval timeInterval = [[NSDate date] timeIntervalSince1970];
  unsigned long long timestampVal = (unsigned long long) timeInterval;
  NSString *timestamp = [NSString stringWithFormat:@"%qu", timestampVal];
  return timestamp;
}

- (void)setTimestamp:(NSString *)str {
  // set a fixed timestamp, for testing only
  [timestamp_ autorelease];
  timestamp_ = [str copy];
}

- (NSString *)nonce {

  if (nonce_) return nonce_; // for testing only

  // make a random 64-bit number
  unsigned long long nonceVal = ((unsigned long long) arc4random()) << 32
  | (unsigned long long) arc4random();

  NSString *nonce = [NSString stringWithFormat:@"%qu", nonceVal];
  return nonce;
}

- (void)setNonce:(NSString *)str {
  // set a fixed nonce, for testing only
  [nonce_ autorelease];
  nonce_ = [str copy];
}

// to avoid the ambiguity between request and access flavors of tokens,
// we'll provide accessors solely for access tokens
- (BOOL)hasAccessToken {
  return hasAccessToken_ && ([[self token] length] > 0);
}

- (void)setHasAccessToken:(BOOL)flag {
  hasAccessToken_ = flag;
}

- (NSString *)accessToken {
  if (hasAccessToken_) {
    return [self token];
  } else {
    return nil;
  }
}

- (void)setAccessToken:(NSString *)str {
  [self setToken:str];
  [self setHasAccessToken:YES];
}

#pragma mark Utility Routines

+ (NSString *)encodedOAuthParameterForString:(NSString *)str {
  // http://oauth.net/core/1.0a/#encoding_parameters

  CFStringRef originalString = (CFStringRef) str;

  CFStringRef leaveUnescaped = CFSTR("ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                                     "abcdefghijklmnopqrstuvwxyz"
                                     "-._~");
  CFStringRef forceEscaped =  CFSTR("%!$&'()*+,/:;=?@");

  CFStringRef escapedStr = NULL;
  if (str) {
    escapedStr = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                         originalString,
                                                         leaveUnescaped,
                                                         forceEscaped,
                                                         kCFStringEncodingUTF8);
    [(id)CFMakeCollectable(escapedStr) autorelease];
  }

  return (NSString *)escapedStr;
}

+ (NSString *)unencodedOAuthParameterForString:(NSString *)str {
  NSString *plainStr = [str stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
  return plainStr;
}

+ (NSDictionary *)dictionaryWithResponseString:(NSString *)responseStr {
  // build a dictionary from a response string of the form
  //  "foo=cat&bar=dog"

  if (responseStr == nil) return nil;

  NSArray *items = [responseStr componentsSeparatedByString:@"&"];

  NSMutableDictionary *responseDict = [NSMutableDictionary dictionary];

  for (NSString *item in items) {
    NSScanner *scanner = [NSScanner scannerWithString:item];
    NSString *key;
    NSString *value;

    [scanner setCharactersToBeSkipped:nil];
    if ([scanner scanUpToString:@"=" intoString:&key]
        && [scanner scanString:@"=" intoString:nil]
        && [scanner scanUpToString:@"&" intoString:&value]) {

      [responseDict setObject:value forKey:key];
    }
  }
  return responseDict;
}

+ (NSDictionary *)dictionaryWithResponseData:(NSData *)data {
  NSString *responseStr = [[[NSString alloc] initWithData:data
                                                 encoding:NSUTF8StringEncoding] autorelease];
  NSDictionary *dict = [self dictionaryWithResponseString:responseStr];
  return dict;
}

#pragma mark -

+ (NSString *)HMACSHA1HashForKey:(NSString *)key body:(NSString *)body {
  if (key == nil || body == nil) return nil;

  NSMutableData *sigData = [NSMutableData dataWithLength:CC_SHA1_DIGEST_LENGTH];

  CCHmac(kCCHmacAlgSHA1,
         [key UTF8String], [key length],
         [body UTF8String], [body length],
         [sigData mutableBytes]);

  NSString *signature = [self stringWithBase64ForData:sigData];
  return signature;
}

#if GDATA_OAUTH_SUPPORTS_RSASHA1_SIGNING
+ (NSString *)signedRSASHA1HashForString:(NSString *)source
                     privateKeyPEMString:(NSString *)key  {
  if (source == nil || key == nil) return nil;

  OpenSSL_add_all_algorithms();
  // add EVP_cleanup

  NSString *signature = nil;

  // make a SHA-1 digest of the source string
  const char* sourceChars = [source UTF8String];

  unsigned char digest[SHA_DIGEST_LENGTH];
  SHA1((const unsigned char *)sourceChars, strlen(sourceChars), digest);

  // get an RSA from the private key PEM, and use it to sign the digest
  const char* keyChars = [key UTF8String];
  BIO* keyBio = BIO_new_mem_buf((char *) keyChars, -1); // -1 = use strlen()


  if (keyBio != NULL) {
    //    BIO_set_flags(keyBio, BIO_FLAGS_BASE64_NO_NL);
    RSA *rsa_key = NULL;

    rsa_key = PEM_read_bio_RSAPrivateKey(keyBio, NULL, NULL, NULL);
    if (rsa_key != NULL) {

      unsigned int sigLen = 0;
      unsigned char *sigBuff = malloc(RSA_size(rsa_key));

      int result = RSA_sign(NID_sha1, digest, (unsigned int) sizeof(digest),
                            sigBuff, &sigLen, rsa_key);

      if (result != 0) {
        NSData *sigData = [NSData dataWithBytes:sigBuff length:sigLen];
        signature = [self stringWithBase64ForData:sigData];
      }

      free(sigBuff);

      RSA_free(rsa_key);
    }
    BIO_free(keyBio);
  }

  return signature;
}
#endif // GDATA_OAUTH_SUPPORTS_RSASHA1_SIGNING

+ (NSString *)stringWithBase64ForData:(NSData *)data {
  // Cyrus Najmabadi elegent little encoder from
  // http://www.cocoadev.com/index.pl?BaseSixtyFour
  if (data == nil) return nil;

  const uint8_t* input = [data bytes];
  NSUInteger length = [data length];

  NSUInteger bufferSize = ((length + 2) / 3) * 4;
  NSMutableData* buffer = [NSMutableData dataWithLength:bufferSize];

  uint8_t* output = [buffer mutableBytes];

  static char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

  for (NSInteger i = 0; i < length; i += 3) {
    NSInteger value = 0;
    for (NSInteger j = i; j < (i + 3); j++) {
      value <<= 8;

      if (j < length) {
        value |= (0xFF & input[j]);
      }
    }

    NSInteger index = (i / 3) * 4;
    output[index + 0] =                    table[(value >> 18) & 0x3F];
    output[index + 1] =                    table[(value >> 12) & 0x3F];
    output[index + 2] = (i + 1) < length ? table[(value >> 6)  & 0x3F] : '=';
    output[index + 3] = (i + 2) < length ? table[(value >> 0)  & 0x3F] : '=';
  }

  NSString *result = [[[NSString alloc] initWithData:buffer
                                            encoding:NSASCIIStringEncoding] autorelease];
  return result;
}

@end

// This class represents key-value pairs so they can be sorted by both
// name and encoded value
@implementation OAuthParameter

@synthesize name = name_;
@synthesize value = value_;

+ (OAuthParameter *)parameterWithName:(NSString *)name
                                value:(NSString *)value {
  OAuthParameter *obj = [[[self alloc] init] autorelease];
  [obj setName:name];
  [obj setValue:value];
  return obj;
}

- (void)dealloc {
  [name_ release];
  [value_ release];
  [super dealloc];
}

- (NSString *)encodedValue {
  NSString *value = [self value];
  NSString *result = [GDataOAuthAuthentication encodedOAuthParameterForString:value];
  return result;
}

- (NSString *)encodedParam {
  NSString *str = [NSString stringWithFormat:@"%@=%@",
                   [self name], [self encodedValue]];
  return str;
}

- (NSString *)quotedEncodedParam {
  NSString *str = [NSString stringWithFormat:@"%@=\"%@\"",
                   [self name], [self encodedValue]];
  return str;
}

- (NSString *)description {
  return [self encodedParam];
}

+ (NSArray *)sortDescriptors {
  // sort by name and value
  SEL sel = @selector(caseInsensitiveCompare:);

  NSSortDescriptor *desc1, *desc2;
  desc1 = [[[NSSortDescriptor alloc] initWithKey:@"name"
                                       ascending:YES
                                        selector:sel] autorelease];
  desc2 = [[[NSSortDescriptor alloc] initWithKey:@"encodedValue"
                                       ascending:YES
                                        selector:sel] autorelease];

  NSArray *sortDescriptors = [NSArray arrayWithObjects:desc1, desc2, nil];
  return sortDescriptors;
}

@end

#endif // #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5

#endif // #if !GDATA_REQUIRE_SERVICE_INCLUDES || GDATA_INCLUDE_OAUTH
