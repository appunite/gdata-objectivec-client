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

// This class implements the OAuth 1.0a protocol for creating and signing
// requests. http://oauth.net/core/1.0a/
//
// Users can rely on +authForInstalledApp for creating a complete authentication
// object for use with Google's OAuth protocol.
//
// The user (typically the GDataOAuthSignIn object) can call the methods
//  - (void)setKeysForResponseData:(NSData *)data;
//  - (void)setKeysForResponseString:(NSString *)str;
//
// to set the parameters following each server interaction, and then can use
// - (BOOL)authorizeRequest:(NSMutableURLRequest *)request
//
// to add the "Authorization: OAuth ..." header to future resource requests.

#import <Foundation/Foundation.h>

#undef _EXTERN
#undef _INITIALIZE_AS
#ifdef GDATAOAUTHAUTHENTICATION_DEFINE_GLOBALS
#define _EXTERN
#define _INITIALIZE_AS(x) =x
#else
#define _EXTERN extern
#define _INITIALIZE_AS(x)
#endif

_EXTERN NSString* const kGDataOAuthServiceProviderGoogle _INITIALIZE_AS(@"Google");

_EXTERN NSString* const kGDataOAuthSignatureMethodHMAC_SHA1 _INITIALIZE_AS(@"HMAC-SHA1");

//
// GDataOAuthSignIn constants, included here for use by clients
//
_EXTERN NSString* const kGDataOAuthErrorDomain  _INITIALIZE_AS(@"com.google.GDataOAuth");

// notifications for token fetches
_EXTERN NSString* const kGDataOAuthFetchStarted _INITIALIZE_AS(@"kGDataOAuthFetchStarted");
_EXTERN NSString* const kGDataOAuthFetchStopped _INITIALIZE_AS(@"kGDataOAuthFetchStopped");

_EXTERN NSString* const kGDataOAuthFetchTypeKey     _INITIALIZE_AS(@"FetchType");
_EXTERN NSString* const kGDataOAuthFetchTypeRequest _INITIALIZE_AS(@"request");
_EXTERN NSString* const kGDataOAuthFetchTypeAccess  _INITIALIZE_AS(@"access");


#if GDATA_OAUTH_SUPPORTS_RSASHA1_SIGNING
_EXTERN NSString* const kGDataOAuthSignatureMethodRSA_SHA1  _INITIALIZE_AS(@"RSA-SHA1");
#endif

@interface GDataOAuthAuthentication : NSObject {
 @private
  // paramValues_ contains the parameters used in requests and responses
  NSMutableDictionary *paramValues_;

  NSString *realm_;
  NSString *privateKey_;
  NSString *timestamp_; // set for testing only
  NSString *nonce_;     // set for testing only

  NSString *serviceProvider_;

  // flag indicating if the token in paramValues is a request token or an
  // access token
  BOOL hasAccessToken_;

  id userData_;
}

// OAuth protocol parameters
//
// timestamp (seconds since 1970) and nonce (random number) are generated
// uniquely for each request, except during testing, when they may be set
// explicitly
@property (nonatomic, assign) NSString *scope;
@property (nonatomic, assign) NSString *displayName;
@property (nonatomic, assign) NSString *hostedDomain;
@property (nonatomic, assign) NSString *language;
@property (nonatomic, assign) NSString *mobile;
@property (nonatomic, assign) NSString *consumerKey;
@property (nonatomic, assign) NSString *signatureMethod;
@property (nonatomic, assign) NSString *version;
@property (nonatomic, assign) NSString *token;
@property (nonatomic, assign) NSString *callback;
@property (nonatomic, assign) NSString *verifier;
@property (nonatomic, assign) NSString *tokenSecret;
@property (nonatomic, assign) NSString *callbackConfirmed;
@property (nonatomic, assign) NSString *timestamp;
@property (nonatomic, assign) NSString *nonce;

// other standard OAuth protocol properties
@property (nonatomic, copy) NSString *realm;
@property (nonatomic, copy) NSString *privateKey;

// service identifier, like "Google"; not used for authentication or signing
@property (nonatomic, copy) NSString *serviceProvider;

// property for using a previously-authorized access token
@property (nonatomic, copy) NSString *accessToken;

// userData is retained for the convenience of the caller
@property (nonatomic, retain) NSString *userData;


// Create an authentication object, with hardcoded values for installed apps
// with HMAC-SHA1 as signature method, and "anonymous" as the consumer key and
// consumer secret (private key).
+ (GDataOAuthAuthentication *)authForInstalledApp;

// Create an authentication object, specifying the consumer key and
// private key (both anonymous for installed apps) and the signature method
// ("HMAC-SHA1" for installed apps).
//
// For signature method "RSA-SHA1", a proper consumer key and private key
// may be supplied (and the GDATA_OAUTH_SUPPORTS_RSASHA1_SIGNING compiler
// conditional must be set.)
- (id)initWithSignatureMethod:(NSString *)signatureMethod
                  consumerKey:(NSString *)consumerKey
                   privateKey:(NSString *)privateKey;

// authorization entry point for GData library
- (BOOL)authorizeRequest:(NSMutableURLRequest *)request;
- (BOOL)canAuthorize;

// add OAuth headers
//
// any non-OAuth parameters (such as scope) will be included in the signature
// but added as a URL parameter, not in the Auth header
- (void)addRequestTokenHeaderToRequest:(NSMutableURLRequest *)request;
- (void)addAuthorizeTokenHeaderToRequest:(NSMutableURLRequest *)request;
- (void)addAccessTokenHeaderToRequest:(NSMutableURLRequest *)request;
- (void)addResourceTokenHeaderToRequest:(NSMutableURLRequest *)request;

// add OAuth URL params, as an alternative to adding headers
- (void)addRequestTokenParamsToRequest:(NSMutableURLRequest *)request;
- (void)addAuthorizeTokenParamsToRequest:(NSMutableURLRequest *)request;
- (void)addAccessTokenParamsToRequest:(NSMutableURLRequest *)request;
- (void)addResourceTokenParamsToRequest:(NSMutableURLRequest *)request;

// parse and set token and token secret from response data
- (void)setKeysForResponseData:(NSData *)data;
- (void)setKeysForResponseString:(NSString *)str;

// persistent token string for keychain storage
//
// we'll use the format "oauth_token=foo&oauth_token_secret=bar" so we can
// easily alter what portions of the auth data are stored
- (NSString *)persistenceResponseString;

// method for distinguishing between the OAuth token being a request token and
// an access token
- (BOOL)hasAccessToken;
- (void)setHasAccessToken:(BOOL)flag;

//
// utilities
//

+ (NSString *)encodedOAuthParameterForString:(NSString *)str;
+ (NSString *)unencodedOAuthParameterForString:(NSString *)str;

+ (NSDictionary *)dictionaryWithResponseData:(NSData *)data;
+ (NSDictionary *)dictionaryWithResponseString:(NSString *)responseStr;

+ (NSString *)stringWithBase64ForData:(NSData *)data;

@end

#endif // #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5

#endif // #if !GDATA_REQUIRE_SERVICE_INCLUDES || GDATA_INCLUDE_OAUTH
