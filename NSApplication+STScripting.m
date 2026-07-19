/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * NSApplication category for automatic StepTalk scripting environment
 * setup.  Loaded when the Eau theme bundle is loaded, so every app
 * that uses this theme gets StepTalk scripting automatically.
 *
 * StepTalk library is loaded via dlopen at runtime so we don't link
 * against it at build time — avoids bundle-load interference on
 * systems where libStepTalk is installed but shouldn't be pulled in
 * as an eager dependency.
 */

#import <AppKit/AppKit.h>
#import <dlfcn.h>

static id gScriptEnv = nil;
static NSConnection *gEnvConnection = nil;

@interface STEauEnvironmentProvider : NSObject
{
  id _environment;
}
- (id)initWithEnvironment:(id)env;
- (void)interpretScript:(bycopy NSString *)aString;
- (bycopy id)resultByCopy;
@end

@interface STEauConversation : NSObject
- (id)initWithContext:(id)ctx language:(id)lang;
- (void)interpretScript:(NSString *)script;
@end

@implementation STEauEnvironmentProvider

- (id)initWithEnvironment:(id)env
{
  if ((self = [super init])) {
    _environment = env;
  }
  return self;
}

- (void)_runScript:(NSString *)aString
{
  Class stConvClass = NSClassFromString(@"STConversation");
  STEauConversation *conversation = (STEauConversation *)
      [[stConvClass alloc] initWithContext:_environment
                                  language:nil];
  [conversation interpretScript:aString];
}

- (void)interpretScript:(bycopy NSString *)aString
{
  [self performSelectorOnMainThread:@selector(_runScript:)
                         withObject:aString
                      waitUntilDone:YES];
}

- (bycopy id)resultByCopy
{
  return nil;
}

@end

@implementation NSApplication (STScripting)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
+ (void)setupStepTalkScripting
{
  void *handle = dlopen("libStepTalk.so", RTLD_NOLOAD | RTLD_LAZY);
  if (!handle)
    {
      handle = dlopen("libStepTalk.so", RTLD_LAZY | RTLD_LOCAL);
    }
  if (!handle)
    {
      return;
    }

  Class stEnvClass = NSClassFromString(@"STEnvironment");
  Class stEnvDescClass = NSClassFromString(@"STEnvironmentDescription");
  if (!stEnvClass || !stEnvDescClass)
    {
      dlclose(handle);
      return;
    }

  gScriptEnv = nil;
  NSString *envDescName = [[NSBundle mainBundle]
    objectForInfoDictionaryKey:@"STEnvironmentDescription"];
  if (envDescName)
    {
      id envDesc = [stEnvDescClass performSelector: @selector(descriptionWithName:)
                                        withObject: envDescName];
      if (envDesc)
        {
          gScriptEnv = [stEnvClass performSelector: @selector(environmentWithDescription:)
                                        withObject: envDesc];
        }
    }
  if (!gScriptEnv)
    {
      gScriptEnv = [stEnvClass performSelector: @selector(environmentWithDefaultDescription)];
    }
  if (!gScriptEnv)
    {
      dlclose(handle);
      return;
    }

  SEL loadModuleSel = @selector(loadModule:);
  if ([gScriptEnv respondsToSelector: loadModuleSel])
    {
      [gScriptEnv performSelector: loadModuleSel withObject: @"AppKit"];
    }

  SEL includeBundleSel = @selector(includeBundle:);
  if ([gScriptEnv respondsToSelector: includeBundleSel])
    {
      [gScriptEnv performSelector: includeBundleSel withObject: [NSBundle mainBundle]];
    }

  SEL setObjectSel = @selector(setObject:forName:);
  if ([gScriptEnv respondsToSelector: setObjectSel])
    {
      [gScriptEnv performSelector: setObjectSel withObject: [NSApplication sharedApplication]
                       withObject: @"Application"];
    }

  /* Register environment provider under STEnvironment:<name> */
  NSString *appName = [[NSProcessInfo processInfo] processName];
  STEauEnvironmentProvider *provider =
    [[STEauEnvironmentProvider alloc] initWithEnvironment:gScriptEnv];
  NSString *envName = [NSString stringWithFormat:@"STEnvironment:%@", appName];
  gEnvConnection = [[NSConnection alloc] init];
  [gEnvConnection setRootObject:provider];
  if ([gEnvConnection registerName:envName]) {
    NSLog(@"%@: StepTalk environment registered as DO '%@'", appName, envName);
  } else {
    NSLog(@"%@: Failed to register DO name '%@'", appName, envName);
  }
}
#pragma clang diagnostic pop

- (id)scriptingEnvironment
{
  return gScriptEnv;
}

@end
