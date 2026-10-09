// This test class is compiled only for an explicitly selected CI Dart suite.
// The host already links/registers the official integration_test plugin. Resolve
// its public Objective-C API in that process; do not link a second static copy.
#if IMAGEHUB_FLUTTER_INTEGRATION_CI

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <stdio.h>

@protocol ImageHubDartPlugin <NSObject>
+ (id<ImageHubDartPlugin>)instance;
@property(nonatomic, readonly, nullable) NSDictionary<NSString *, NSString *> *testResults;
@end

@protocol ImageHubDartRunner <NSObject>
+ (NSString *)testCaseNameFromDartTestName:(NSString *)name;
- (void)testIntegrationTestWithResults:(void (^)(SEL, BOOL, NSString * _Nullable))result;
@end

@interface ImageHubFlutterIntegrationTests : XCTestCase
@end

@implementation ImageHubFlutterIntegrationTests

- (void)testCompiledDartSuiteCompletes {
#if (IMAGEHUB_FLUTTER_INTEGRATION_NATIVE + IMAGEHUB_FLUTTER_INTEGRATION_BACKUP) != 1
#error Exactly one Dart suite is required.
#endif
#if IMAGEHUB_FLUTTER_INTEGRATION_NATIVE
  NSString *suite = @"native";
  NSArray<NSString *> *expected = @[
    @"IT-004 UT-036/075 partial Apple real Pigeon file bridge ownership rejection",
    @"IT-001/002 UT-004/012/102 partial Apple native storage SQLite pixels gallery and IO protection",
    @"UT/IT partial Apple native Keychain isolated write new-instance read delete",
    @"UT/IT partial Apple passive native network read listen cancel",
  ];
#elif IMAGEHUB_FLUTTER_INTEGRATION_BACKUP
  NSString *suite = @"backup";
  NSArray<NSString *> *expected = @[
    @"CT-006 ios actual closed full and metadata exports",
    @"CT-006/IT-005/BAK-005 windows to ios actual full metadata restore reopen",
    @"CT-006/IT-005/BAK-005 android to ios actual full metadata restore reopen",
    @"CT-006/IT-005/BAK-005 macos to ios actual full metadata restore reopen",
  ];
#else
#error An explicit native or backup Dart suite is required.
#endif
  XCTAssertTrue([NSThread isMainThread], @"The host run loop must service the real Flutter plugin.");
  if (![NSThread isMainThread]) { return; }

  Class pluginClass = NSClassFromString(@"IntegrationTestPlugin");
  Class runnerClass = NSClassFromString(@"FLTIntegrationTestRunner");
  XCTAssertNotNil(pluginClass, @"The official host plugin must be registered.");
  XCTAssertNotNil(runnerClass, @"The official host result runner must be linked.");
  if (!pluginClass || !runnerClass) { return; }
  XCTAssertTrue([pluginClass respondsToSelector:@selector(instance)]);
  XCTAssertTrue([pluginClass instancesRespondToSelector:@selector(testResults)]);
  XCTAssertTrue([runnerClass respondsToSelector:@selector(testCaseNameFromDartTestName:)]);
  XCTAssertTrue([runnerClass instancesRespondToSelector:@selector(testIntegrationTestWithResults:)]);
  if (![pluginClass respondsToSelector:@selector(instance)] ||
      ![pluginClass instancesRespondToSelector:@selector(testResults)] ||
      ![runnerClass respondsToSelector:@selector(testCaseNameFromDartTestName:)] ||
      ![runnerClass instancesRespondToSelector:@selector(testIntegrationTestWithResults:)]) { return; }

  id<ImageHubDartPlugin> plugin = [(id<ImageHubDartPlugin>)pluginClass instance];
  XCTAssertNotNil(plugin);
  if (!plugin) { return; }
  // The SDK runner's own wait is unbounded. Wait here with the actual host run
  // loop before calling it, and reject timeout, empty or incomplete responses.
  NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 600;
  while (!plugin.testResults && NSProcessInfo.processInfo.systemUptime < deadline) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  }
  NSDictionary<NSString *, NSString *> *results = [plugin.testResults copy];
  XCTAssertTrue([results isKindOfClass:[NSDictionary class]], @"No completed Dart response.");
  if (![results isKindOfClass:[NSDictionary class]]) { return; }
  NSSet *wanted = [NSSet setWithArray:expected];
  XCTAssertEqual(results.count, expected.count, @"Every selected Dart case must finish.");
  XCTAssertEqualObjects([NSSet setWithArray:results.allKeys], wanted, @"Unexpected Dart test set.");
  if (results.count != expected.count || ![[NSSet setWithArray:results.allKeys] isEqual:wanted]) { return; }
  for (NSString *name in expected) {
    XCTAssertEqualObjects(results[name], @"success", @"A Dart case did not succeed.");
    if (![results[name] isKindOfClass:[NSString class]] || ![results[name] isEqual:@"success"]) { return; }
  }

  NSMutableSet<NSString *> *expectedSelectors = [NSMutableSet set];
  for (NSString *name in expected) {
    NSString *selector = [(id<ImageHubDartRunner>)runnerClass testCaseNameFromDartTestName:name];
    XCTAssertTrue([selector isKindOfClass:[NSString class]] && selector.length > 0);
    if (![selector isKindOfClass:[NSString class]] || selector.length == 0) { return; }
    [expectedSelectors addObject:selector];
  }
  XCTAssertEqual(expectedSelectors.count, expected.count, @"SDK test names must remain unique.");
  if (expectedSelectors.count != expected.count) { return; }

  id<ImageHubDartRunner> runner = (id<ImageHubDartRunner>)[runnerClass new];
  __block NSUInteger callbacks = 0;
  __block BOOL callbackFailed = NO;
  NSMutableSet<NSString *> *received = [NSMutableSet set];
  [runner testIntegrationTestWithResults:^(SEL selector, BOOL success, NSString *message) {
    callbacks += 1;
    NSString *name = NSStringFromSelector(selector);
    BOOL valid = success && [expectedSelectors containsObject:name] && ![received containsObject:name];
    XCTAssertTrue(valid, @"Official SDK result callback must match the completed response.");
    callbackFailed = callbackFailed || !valid;
    [received addObject:name];
  }];
  XCTAssertEqual(callbacks, expected.count);
  XCTAssertEqualObjects(received, expectedSelectors);
  if (callbackFailed || callbacks != expected.count || ![received isEqual:expectedSelectors]) { return; }

  NSDictionary *proof = @{ @"suite": suite, @"results": results, @"callbacks": @(callbacks) };
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:proof options:NSJSONWritingSortedKeys error:&error];
  XCTAssertNotNil(data);
  XCTAssertNil(error);
  if (!data || error) { return; }
  XCTAttachment *attachment = [XCTAttachment attachmentWithData:data uniformTypeIdentifier:@"public.json"];
  attachment.name = [NSString stringWithFormat:@"imagehub-dart-%@-results.json", suite];
  attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
  [self addAttachment:attachment];
  NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  fprintf(stdout, "IMAGEHUB_DART_XCTEST_RESULTS:%s\n", json.UTF8String);
  fflush(stdout);
}

@end
#endif
