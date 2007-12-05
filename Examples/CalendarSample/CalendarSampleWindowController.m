/* Copyright (c) 2007 Google Inc.
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

//
//  CalendarSampleWindowController.m
//

#import "CalendarSampleWindowController.h"

#import "EditEventWindowController.h"
#import "EditACLWindowController.h"

@interface CalendarSampleWindowController (PrivateMethods)
- (void)updateUI;

- (void)fetchAllCalendars;
- (void)fetchSelectedCalendar;

- (void)addACalendar;
- (void)renameSelectedCalendar;
- (void)deleteSelectedCalendar;

- (void)fetchSelectedCalendarEvents;
- (void)addAnEvent;
- (void)editSelectedEvent;
- (void)deleteSelectedEvents;
- (void)batchDeleteSelectedEvents;
- (void)queryTodaysEvents;

- (void)fetchSelectedCalendarACLEntries;
- (void)addAnACLEntry;
- (void)editSelectedACLEntry;
- (void)deleteSelectedACLEntry;

- (GDataServiceGoogleCalendar *)calendarService;
- (GDataEntryCalendar *)selectedCalendar;
- (GDataEntryCalendarEvent *)singleSelectedEvent;
- (NSArray *)selectedEvents;
- (GDataEntryACL *)selectedACLEntry;

- (BOOL)isACLSegmentSelected;
- (BOOL)isEventsSegmentSelected;
  
- (GDataFeedCalendar *)calendarFeed;
- (void)setCalendarFeed:(GDataFeedCalendar *)feed;
- (NSError *)calendarFetchError;
- (void)setCalendarFetchError:(NSError *)error;  
- (GDataServiceTicket *)calendarFetchTicket;
- (void)setCalendarFetchTicket:(GDataServiceTicket *)ticket;

- (GDataFeedCalendarEvent *)eventFeed;
- (void)setEventFeed:(GDataFeedCalendarEvent *)feed;
- (NSError *)eventFetchError;
- (void)setEventFetchError:(NSError *)error;
- (GDataServiceTicket *)eventFetchTicket;
- (void)setEventFetchTicket:(GDataServiceTicket *)ticket;
  
- (GDataFeedACL *)ACLFeed;
- (void)setACLFeed:(GDataFeedACL *)feed;
- (NSError *)ACLFetchError;
- (void)setACLFetchError:(NSError *)error;
- (GDataServiceTicket *)ACLFetchTicket;
- (void)setACLFetchTicket:(GDataServiceTicket *)ticket;

@end

enum {
  // calendar segmented control segment index values
  kAllCalendarsSegment = 0,
  kOwnedCalendarsSegment = 1
};

enum {
  // event/ACL segmented control segment index values
  kEventsSegment = 0,
  kACLSegment = 1
};

@implementation CalendarSampleWindowController

static CalendarSampleWindowController* gCalendarSampleWindowController = nil;


+ (CalendarSampleWindowController *)sharedCalendarSampleWindowController {
  
  if (!gCalendarSampleWindowController) {
    gCalendarSampleWindowController = [[CalendarSampleWindowController alloc] init];
  }  
  return gCalendarSampleWindowController;
}


- (id)init {
  return [self initWithWindowNibName:@"CalendarSampleWindow"];
}

- (void)windowDidLoad {
}

- (void)awakeFromNib {
  // Set the result text fields to have a distinctive color and mono-spaced font
  // to aid in understanding of each calendar and event query operation.
  [mCalendarResultTextField setTextColor:[NSColor darkGrayColor]];
  [mEventResultTextField setTextColor:[NSColor darkGrayColor]];

  NSFont *resultTextFont = [NSFont fontWithName:@"Monaco" size:9];
  [mCalendarResultTextField setFont:resultTextFont];
  [mEventResultTextField setFont:resultTextFont];
  
  [mCalendarTable setDoubleAction:@selector(logEntryXML:)];
  [mEventTable setDoubleAction:@selector(logEntryXML:)];

  [self updateUI];
}

- (void)dealloc {
  [mCalendarFeed release];
  [mCalendarFetchError release];
  [mCalendarFetchTicket release];
  
  [mEventFeed release];
  [mEventFetchError release];
  [mEventFetchTicket release];
  
  [mACLFeed release];
  [mACLFetchError release];
  [mACLFetchTicket release];
  
  [super dealloc];
}

#pragma mark -

- (void)updateUI {
  
  // calendar list display
  [mCalendarTable reloadData]; 
  
  if (mCalendarFetchTicket != nil) {
    [mCalendarProgressIndicator startAnimation:self];  
  } else {
    [mCalendarProgressIndicator stopAnimation:self];  
  }
  
  // calendar fetch result or selected item
  NSString *calendarResultStr = @"";
  if (mCalendarFetchError) {
    calendarResultStr = [mCalendarFetchError description];
  } else {
    GDataEntryCalendar *calendar = [self selectedCalendar];
    if (calendar) {
      calendarResultStr = [calendar description];
    } else {
      
    }
  }
  [mCalendarResultTextField setString:calendarResultStr];
  
  // add/delete calendar controls
  BOOL canAddCalendar = ([[mCalendarFeed links] postLink] != nil);
  BOOL hasNewCalendarName = ([[mCalendarNameField stringValue] length] > 0);
  [mAddCalendarButton setEnabled:(canAddCalendar && hasNewCalendarName)];
  
  BOOL canEditSelectedCalendar = ([[[self selectedCalendar] links] editLink] != nil);
  [mDeleteCalendarButton setEnabled:canEditSelectedCalendar];
  [mRenameCalendarButton setEnabled:(hasNewCalendarName && canEditSelectedCalendar)];
  
  int calendarsSegment = [mCalendarSegmentedControl selectedSegment];
  BOOL canEditNewCalendarName = (calendarsSegment == kOwnedCalendarsSegment);
  [mCalendarNameField setEnabled:canEditNewCalendarName];
  
  // event/ACL list display
  [mEventTable reloadData]; 
  
  // the bottom table displays either event entries or ACL entries
  BOOL isEventDisplay = [self isEventsSegmentSelected];
  
  GDataServiceTicket *entryTicket = isEventDisplay ? mEventFetchTicket : mACLFetchTicket;
  NSError *error = isEventDisplay ? mEventFetchError : mACLFetchError;
    
  if (entryTicket != nil) {
    [mEventProgressIndicator startAnimation:self];  
  } else {
    [mEventProgressIndicator stopAnimation:self];  
  }
  
  // display event or ACL entry fetch result or selected item
  NSString *eventResultStr = @"";
  if (error) {
    eventResultStr = [error description];
  } else {
    if (isEventDisplay) {
      GDataEntryCalendarEvent *event = [self singleSelectedEvent];
      if (event) {
        eventResultStr = [event description];
      }
    } else {
      GDataEntryACL *entry = [self selectedACLEntry];
      if (entry) {
        eventResultStr = [entry description];
      }
    }
  }
  [mEventResultTextField setString:eventResultStr];
  
  // enable/disable cancel buttons
  [mCalendarCancelButton setEnabled:(mCalendarFetchTicket != nil)];
  [mEventCancelButton setEnabled:(entryTicket != nil)];
  
  // enable/disable other buttons
  BOOL isCalendarSelected = ([self selectedCalendar] != nil);
  
  BOOL doesSelectedCalendarHaveACLFeed = 
    ([[[self selectedCalendar] links] ACLLink] != nil);
    
  if (isEventDisplay) {
    
    [mAddEventButton setEnabled:isCalendarSelected];
    [mQueryTodayEventButton setEnabled:isCalendarSelected];

    // Events segment is selected 
    NSArray *selectedEvents = [self selectedEvents];
    unsigned int numberOfSelectedEvents = [selectedEvents count];
    
    NSString *deleteTitle = (numberOfSelectedEvents <= 1) ?
      @"Delete Entry" : @"Delete Entries"; 
    [mDeleteEventButton setTitle:deleteTitle];

    if (numberOfSelectedEvents == 1) {
      
      // 1 selected event
      GDataEntryCalendarEvent *event = [selectedEvents objectAtIndex:0];
      BOOL isSelectedEntryEditable = 
        ([[event links] editLink] != nil);

      [mDeleteEventButton setEnabled:isSelectedEntryEditable];
      [mEditEventButton setEnabled:isSelectedEntryEditable];
      
    } else {
      // zero or many selected events
      BOOL canBatchEdit = ([[mEventFeed links] batchLink] != nil);
      BOOL canDeleteAll = (canBatchEdit && numberOfSelectedEvents > 1);
      
      [mDeleteEventButton setEnabled:canDeleteAll];
      [mEditEventButton setEnabled:NO];
    }
  } else {
    // ACL segment is selected
    BOOL isEditableACLEntrySelected = 
      ([[[self selectedACLEntry] links] editLink] != nil);

    [mDeleteEventButton setEnabled:isEditableACLEntrySelected];
    [mEditEventButton setEnabled:isEditableACLEntrySelected];
    
    [mAddEventButton setEnabled:doesSelectedCalendarHaveACLFeed];
    [mQueryTodayEventButton setEnabled:NO];
  }
  
  // enable or disable the Events/ACL segment buttons
  [mEntrySegmentedControl setEnabled:isCalendarSelected 
                          forSegment:kEventsSegment];
  [mEntrySegmentedControl setEnabled:doesSelectedCalendarHaveACLFeed 
                          forSegment:kACLSegment];
}

- (NSString *)displayStringForACLEntry:(GDataEntryACL *)aclEntry  {
  
  // make a concise, readable string showing the scope type, scope value, 
  // and role value for an ACL entry, like:
  //
  //    scope: user "fred@flintstone.com"  role:owner
  
  NSMutableString *resultStr = [NSMutableString string];
  
  GDataACLScope *scope = [aclEntry scope];
  if (scope) {
    NSString *type = ([scope type] ? [scope type] : @"");
    NSString *value = @"";
    if ([scope value]) {
      value = [NSString stringWithFormat:@"\"%@\"", [scope value]];
    }
    [resultStr appendFormat:@"scope: %@ %@  ", type, value];
  }  
  
  GDataACLRole *role = [aclEntry role];
  if (role) {
    // for the role value, display only anything after the # character
    // since roles may be rather long, like
    // http://schemas.google.com/calendar/2005/role#collaborator
    
    NSString *value = [role value];
    
    NSRange poundRange = [value rangeOfString:@"#" options:NSBackwardsSearch];
    if (poundRange.location != NSNotFound 
        && [value length] > (1 + poundRange.location)) {
      value = [value substringFromIndex:(1 + poundRange.location)];
    }
    [resultStr appendFormat:@"role: %@", value];
  }
  return resultStr;  
}

#pragma mark IBActions

- (IBAction)getCalendarClicked:(id)sender {
  
  NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];

  NSString *username = [mUsernameField stringValue];
  username = [username stringByTrimmingCharactersInSet:whitespace];

  if ([username rangeOfString:@"@"].location == NSNotFound) {
    // if no domain was supplied, add @gmail.com
    username = [username stringByAppendingString:@"@gmail.com"];
  }
  
  [mUsernameField setStringValue:username];

  [self fetchAllCalendars];
}

- (IBAction)calendarSegmentClicked:(id)sender {
  // get the new calendar list for the selected segment
  [self getCalendarClicked:sender]; 
}

- (IBAction)addCalendarClicked:(id)sender {
  [self addACalendar];
}

- (IBAction)renameCalendarClicked:(id)sender {
  [self renameSelectedCalendar]; 
}

- (IBAction)deleteCalendarClicked:(id)sender {
  [self deleteSelectedCalendar];
}

- (IBAction)cancelCalendarFetchClicked:(id)sender {
  [mCalendarFetchTicket cancelTicket];
  [self setCalendarFetchTicket:nil];
  [self updateUI];
}

- (IBAction)cancelEventFetchClicked:(id)sender {
  [mEventFetchTicket cancelTicket];
  [self setEventFetchTicket:nil];
  [self updateUI];
}

- (IBAction)addEventClicked:(id)sender {
  if ([self isEventsSegmentSelected]) {
    [self addAnEvent];
  } else {
    [self addAnACLEntry]; 
  }
}

- (IBAction)editEventClicked:(id)sender {
  if ([self isEventsSegmentSelected]) {
    [self editSelectedEvent];
  } else {
    [self editSelectedACLEntry]; 
  }
}

- (IBAction)deleteEventClicked:(id)sender {
  if ([self isEventsSegmentSelected]) {
    [self deleteSelectedEvents];
  } else {
    [self deleteSelectedACLEntry];
  }
}

- (IBAction)queryTodayClicked:(id)sender {
  [self queryTodaysEvents];
}

- (IBAction)entrySegmentClicked:(id)sender {
  [self fetchSelectedCalendar];  
}

- (IBAction)loggingCheckboxClicked:(id)sender {
  [GDataHTTPFetcher setIsLoggingEnabled:[sender state]]; 
}

// logEntryXML is called when the user double-clicks on a calendar,
// event entry, or ACL entry
- (IBAction)logEntryXML:(id)sender {
  
  int row = [sender selectedRow];
  
  if (sender == mCalendarTable) {
    // get the calendar entry's title
    GDataEntryCalendar *calendar = [[mCalendarFeed entries] objectAtIndex:row];
    NSLog(@"%@", [calendar XMLElement]);
    
  } else if (sender == mEventTable) {
    
    if ([self isEventsSegmentSelected]) {
      // get the event entry's title
      GDataEntryCalendarEvent *eventEntry = [[mEventFeed entries] objectAtIndex:row];
      NSLog(@"%@", [eventEntry XMLElement]);
      
    } else {
      // get the ACL entry 
      if (mACLFeed) {
        GDataEntryACL *aclEntry = [[mACLFeed entries] objectAtIndex:row];
        NSLog(@"%@", [aclEntry XMLElement]);
      } 
    }
  }
}

#pragma mark -

// get a calendar service object with the current username/password
//
// A "service" object handles networking tasks.  Service objects
// contain user authentication information as well as networking
// state information (such as cookies and the "last modified" date for
// fetched data.)

- (GDataServiceGoogleCalendar *)calendarService {
  
  static GDataServiceGoogleCalendar* service = nil;
  
  if (!service) {
    service = [[GDataServiceGoogleCalendar alloc] init];
    
    [service setUserAgent:@"Google-SampleCalendarApp-1.0"];
    [service setShouldCacheDatedData:YES];
    [service setServiceShouldFollowNextLinks:YES];
  }

  // update the username/password each time the service is requested
  NSString *username = [mUsernameField stringValue];
  NSString *password = [mPasswordField stringValue];
  
  [service setUserCredentialsWithUsername:username
                                 password:password];
  
  return service;
}

// get the calendar selected in the top list, or nil if none
- (GDataEntryCalendar *)selectedCalendar {
  
  NSArray *calendars = [mCalendarFeed entries];
  int rowIndex = [mCalendarTable selectedRow];
  if ([calendars count] > 0 && rowIndex > -1) {
    
    GDataEntryCalendar *calendar = [calendars objectAtIndex:rowIndex];
    return calendar;
  }
  return nil;
}

// get the events selected in the bottom list, or nil if none
- (NSArray *)selectedEvents {
  
  if ([self isEventsSegmentSelected]) {
    
    NSIndexSet *indexes = [mEventTable selectedRowIndexes];
    NSArray *events = [mEventFeed entries];
    NSArray *selectedEvents = [events objectsAtIndexes:indexes];
    
    if ([selectedEvents count] > 0) {
      return selectedEvents;
    }
  }
  return nil;
}

- (GDataEntryCalendarEvent *)singleSelectedEvent {
  
  NSArray *selectedEvents = [self selectedEvents];
  if ([selectedEvents count] == 1) {
    return [selectedEvents objectAtIndex:0]; 
  }
  return nil;
}


// get the event selected in the bottom list, or nil if none
- (GDataEntryACL *)selectedACLEntry {
  
  if ([self isACLSegmentSelected]) {

    NSArray *entries = [mACLFeed entries];
    int rowIndex = [mEventTable selectedRow];
    if ([entries count] > 0 && rowIndex > -1) {
      
      GDataEntryACL *entry = [entries objectAtIndex:rowIndex];
      return entry;
    }
  }
  return nil;
}

- (BOOL)isACLSegmentSelected {
  return ([mEntrySegmentedControl selectedSegment] == kACLSegment);
}

- (BOOL)isEventsSegmentSelected {
  return ([mEntrySegmentedControl selectedSegment] == kEventsSegment);
}

#pragma mark Add/delete calendars

- (void)addACalendar {
  
  NSString *newCalendarName = [mCalendarNameField stringValue];
  
  NSURL *postURL = [[[mCalendarFeed links] postLink] URL];

  if ([newCalendarName length] > 0 && postURL != nil) {
    
    GDataServiceGoogleCalendar *service = [self calendarService];
    
    GDataEntryCalendar *newEntry = [GDataEntryCalendar calendarEntry];
    [newEntry setTitleWithString:newCalendarName];
    [newEntry setIsSelected:YES]; // check the calendar in the web display
    
    // as of Dec. '07 the server requires a color, 
    // or returns a 404 (Not Found) error
    [newEntry setColor:[GDataColorProperty valueWithString:@"#2952A3"]];

    [service fetchCalendarEntryByInsertingEntry:newEntry
                                     forFeedURL:postURL 
                                       delegate:self
                              didFinishSelector:@selector(addCalendarTicket:addedEntry:)
                                didFailSelector:@selector(addCalendarTicket:failedWithError:)];
  }
}

// calendar added successfully
- (void)addCalendarTicket:(GDataServiceTicket *)ticket
               addedEntry:(GDataEntryCalendar *)object {
  
  // tell the user that the add worked
  NSBeginAlertSheet(@"Added Calendar", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"Calendar added");
  
  [mCalendarNameField setStringValue:@""];
  
  // refetch the current calendars
  [self fetchAllCalendars];
  [self updateUI];
} 

// failure to add event
- (void)addCalendarTicket:(GDataServiceTicket *)ticket
          failedWithError:(NSError *)error {
  
  NSBeginAlertSheet(@"Add failed", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"Calendar add failed: %@", error);
  
}

- (void)renameSelectedCalendar {
  
  GDataEntryCalendar *selectedCalendar = [self selectedCalendar];
  NSString *newCalendarName = [mCalendarNameField stringValue];
  NSURL *editURL = [[[[self selectedCalendar] links] editLink] URL];

  if (selectedCalendar && editURL && [newCalendarName length] > 0) {
    
    // make the user confirm that the selected calendar should be renamed
    NSBeginAlertSheet(@"Rename calendar", @"Rename", @"Cancel", nil,
                      [self window], self, 
                      @selector(renameCalendarSheetDidEnd:returnCode:contextInfo:),
                      nil, nil, @"Rename the calendar \"%@\" as \"%@\"?",
                      [[selectedCalendar title] stringValue],
                      newCalendarName);
  }
}

- (void)renameCalendarSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
  
  if (returnCode == NSAlertDefaultReturn) {
    
    NSString *newCalendarName = [mCalendarNameField stringValue];
    NSURL *editURL = [[[[self selectedCalendar] links] editLink] URL];
    GDataEntryCalendar *selectedCalendar = [self selectedCalendar];
    
    GDataServiceGoogleCalendar *service = [self calendarService];
    
    // rename it
    [selectedCalendar setTitleWithString:newCalendarName];
    
    [service fetchCalendarEntryByUpdatingEntry:selectedCalendar
                                   forEntryURL:editURL
                                      delegate:self
                             didFinishSelector:@selector(renameCalendarTicket:renamedEntry:)
                               didFailSelector:@selector(renameCalendarTicket:failedWithError:)];
  }
}

// calendar renamed successfully
- (void)renameCalendarTicket:(GDataServiceTicket *)ticket
                renamedEntry:(GDataEntryCalendar *)object {
  
  // tell the user that the rename worked
  NSBeginAlertSheet(@"Renamed Calendar", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"Calendar renamed");
  
  // refetch the current calendars
  [self fetchAllCalendars];
  [self updateUI];
} 

// failure to rename event
- (void)renameCalendarTicket:(GDataServiceTicket *)ticket
             failedWithError:(NSError *)error {
  
  NSBeginAlertSheet(@"Rename failed", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"Calendar rename failed: %@", error);
  
}


- (void)deleteSelectedCalendar {
  
  GDataEntryCalendar *selectedCalendar = [self selectedCalendar];
  if (selectedCalendar) {
    // make the user confirm that the selected calendar should be deleted
    NSBeginAlertSheet(@"Delete calendar", @"Delete", @"Cancel", nil,
                      [self window], self, 
                      @selector(deleteCalendarSheetDidEnd:returnCode:contextInfo:),
                      nil, nil, @"Delete the calendar \"%@\"?",
                      [[selectedCalendar title] stringValue]);
  }
  
}

- (void)deleteCalendarSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
  
  if (returnCode == NSAlertDefaultReturn) {
    
    NSURL *editURL = [[[[self selectedCalendar] links] editLink] URL];
    
    if (editURL != nil) {
      
      GDataServiceGoogleCalendar *service = [self calendarService];
      
      [service deleteCalendarResourceURL:editURL
                                delegate:self
                       didFinishSelector:@selector(deleteCalendarTicket:deletedEntry:)
                         didFailSelector:@selector(deleteCalendarTicket:failedWithError:)];
    }
  }
}

// calendar deleted successfully
- (void)deleteCalendarTicket:(GDataServiceTicket *)ticket
                deletedEntry:(GDataEntryCalendar *)object {
  
  // tell the user that the delete worked
  NSBeginAlertSheet(@"Deleted Calendar", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"Calendar deleted");
  
  // refetch the current calendars
  [self fetchAllCalendars];
  [self updateUI];
} 

// failure to delete event
- (void)deleteCalendarTicket:(GDataServiceTicket *)ticket
             failedWithError:(NSError *)error {
  
  NSBeginAlertSheet(@"Delete failed", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"Calendar delete failed: %@", error);
  
}

#pragma mark Fetch all calendars

// begin retrieving the list of the user's calendars
- (void)fetchAllCalendars {
  
  [self setCalendarFeed:nil];
  [self setCalendarFetchError:nil];
  [self setCalendarFetchTicket:nil];
  
  [self setEventFeed:nil];
  [self setEventFetchError:nil];
  [self setEventFetchTicket:nil];

  [self setACLFeed:nil];
  [self setACLFetchError:nil];
  [self setACLFetchTicket:nil];
  
  GDataServiceGoogleCalendar *service = [self calendarService];
  GDataServiceTicket *ticket;
  
  int segment = [mCalendarSegmentedControl selectedSegment];
  NSString *feedURLString;

  // The sample app shows the default, non-editable feed of calendars,
  // and the "OwnCalendars" feed, which allows calendars to be inserted
  // and deleted.  We're not demonstrating the "AllCalendars" feed, which
  // allows subscriptions to non-owned calendars to be inserted and deleted,
  // just because it's a bit too complex to easily keep distinct from add/
  // delete in the user interface.
  
  if (segment == kAllCalendarsSegment) {
    feedURLString = kGDataGoogleCalendarDefaultFeed;
  } else {
    feedURLString = kGDataGoogleCalendarDefaultOwnCalendarsFeed;
  }
  
  ticket = [service fetchCalendarFeedWithURL:[NSURL URLWithString:feedURLString]
                                    delegate:self
                           didFinishSelector:@selector(calendarListFetchTicket:finishedWithFeed:)
                             didFailSelector:@selector(calendarListFetchTicket:failedWithError:)];
  
  [self setCalendarFetchTicket:ticket];
  
  [self updateUI];
}

//
// calendar list fetch callbacks
//

// finished calendar list successfully
- (void)calendarListFetchTicket:(GDataServiceTicket *)ticket
               finishedWithFeed:(GDataFeedCalendar *)object {
  [self setCalendarFeed:object];
  [self setCalendarFetchError:nil];    
  [self setCalendarFetchTicket:nil];

  [self updateUI];
  
} 

// failed
- (void)calendarListFetchTicket:(GDataServiceTicket *)ticket
                failedWithError:(NSError *)error {
  
  [self setCalendarFeed:nil];
  [self setCalendarFetchError:error];    
  [self setCalendarFetchTicket:nil];

  [self updateUI];
}

#pragma mark -

- (void)fetchSelectedCalendar {
  
  GDataEntryCalendar *calendar = [self selectedCalendar];
  if (calendar) {
    
    BOOL hasACL = ([[[self selectedCalendar] links] ACLLink] != nil);
    BOOL isDisplayingEvents = [self isEventsSegmentSelected];
    
    if (isDisplayingEvents || !hasACL) {
      [self fetchSelectedCalendarEvents];
    } else {
      [self fetchSelectedCalendarACLEntries]; 
    }
  }
}

#pragma mark Fetch a calendar's events 

// for the calendar selected in the top list, begin retrieving the list of
// events
- (void)fetchSelectedCalendarEvents {
  
  GDataEntryCalendar *calendar = [self selectedCalendar];
  if (calendar) {
    
    // fetch the events feed
    NSURL *feedURL = [[[calendar links] alternateLink] URL];
    if (feedURL) {
      
      [self setEventFeed:nil];
      [self setEventFetchError:nil];
      [self setEventFetchTicket:nil];
      
      GDataServiceGoogleCalendar *service = [self calendarService];
      GDataServiceTicket *ticket;
      ticket = [service fetchCalendarEventFeedWithURL:feedURL
                                             delegate:self
                                    didFinishSelector:@selector(calendarEventsTicket:finishedWithEntries:)
                                      didFailSelector:@selector(calendarEventsTicket:failedWithError:)];
      [self setEventFetchTicket:ticket];

      [self updateUI];
    }
  }
}

//
// entries list fetch callbacks
//

// fetched event list successfully
- (void)calendarEventsTicket:(GDataServiceTicket *)ticket
         finishedWithEntries:(GDataFeedCalendarEvent *)object {
  
  [self setEventFeed:object];
  [self setEventFetchError:nil];
  [self setEventFetchTicket:nil];
  
  [self updateUI];
} 

// failed
- (void)calendarEventsTicket:(GDataServiceTicket *)ticket
             failedWithError:(NSError *)error {
  
  [self setEventFeed:nil];
  [self setEventFetchError:error];
  [self setEventFetchTicket:nil];
  
  [self updateUI];
  
}

#pragma mark Add an event

- (void)addAnEvent {
  
  // make a new event
  GDataEntryCalendarEvent *newEvent = [GDataEntryCalendarEvent calendarEvent];
  
  // set a title and description (the author is the authenticated user adding
  // the entry)
  [newEvent setTitleWithString:@"Sample Added Event"];
  [newEvent setContentWithString:@"Description of sample added event"];
  
  // start time now, end time in an hour, reminder 10 minutes before
  NSDate *anHourFromNow = [NSDate dateWithTimeIntervalSinceNow:60*60];
  GDataDateTime *startDateTime = [GDataDateTime dateTimeWithDate:[NSDate date]
                                                        timeZone:[NSTimeZone systemTimeZone]];
  GDataDateTime *endDateTime = [GDataDateTime dateTimeWithDate:anHourFromNow
                                                      timeZone:[NSTimeZone systemTimeZone]];
  GDataReminder *reminder = [GDataReminder reminder];
  [reminder setMinutes:@"10"];
  
  GDataWhen *when = [GDataWhen whenWithStartTime:startDateTime
                                         endTime:endDateTime];
  [when addReminder:reminder];
  [newEvent addTime:when];
  
  // display the event edit dialog
  EditEventWindowController *controller = [[EditEventWindowController alloc] init];
  [controller runModalForTarget:self
                       selector:@selector(addEditControllerFinished:)
                          event:newEvent];
}

// callback from the edit event dialog
- (void)addEditControllerFinished:(EditEventWindowController *)addEventController {
  
  if ([addEventController wasSaveClicked]) {
    
    // insert the event into the selected calendar
    GDataEntryCalendarEvent *event = [addEventController event];
    if (event) {
      
      GDataServiceGoogleCalendar *service = [self calendarService];
      
      GDataEntryCalendar *calendar = [self selectedCalendar];
      NSURL *feedURL = [[[calendar links] alternateLink] URL];
      
      [service fetchCalendarEventByInsertingEntry:event
                                       forFeedURL:feedURL
                                         delegate:self
                                didFinishSelector:@selector(addEventTicket:addedEntry:)
                                  didFailSelector:@selector(addEventTicket:failedWithError:)];
    }
  }
  [addEventController autorelease];
}

// event added successfully
- (void)addEventTicket:(GDataServiceTicket *)ticket
            addedEntry:(GDataFeedCalendarEvent *)object {
  
  // tell the user that the add worked
  NSBeginAlertSheet(@"Added Event", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"Event added");
  
  // refetch the current calendar's events
  [self fetchSelectedCalendar];
  [self updateUI];
} 

// failure to add event
- (void)addEventTicket:(GDataServiceTicket *)ticket
       failedWithError:(NSError *)error {
  
  NSBeginAlertSheet(@"Add failed", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"Event add failed: %@", error);
  
}


#pragma mark Edit an event

- (void)editSelectedEvent {
  
  // display the event edit dialog
  GDataEntryCalendarEvent *event = [self singleSelectedEvent];
  if (event) {
    EditEventWindowController *controller = [[EditEventWindowController alloc] init];
    [controller runModalForTarget:self
                         selector:@selector(editControllerFinished:)
                            event:event];
  }
}

// callback from the edit event dialog
- (void)editControllerFinished:(EditEventWindowController *)editEventController {
  if ([editEventController wasSaveClicked]) {
    
    // update the event with the changed settings
    GDataEntryCalendarEvent *event = [editEventController event];
    if (event) {
      
      GDataLink *link = [[event links] editLink];
      
      GDataServiceGoogleCalendar *service = [self calendarService];
      [service fetchCalendarEventEntryByUpdatingEntry:event
                                          forEntryURL:[link URL]
                                             delegate:self
                                    didFinishSelector:@selector(editEventTicket:editedEntry:)
                                      didFailSelector:@selector(editEventTicket:failedWithError:)];
      
    }
  }
  [editEventController autorelease];
}

// event edited successfully
- (void)editEventTicket:(GDataServiceTicket *)ticket
            editedEntry:(GDataFeedCalendarEvent *)object {
  
  // tell the user that the update worked
  NSBeginAlertSheet(@"Updated Event", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"Event updated");
  
  // re-fetch the selected calendar's events
  [self fetchSelectedCalendar];
  [self updateUI];
} 

// failure to submit edited event
- (void)editEventTicket:(GDataServiceTicket *)ticket
        failedWithError:(NSError *)error {
  
  NSBeginAlertSheet(@"Update failed", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"Event update failed: %@", error);
  
}

#pragma mark Delete selected events

- (void)deleteSelectedEvents {
  
  NSArray *events = [self selectedEvents];
  unsigned int numberOfSelectedEvents = [events count];
  
  if (numberOfSelectedEvents == 1) {
    
    // 1 event selected
    GDataEntryCalendarEvent *event = [events objectAtIndex:0];
    
    // make the user confirm that the selected event should be deleted
    NSBeginAlertSheet(@"Delete Event", @"Delete", @"Cancel", nil,
                      [self window], self, 
                      @selector(deleteSheetDidEnd:returnCode:contextInfo:),
                      nil, nil, @"Delete the event \"%@\"?",
                      [event title]);
    
  } else if (numberOfSelectedEvents >= 1) {
    
    NSBeginAlertSheet(@"Delete Events", @"Delete", @"Cancel", nil,
                      [self window], self, 
                      @selector(batchDeleteSheetDidEnd:returnCode:contextInfo:),
                      nil, nil, @"Delete %d events?",
                      numberOfSelectedEvents);
  }
}

// delete dialog callback
- (void)deleteSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
  
  if (returnCode == NSAlertDefaultReturn) {
    
    // delete the event
    GDataEntryCalendarEvent *event = [self singleSelectedEvent];
    GDataLink *link = [[event links] editLink];
    
    if (link) {
      GDataServiceGoogleCalendar *service = [self calendarService];
      [service deleteCalendarResourceURL:[link URL]
                                delegate:self 
                       didFinishSelector:@selector(deleteTicket:deletedEntry:)
                         didFailSelector:@selector(deleteTicket:failedWithError:)];
    }
  }
}

// event deleted successfully
- (void)deleteTicket:(GDataServiceTicket *)ticket
        deletedEntry:(GDataFeedCalendarEvent *)object {
  
  NSBeginAlertSheet(@"Deleted Event", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"Event deleted");
  
  // re-fetch the selected calendar's events
  [self fetchSelectedCalendar];
  [self updateUI];
} 

// failure to delete event
- (void)deleteTicket:(GDataServiceTicket *)ticket
     failedWithError:(NSError *)error {
  
  NSBeginAlertSheet(@"Delete failed", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"Event delete failed: %@", error);
  
}

// delete dialog callback
- (void)batchDeleteSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
  
  if (returnCode == NSAlertDefaultReturn) {
    // delete the events
    [self batchDeleteSelectedEvents];
  }
}

- (void)batchDeleteSelectedEvents {
  
  NSArray *selectedEvents = [self selectedEvents];
  
  for (int idx = 0; idx < [selectedEvents count]; idx++) {
    
    GDataEntryCalendarEvent *event = [selectedEvents objectAtIndex:idx];
    
    // add a batch ID to this entry
    static int staticID = 0;
    NSString *batchID = [NSString stringWithFormat:@"batchID_%u", ++staticID];
    [event setBatchID:[GDataBatchID batchIDWithString:batchID]];
    
    // we don't need to add the batch operation to the entries since
    // we're putting it in the feed to apply to all entries
    
    // we could force an error on an item by nuking the entry's identifier
    //   if (idx == 1) { [event setIdentifier:nil]; }
  }

  NSURL *batchURL = [[[mEventFeed links] batchLink] URL];
  if (batchURL != nil && [selectedEvents count] > 0) {
    
    // make a batch feed object: add entries, and since
    // we are doing the same operation for all entries in the feed, 
    // add the operation
    
    GDataFeedCalendarEvent *batchFeed = [GDataFeedCalendarEvent calendarEventFeed];
    [batchFeed setEntriesWithEntries:selectedEvents];
    
    GDataBatchOperation *op = [GDataBatchOperation batchOperationWithType:kGDataBatchOperationDelete];
    [batchFeed setBatchOperation:op];    
    
    // now do the usual steps for authenticating for this service, and issue
    // the fetch
    
    GDataServiceGoogleCalendar *service = [self calendarService];
    
    [service fetchCalendarEventBatchFeedWithBatchFeed:batchFeed
                                      forBatchFeedURL:batchURL
                                             delegate:self
                                    didFinishSelector:@selector(batchDeleteTicket:finishedWithFeed:)
                                      didFailSelector:@selector(batchDeleteTicket:failedWithError:)];
  } else {
    // the button shouldn't be enabled when we can't batch delete, so we
    // shouldn't get here
    NSBeep();
  }
}

- (void)batchDeleteTicket:(GDataServiceTicket *)ticket
   finishedWithFeed:(GDataFeedCalendarEvent *)feed {
  
  // step through all the entries in the response feed, 
  // and build a string reporting each
  
  // show the http status to start (should be 200)
  NSMutableString *reportStr = [NSMutableString stringWithFormat:@"http status:%d\n\n", 
    [ticket statusCode]];
  
  NSArray *responseEntries = [feed entries];
  for (int idx = 0; idx < [responseEntries count]; idx++) {
    
    GDataEntryCalendarEvent *entry = [responseEntries objectAtIndex:idx];
    GDataBatchID *batchID = [entry batchID];
    
    // report the batch ID, entry title, and status for each item
    NSString *title= [[entry title] stringValue];
    [reportStr appendFormat:@"%@: %@\n", [batchID stringValue], title];
    
    GDataBatchInterrupted *interrupted = [entry batchInterrupted];
    if (interrupted) {
      [reportStr appendFormat:@"%@\n", [interrupted description]];
    }
    
    GDataBatchStatus *status = [entry batchStatus];
    if (status) {
      [reportStr appendFormat:@"%d %@\n", [[status code] intValue], [status reason]];
    }
    [reportStr appendString:@"\n"];
  }
  
  NSBeginAlertSheet(@"Batch delete completed", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"Delete completed.\n%@", reportStr);
  
  // re-fetch the selected calendar's events
  [self fetchSelectedCalendar];
  [self updateUI];
}

- (void)batchDeleteTicket:(GDataServiceTicket *)ticket
          failedWithError:(NSError *)error {
  
  NSBeginAlertSheet(@"Batch delete failed", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"Delete failed: %@", error);  
  
  [self updateUI];
}


#pragma mark Query today's events

// utility routine to make a GDataDateTime object for sometime today
- (GDataDateTime *)dateTimeForTodayAtHour:(int)hour
                                   minute:(int)minute
                                   second:(int)second {
  
  int const kComponentBits = (NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit
                              | NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit);
  
  NSCalendar *cal = [[[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar] autorelease];
  
  NSDateComponents *dateComponents = [cal components:kComponentBits fromDate:[NSDate date]];
  [dateComponents setHour:hour];
  [dateComponents setMinute:minute];
  [dateComponents setSecond:second];
  
  GDataDateTime *dateTime = [GDataDateTime dateTimeWithDate:[NSDate date]
                                                   timeZone:[NSTimeZone systemTimeZone]];
  [dateTime setDateComponents:dateComponents];
  return dateTime;
}

// submit a query about today's events in the selected calendar
- (void)queryTodaysEvents {

  GDataServiceGoogleCalendar *service = [self calendarService];
  
  GDataEntryCalendar *calendar = [self selectedCalendar];
  NSURL *feedURL = [[[calendar links] alternateLink] URL];

  // make start and end times for today, at the beginning and end of the day
  
  GDataDateTime *startOfDay = [self dateTimeForTodayAtHour:0 minute:0 second:0];
  GDataDateTime *endOfDay = [self dateTimeForTodayAtHour:23 minute:59 second:59];
  
  // make the query
  GDataQueryCalendar* queryCal = [GDataQueryCalendar calendarQueryWithFeedURL:feedURL];
  [queryCal setStartIndex:1];
  [queryCal setMaxResults:10];
  [queryCal setMinimumStartTime:startOfDay]; 
  [queryCal setMaximumStartTime:endOfDay];

  [service fetchCalendarEventFeedWithURL:[queryCal URL]
                                delegate:self
                       didFinishSelector:@selector(queryTicket:finishedWithEntries:)
                         didFailSelector:@selector(queryTicket:failedWithError:)];
}

// today's events successfully retrieved
- (void)queryTicket:(GDataServiceTicket *)ticket
finishedWithEntries:(GDataFeedCalendarEvent *)object {
  
  NSArray *entries = [object entries];
  
  // make a comma-separate list of the event titles to display
  NSMutableArray *titles = [NSMutableArray array];
  
  for (int idx = 0; idx < [entries count]; idx++) {
    GDataEntryCalendarEvent *event = [entries objectAtIndex:idx];
    NSString *title = [[event title] stringValue];
    if ([title length] > 0) {
      [titles addObject:title];
    }
  }
  
  NSString *resultStr = [titles componentsJoinedByString:@", "];
  
  NSBeginAlertSheet(@"Query ", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"Query result: %@", resultStr);
  
} 

// failure to fetch today's events
- (void)queryTicket:(GDataServiceTicket *)ticket
    failedWithError:(NSError *)error {
  
  NSBeginAlertSheet(@"Query failed", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"Query failed: %@", error);
  
}

////////////////////////////////////////////////////////
#pragma mark ACL

- (void)fetchSelectedCalendarACLEntries {
  
  GDataEntryCalendar *calendar = [self selectedCalendar];
  if (calendar) {
    
    NSURL *aclFeedURL = [[[calendar links] ACLLink] URL];
    if (aclFeedURL) {
      
      // fetch the ACL feed
      [self setACLFeed:nil];
      [self setACLFetchError:nil];
      [self setACLFetchTicket:nil];
        
      GDataServiceGoogleCalendar *service = [self calendarService];
      GDataServiceTicket *ticket;
      ticket = [service fetchAuthenticatedFeedWithURL:aclFeedURL
                                            feedClass:kGDataUseRegisteredClass
                                             delegate:self
                                    didFinishSelector:@selector(calendarACLTicket:finishedWithEntries:)
                                      didFailSelector:@selector(calendarACLTicket:failedWithError:)];
      
      [self setACLFetchTicket:ticket];
      
      [self updateUI];
    }
  }
}


// fetched acl list successfully
- (void)calendarACLTicket:(GDataServiceTicket *)ticket
      finishedWithEntries:(GDataFeedACL *)object {
  
  [self setACLFeed:object];
  [self setACLFetchError:nil];
  [self setACLFetchTicket:nil];
  
  [self updateUI];
} 

// failed
- (void)calendarACLTicket:(GDataServiceTicket *)ticket
          failedWithError:(NSError *)error {
  
  [self setACLFeed:nil];
  [self setACLFetchError:error];
  [self setACLFetchTicket:nil];
  
  [self updateUI];
  
}


#pragma mark Add an ACL entry

- (void)addAnACLEntry {
  
  // make a new entry
  NSString *email = @"fred.flintstone@bounce.spuriousmail.com";
  
  GDataACLScope *scope = [GDataACLScope scopeWithType:@"user"
                                                value:email];
  GDataACLRole *role = [GDataACLRole roleWithValue:kGDataRoleCalendarRead];
  
  GDataEntryACL *newEntry = [GDataEntryACL ACLEntryWithScope:scope role:role];
  
  // display the ACL edit dialog
  EditACLWindowController *controller = [[EditACLWindowController alloc] init];
  [controller runModalForTarget:self
                       selector:@selector(addACLEditControllerFinished:)
                       ACLEntry:newEntry];
}

// callback from the edit ACL dialog
- (void)addACLEditControllerFinished:(EditACLWindowController *)addACLController {
  
  if ([addACLController wasSaveClicked]) {
    
    // insert the ACL into the selected calendar
    GDataEntryACL *entry = [addACLController ACLEntry];
    if (entry) {
      
      GDataServiceGoogleCalendar *service = [self calendarService];
      
      GDataEntryCalendar *calendar = [self selectedCalendar];
      NSURL *feedURL = [[[calendar links] ACLLink] URL];
      
      if (feedURL) {
        [service fetchAuthenticatedEntryByInsertingEntry:entry
                                              forFeedURL:feedURL
                                                delegate:self
                                       didFinishSelector:@selector(addACLEntryTicket:addedEntry:)
                                         didFailSelector:@selector(addACLEntryTicket:failedWithError:)];
      }
    }
  }
  [addACLController autorelease];
}

// event added successfully
- (void)addACLEntryTicket:(GDataServiceTicket *)ticket
               addedEntry:(GDataFeedACL *)object {
  
  // tell the user that the add worked
  NSBeginAlertSheet(@"Added ACL Entry", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"ACL Entry added");
  
  // refetch the current calendar's ACL entries
  [self fetchSelectedCalendar];
  [self updateUI];
} 

// failure to add ACLEntry
- (void)addACLEntryTicket:(GDataServiceTicket *)ticket
          failedWithError:(NSError *)error {
  
  NSBeginAlertSheet(@"Add failed", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"ACL Entry add failed: %@", error);
  
}


#pragma mark Edit an ACLEntry

- (void)editSelectedACLEntry {
  
  // display the ACLEntry edit dialog
  GDataEntryACL *entry = [self selectedACLEntry];
  if (entry) {
    EditACLWindowController *controller = [[EditACLWindowController alloc] init];
    [controller runModalForTarget:self
                         selector:@selector(ACLEditControllerFinished:)
                         ACLEntry:entry];
  }
}

// callback from the edit ACLEntry dialog
- (void)ACLEditControllerFinished:(EditACLWindowController *)editACLEntryController {
  if ([editACLEntryController wasSaveClicked]) {
    
    // update the ACLEntry with the changed settings
    GDataEntryACL *entry = [editACLEntryController ACLEntry];
    if (entry) {
      
      GDataLink *link = [[entry links] editLink];
      if (link) {
        GDataServiceGoogleCalendar *service = [self calendarService];
        [service fetchAuthenticatedEntryByUpdatingEntry:entry
                                            forEntryURL:[link URL]
                                               delegate:self
                                      didFinishSelector:@selector(editACLEntryTicket:editedEntry:)
                                        didFailSelector:@selector(editACLEntryTicket:failedWithError:)];
      }
    }
  }
  [editACLEntryController autorelease];
}

// ACLEntry edited successfully
- (void)editACLEntryTicket:(GDataServiceTicket *)ticket
               editedEntry:(GDataFeedACL *)object {
  
  // tell the user that the update worked
  NSBeginAlertSheet(@"Updated ACLEntry", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"ACL Entry updated");
  
  // re-fetch the selected calendar's ACLEntries
  [self fetchSelectedCalendar];
  [self updateUI];
} 

// failure to submit edited ACL Entry
- (void)editACLEntryTicket:(GDataServiceTicket *)ticket
           failedWithError:(NSError *)error {
  
  NSBeginAlertSheet(@"Update failed", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"ACLEntry update failed: %@", error);
  
}

#pragma mark Delete an ACL Entry

- (void)deleteSelectedACLEntry {
  
  GDataEntryACL *entry = [self selectedACLEntry];
  if (entry) {
    // make the user confirm that the selected ACLEntry should be deleted
    NSBeginAlertSheet(@"Delete ACLEntry", @"Delete", @"Cancel", nil,
                      [self window], self, 
                      @selector(deleteACLSheetDidEnd:returnCode:contextInfo:),
                      nil, nil, @"Delete the ACL entry \"%@\"?",
                      [entry description]);
  }
}

// delete dialog callback
- (void)deleteACLSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
  
  if (returnCode == NSAlertDefaultReturn) {
    
    // delete the ACLEntry
    GDataEntryACL *entry = [self selectedACLEntry];
    GDataLink *link = [[entry links] editLink];
    
    if (link) {
      GDataServiceGoogleCalendar *service = [self calendarService];
      [service deleteAuthenticatedResourceURL:[link URL]
                                     delegate:self 
                            didFinishSelector:@selector(deleteACLEntryTicket:deletedEntry:)
                              didFailSelector:@selector(deleteACLEntryTicket:failedWithError:)];
    }
  }
}

// ACLEntry deleted successfully
- (void)deleteACLEntryTicket:(GDataServiceTicket *)ticket
                deletedEntry:(GDataFeedACL *)object {
  
  NSBeginAlertSheet(@"Deleted ACLEntry", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"ACL Entry deleted");
  
  // re-fetch the selected calendar's events
  [self fetchSelectedCalendar];
  [self updateUI];
} 

// failure to delete event
- (void)deleteACLEntryTicket:(GDataServiceTicket *)ticket
             failedWithError:(NSError *)error {
  
  NSBeginAlertSheet(@"Delete failed", nil, nil, nil,
                    [self window], nil, nil,
                    nil, nil, @"ACL Entry delete failed: %@", error);
}

#pragma mark TableView delegate methods
//
// table view delegate methods
//

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  
  if ([notification object] == mCalendarTable) {
    // the user clicked on a calendar, so fetch its events
    
    // if the calendar lacks an ACL feed, select the events segment;
    // the updateUI routine will disable the ACL segment for us
    BOOL doesSelectedCalendarHaveACLFeed = 
      ([[[self selectedCalendar] links] ACLLink] != nil);
    
    if (!doesSelectedCalendarHaveACLFeed) {
      [mEntrySegmentedControl setSelectedSegment:kEventsSegment]; 
    }
    
    [self fetchSelectedCalendar];
  } else {
    // the user clicked on an event or an ACL entry; 
    // just display it below the entry table
    
    [self updateUI]; 
  }
}

// table view data source methods
- (int)numberOfRowsInTableView:(NSTableView *)tableView {
  if (tableView == mCalendarTable) {
    return [[mCalendarFeed entries] count];
  } else {
    // entry table
    if ([self isEventsSegmentSelected]) {
      return [[mEventFeed entries] count];
    } else {
      return [[mACLFeed entries] count]; 
    }
  }
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(int)row {
  if (tableView == mCalendarTable) {
    // get the calendar entry's title
    GDataEntryCalendar *calendar = [[mCalendarFeed entries] objectAtIndex:row];
    return [[calendar title] stringValue];
  } else {
    
    if ([self isEventsSegmentSelected]) {
      // get the event entry's title
      GDataEntryCalendarEvent *eventEntry = [[mEventFeed entries] objectAtIndex:row];
      return [[eventEntry title] stringValue];
      
    } else {
      // get the ACL entry 
      if (mACLFeed) {
        GDataEntryACL *aclEntry = [[mACLFeed entries] objectAtIndex:row];
        return [self displayStringForACLEntry:aclEntry];
        
      } 
    }
  }
  return nil;
}

#pragma mark Control delegate methods

- (void)controlTextDidChange:(NSNotification *)note {
    
  [self updateUI]; // enabled/disable the Add Calendar button
}

#pragma mark Setters and Getters

- (GDataFeedCalendar *)calendarFeed {
  return mCalendarFeed; 
}

- (void)setCalendarFeed:(GDataFeedCalendar *)feed {
  [mCalendarFeed autorelease];
  mCalendarFeed = [feed retain];
}

- (NSError *)calendarFetchError {
  return mCalendarFetchError; 
}

- (void)setCalendarFetchError:(NSError *)error {
  [mCalendarFetchError release];
  mCalendarFetchError = [error retain];
}

- (GDataServiceTicket *)calendarFetchTicket {
  return mCalendarFetchTicket; 
}

- (void)setCalendarFetchTicket:(GDataServiceTicket *)ticket {
  [mCalendarFetchTicket release];
  mCalendarFetchTicket = [ticket retain];
}

- (GDataFeedCalendarEvent *)eventFeed {
  return mEventFeed; 
}

- (void)setEventFeed:(GDataFeedCalendarEvent *)feed {
  [mEventFeed autorelease];
  mEventFeed = [feed retain];
}

- (NSError *)eventFetchError {
  return mEventFetchError; 
}

- (void)setEventFetchError:(NSError *)error {
  [mEventFetchError release];
  mEventFetchError = [error retain];
}

- (GDataServiceTicket *)eventFetchTicket {
  return mEventFetchTicket; 
}

- (void)setEventFetchTicket:(GDataServiceTicket *)ticket {
  [mEventFetchTicket release];
  mEventFetchTicket = [ticket retain];
}

- (GDataFeedACL *)ACLFeed {
  return mACLFeed; 
}

- (void)setACLFeed:(GDataFeedACL *)feed {
  [mACLFeed autorelease];
  mACLFeed = [feed retain];
}

- (NSError *)ACLFetchError {
  return mACLFetchError; 
}

- (void)setACLFetchError:(NSError *)error {
  [mACLFetchError release];
  mACLFetchError = [error retain];
}

- (GDataServiceTicket *)ACLFetchTicket {
  return mACLFetchTicket; 
}

- (void)setACLFetchTicket:(GDataServiceTicket *)ticket {
  [mACLFetchTicket release];
  mACLFetchTicket = [ticket retain];
}
@end
