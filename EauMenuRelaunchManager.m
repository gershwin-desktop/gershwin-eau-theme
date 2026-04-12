#import "EauMenuRelaunchManager.h"

#import <Foundation/Foundation.h>

#import <errno.h>
#import <signal.h>
#import <stdlib.h>
#import <string.h>
#import <time.h>
#import <unistd.h>

static pid_t EauFindMenuPIDInProcFS(void);
static pid_t EauFindMenuPIDWithPS(void);
static BOOL EauCaptureMenuSnapshotFromProcFS(pid_t pid,
                                             NSString **exeOut,
                                             NSArray **argsOut,
                                             NSDictionary **envOut,
                                             uid_t *uidOut,
                                             gid_t *gidOut);
static BOOL EauCaptureMenuSnapshotFromProcstat(pid_t pid,
                                               NSString **exeOut,
                                               NSArray **argsOut,
                                               NSDictionary **envOut);
static NSString *EauTailAfterColumns(NSString *line, NSUInteger cols);
static NSString *EauReadlinkTarget(NSString *path);

@interface EauMenuRelaunchManager ()
{
  NSString *_menuExecutablePath;
  NSArray *_menuArguments;
  NSDictionary *_menuEnvironment;
  uid_t _menuUid;
  gid_t _menuGid;
  BOOL _menuSnapshotCaptured;
  time_t _menuLaunchLastAttempt;
}
@end

@implementation EauMenuRelaunchManager

+ (instancetype)sharedManager
{
  static EauMenuRelaunchManager *manager = nil;
  static BOOL initialized = NO;

  if (!initialized)
    {
      manager = [[EauMenuRelaunchManager alloc] init];
      initialized = YES;
    }
  return manager;
}

- (instancetype)init
{
  self = [super init];
  if (self != nil)
    {
      _menuUid = (uid_t)-1;
      _menuGid = (gid_t)-1;
      _menuSnapshotCaptured = NO;
      _menuLaunchLastAttempt = 0;
    }
  return self;
}

- (BOOL)captureMenuProcessSnapshotIfAvailable
{
  @synchronized(self)
    {
      pid_t pid = EauFindMenuPIDInProcFS();
      if (pid <= 0)
        {
          pid = EauFindMenuPIDWithPS();
        }
      if (pid <= 0)
        {
          NSLog(@"Eau: No running Menu process snapshot found");
          return NO;
        }

      NSString *exe = nil;
      NSArray *args = nil;
      NSDictionary *env = nil;
      uid_t uid = (uid_t)-1;
      gid_t gid = (gid_t)-1;

      if (EauCaptureMenuSnapshotFromProcFS(pid, &exe, &args, &env, &uid, &gid))
        {
          _menuExecutablePath = exe;
          _menuArguments = args;
          _menuEnvironment = env;
          _menuUid = uid;
          _menuGid = gid;
          _menuSnapshotCaptured = YES;

          NSLog(@"Eau: Captured Menu snapshot via /proc pid=%d exec=%@ argc=%lu envc=%lu uid=%u gid=%u",
                (int)pid,
                _menuExecutablePath,
                (unsigned long)[_menuArguments count],
                (unsigned long)[_menuEnvironment count],
                (unsigned int)_menuUid,
                (unsigned int)_menuGid);
          return YES;
        }

      if (EauCaptureMenuSnapshotFromProcstat(pid, &exe, &args, &env))
        {
          _menuExecutablePath = exe;
          _menuArguments = args;
          _menuEnvironment = env;
          _menuUid = (uid_t)-1;
          _menuGid = (gid_t)-1;
          _menuSnapshotCaptured = YES;

          NSLog(@"Eau: Captured Menu snapshot via procstat pid=%d exec=%@ argc=%lu envc=%lu",
                (int)pid,
                _menuExecutablePath,
                (unsigned long)[_menuArguments count],
                (unsigned long)[_menuEnvironment count]);
          return YES;
        }

      NSLog(@"Eau: Failed to capture Menu process snapshot for pid %d", (int)pid);
      return NO;
    }
}

- (void)relaunchMenuProcessIfSnapshotAvailable
{
  @synchronized(self)
    {
      time_t now = time(NULL);
      if (now != (time_t)-1 && _menuLaunchLastAttempt != 0 && (now - _menuLaunchLastAttempt) < 2)
        {
          return;
        }
      _menuLaunchLastAttempt = now;

      if (!_menuSnapshotCaptured)
        {
          [self captureMenuProcessSnapshotIfAvailable];
        }

      if (!_menuSnapshotCaptured || _menuExecutablePath == nil || [_menuExecutablePath length] == 0)
        {
          NSLog(@"Eau: Menu restart skipped - no process snapshot available");
          return;
        }

      pid_t pid = fork();
      if (pid < 0)
        {
          NSLog(@"Eau: Failed to fork to launch Menu process: %s", strerror(errno));
          return;
        }

      if (pid == 0)
        {
          uid_t targetUid = _menuUid;
          gid_t targetGid = _menuGid;
          if (targetUid == (uid_t)-1)
            {
              targetUid = getuid();
            }
          if (targetGid == (gid_t)-1)
            {
              targetGid = getgid();
            }

          if (geteuid() == 0 && targetUid != 0)
            {
              if (setgid(targetGid) != 0)
                {
                  _exit(1);
                }
              if (setuid(targetUid) != 0)
                {
                  _exit(1);
                }
            }

          if (_menuExecutablePath != nil && [_menuExecutablePath length] > 0 &&
              access([_menuExecutablePath UTF8String], X_OK) == 0)
            {
              NSArray *args = _menuArguments;
              if (args == nil || [args count] == 0)
                {
                  args = [NSArray arrayWithObject:[_menuExecutablePath lastPathComponent]];
                }

              NSUInteger argc = [args count];
              char **argv = (char **)calloc(argc + 1, sizeof(char *));
              if (argv != NULL)
                {
                  for (NSUInteger i = 0; i < argc; i++)
                    {
                      NSString *a = [args objectAtIndex:i];
                      argv[i] = strdup([a UTF8String]);
                    }
                  argv[argc] = NULL;

                  NSArray *envKeys = [_menuEnvironment allKeys];
                  NSUInteger envc = [envKeys count];
                  char **envp = NULL;
                  if (envc > 0)
                    {
                      envp = (char **)calloc(envc + 1, sizeof(char *));
                      if (envp != NULL)
                        {
                          for (NSUInteger i = 0; i < envc; i++)
                            {
                              NSString *key = [envKeys objectAtIndex:i];
                              NSString *value = [_menuEnvironment objectForKey:key];
                              NSString *pair = [NSString stringWithFormat:@"%@=%@", key, value ?: @""];
                              envp[i] = strdup([pair UTF8String]);
                            }
                          envp[envc] = NULL;
                        }
                    }

                  if (envp != NULL)
                    {
                      execve([_menuExecutablePath UTF8String], argv, envp);
                    }
                  else
                    {
                      execv([_menuExecutablePath UTF8String], argv);
                    }
                }
            }

          NSLog(@"Eau: Menu restart failed - unable to exec captured command (%@): %s",
                _menuExecutablePath,
                strerror(errno));
          _exit(1);
        }
    }
}

@end

static pid_t EauFindMenuPIDInProcFS(void)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *entries = [fm contentsOfDirectoryAtPath:@"/proc" error:nil];
  NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
  NSCharacterSet *trim = [NSCharacterSet whitespaceAndNewlineCharacterSet];

  for (NSString *entry in entries)
    {
      if ([entry rangeOfCharacterFromSet:[digits invertedSet]].location != NSNotFound)
        {
          continue;
        }
      NSString *commPath = [[@"/proc" stringByAppendingPathComponent:entry] stringByAppendingPathComponent:@"comm"];
      NSString *comm = [NSString stringWithContentsOfFile:commPath
                                                 encoding:NSUTF8StringEncoding
                                                    error:nil];
      if (comm == nil)
        {
          continue;
        }
      if ([[comm stringByTrimmingCharactersInSet:trim] isEqualToString:@"Menu"])
        {
          return (pid_t)[entry intValue];
        }
    }
  return (pid_t)0;
}

static pid_t EauFindMenuPIDWithPS(void)
{
  FILE *pipe = popen("ps -ax -o pid= -o comm=", "r");
  if (pipe == NULL)
    {
      return (pid_t)0;
    }

  char line[1024];
  pid_t found = (pid_t)0;
  while (fgets(line, sizeof(line), pipe) != NULL)
    {
      int pid = 0;
      char comm[512];
      comm[0] = '\0';
      if (sscanf(line, "%d %511s", &pid, comm) == 2)
        {
          if (strcmp(comm, "Menu") == 0)
            {
              found = (pid_t)pid;
              break;
            }
        }
    }
  pclose(pipe);
  return found;
}

static BOOL EauCaptureMenuSnapshotFromProcFS(pid_t pid,
                                             NSString **exeOut,
                                             NSArray **argsOut,
                                             NSDictionary **envOut,
                                             uid_t *uidOut,
                                             gid_t *gidOut)
{
  NSString *procPath = [NSString stringWithFormat:@"/proc/%d", (int)pid];
  NSString *exePath = EauReadlinkTarget([procPath stringByAppendingPathComponent:@"exe"]);
  if (exePath == nil || [exePath length] == 0)
    {
      return NO;
    }

  NSMutableArray *argv = [NSMutableArray array];
  NSData *cmdData = [NSData dataWithContentsOfFile:[procPath stringByAppendingPathComponent:@"cmdline"]];
  if (cmdData != nil && [cmdData length] > 0)
    {
      const char *bytes = [cmdData bytes];
      NSUInteger len = [cmdData length];
      NSUInteger start = 0;
      for (NSUInteger i = 0; i < len; i++)
        {
          if (bytes[i] == '\0')
            {
              if (i > start)
                {
                  NSString *s = [[NSString alloc] initWithBytes:bytes + start
                                                          length:(i - start)
                                                        encoding:NSUTF8StringEncoding];
                  if (s != nil)
                    {
                      [argv addObject:s];
                    }
                }
              start = i + 1;
            }
        }
    }

  NSMutableDictionary *env = [NSMutableDictionary dictionary];
  NSData *envData = [NSData dataWithContentsOfFile:[procPath stringByAppendingPathComponent:@"environ"]];
  if (envData != nil && [envData length] > 0)
    {
      const char *bytes = [envData bytes];
      NSUInteger len = [envData length];
      NSUInteger start = 0;
      for (NSUInteger i = 0; i < len; i++)
        {
          if (bytes[i] == '\0')
            {
              if (i > start)
                {
                  NSString *pair = [[NSString alloc] initWithBytes:bytes + start
                                                             length:(i - start)
                                                           encoding:NSUTF8StringEncoding];
                  NSRange eq = [pair rangeOfString:@"="];
                  if (eq.location != NSNotFound)
                    {
                      NSString *k = [pair substringToIndex:eq.location];
                      NSString *v = [pair substringFromIndex:eq.location + 1];
                      if ([k length] > 0)
                        {
                          [env setObject:(v ?: @"") forKey:k];
                        }
                    }
                }
              start = i + 1;
            }
        }
    }

  uid_t uid = (uid_t)-1;
  gid_t gid = (gid_t)-1;
  NSString *status = [NSString stringWithContentsOfFile:[procPath stringByAppendingPathComponent:@"status"]
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
  if (status != nil)
    {
      NSArray *lines = [status componentsSeparatedByString:@"\n"];
      for (NSString *line in lines)
        {
          if ([line hasPrefix:@"Uid:"])
            {
              NSScanner *scanner = [NSScanner scannerWithString:line];
              int parsed = -1;
              [scanner scanString:@"Uid:" intoString:NULL];
              [scanner scanInt:&parsed];
              if (parsed >= 0)
                {
                  uid = (uid_t)parsed;
                }
            }
          else if ([line hasPrefix:@"Gid:"])
            {
              NSScanner *scanner = [NSScanner scannerWithString:line];
              int parsed = -1;
              [scanner scanString:@"Gid:" intoString:NULL];
              [scanner scanInt:&parsed];
              if (parsed >= 0)
                {
                  gid = (gid_t)parsed;
                }
            }
        }
    }

  if (exeOut != NULL)
    {
      *exeOut = exePath;
    }
  if (argsOut != NULL)
    {
      *argsOut = [NSArray arrayWithArray:argv];
    }
  if (envOut != NULL)
    {
      *envOut = [NSDictionary dictionaryWithDictionary:env];
    }
  if (uidOut != NULL)
    {
      *uidOut = uid;
    }
  if (gidOut != NULL)
    {
      *gidOut = gid;
    }
  return YES;
}

static NSString *EauTailAfterColumns(NSString *line, NSUInteger cols)
{
  NSUInteger len = [line length];
  NSUInteger i = 0;
  NSUInteger consumed = 0;
  NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];

  while (i < len && consumed < cols)
    {
      while (i < len && [ws characterIsMember:[line characterAtIndex:i]])
        {
          i++;
        }
      while (i < len && ![ws characterIsMember:[line characterAtIndex:i]])
        {
          i++;
        }
      consumed++;
    }

  while (i < len && [ws characterIsMember:[line characterAtIndex:i]])
    {
      i++;
    }

  if (i >= len)
    {
      return @"";
    }
  return [line substringFromIndex:i];
}

static BOOL EauCaptureMenuSnapshotFromProcstat(pid_t pid,
                                               NSString **exeOut,
                                               NSArray **argsOut,
                                               NSDictionary **envOut)
{
  NSString *cmd;
  FILE *pipe;
  char line[4096];
  NSMutableArray *argv = [NSMutableArray array];
  NSMutableDictionary *env = [NSMutableDictionary dictionary];
  NSString *exePath = nil;

  cmd = [NSString stringWithFormat:@"procstat -b %d 2>/dev/null", (int)pid];
  pipe = popen([cmd UTF8String], "r");
  if (pipe != NULL)
    {
      while (fgets(line, sizeof(line), pipe) != NULL)
        {
          NSString *s = [[NSString stringWithUTF8String:line] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
          if ([s length] == 0 || [s hasPrefix:@"PID "])
            {
              continue;
            }
          exePath = EauTailAfterColumns(s, 3);
          break;
        }
      pclose(pipe);
    }

  cmd = [NSString stringWithFormat:@"procstat -c %d 2>/dev/null", (int)pid];
  pipe = popen([cmd UTF8String], "r");
  if (pipe != NULL)
    {
      while (fgets(line, sizeof(line), pipe) != NULL)
        {
          NSString *s = [[NSString stringWithUTF8String:line] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
          if ([s length] == 0 || [s hasPrefix:@"PID "])
            {
              continue;
            }
          NSString *tail = EauTailAfterColumns(s, 2);
          NSArray *parts = [tail componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
          for (NSString *part in parts)
            {
              if ([part length] > 0)
                {
                  [argv addObject:part];
                }
            }
          break;
        }
      pclose(pipe);
    }

  cmd = [NSString stringWithFormat:@"procstat -e %d 2>/dev/null", (int)pid];
  pipe = popen([cmd UTF8String], "r");
  if (pipe != NULL)
    {
      while (fgets(line, sizeof(line), pipe) != NULL)
        {
          NSString *s = [[NSString stringWithUTF8String:line] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
          if ([s length] == 0 || [s hasPrefix:@"PID "])
            {
              continue;
            }
          NSString *tail = EauTailAfterColumns(s, 2);
          NSRange eq = [tail rangeOfString:@"="];
          if (eq.location != NSNotFound)
            {
              NSString *k = [tail substringToIndex:eq.location];
              NSString *v = [tail substringFromIndex:eq.location + 1];
              if ([k length] > 0)
                {
                  [env setObject:(v ?: @"") forKey:k];
                }
            }
        }
      pclose(pipe);
    }

  if (exePath == nil || [exePath length] == 0)
    {
      return NO;
    }
  if ([argv count] == 0)
    {
      [argv addObject:[exePath lastPathComponent]];
    }

  if (exeOut != NULL)
    {
      *exeOut = exePath;
    }
  if (argsOut != NULL)
    {
      *argsOut = [NSArray arrayWithArray:argv];
    }
  if (envOut != NULL)
    {
      *envOut = [NSDictionary dictionaryWithDictionary:env];
    }
  return YES;
}

static NSString *EauReadlinkTarget(NSString *path)
{
  char buffer[4096];
  ssize_t n = readlink([path UTF8String], buffer, sizeof(buffer) - 1);
  if (n <= 0)
    {
      return nil;
    }
  buffer[n] = '\0';
  return [NSString stringWithUTF8String:buffer];
}
