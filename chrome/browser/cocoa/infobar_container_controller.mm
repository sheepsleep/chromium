// Copyright (c) 2009 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "base/logging.h"
#include "base/mac_util.h"
#import "chrome/browser/cocoa/animatable_view.h"
#include "chrome/browser/cocoa/infobar.h"
#import "chrome/browser/cocoa/infobar_container_controller.h"
#import "chrome/browser/cocoa/infobar_controller.h"
#include "chrome/browser/cocoa/tab_strip_model_observer_bridge.h"
#include "chrome/browser/tab_contents/infobar_delegate.h"
#include "chrome/browser/tab_contents/tab_contents.h"
#include "chrome/common/notification_service.h"
#include "skia/ext/skia_utils_mac.h"

// C++ class that receives INFOBAR_ADDED and INFOBAR_REMOVED
// notifications and proxies them back to |controller|.
class InfoBarNotificationObserver : public NotificationObserver {
 public:
  InfoBarNotificationObserver(InfoBarContainerController* controller)
      : controller_(controller) {
  }

 private:
  // NotificationObserver implementation
  void Observe(NotificationType type,
               const NotificationSource& source,
               const NotificationDetails& details) {
    switch (type.value) {
      case NotificationType::TAB_CONTENTS_INFOBAR_ADDED:
        [controller_ addInfoBar:Details<InfoBarDelegate>(details).ptr()
                        animate:YES];
        break;
      case NotificationType::TAB_CONTENTS_INFOBAR_REMOVED:
        [controller_
          closeInfoBarsForDelegate:Details<InfoBarDelegate>(details).ptr()
                           animate:YES];
        break;
      case NotificationType::TAB_CONTENTS_INFOBAR_REPLACED: {
        typedef std::pair<InfoBarDelegate*, InfoBarDelegate*>
            InfoBarDelegatePair;
        InfoBarDelegatePair* delegates =
            Details<InfoBarDelegatePair>(details).ptr();
        [controller_
         replaceInfoBarsForDelegate:delegates->first with:delegates->second];
        break;
      }
      default:
        NOTREACHED();  // we don't ask for anything else!
        break;
    }

    [controller_ positionInfoBarsAndRedraw];
  }

  InfoBarContainerController* controller_;  // weak, owns us.
};


@interface InfoBarContainerController (PrivateMethods)
// Returns the desired height of the container view, computed by
// adding together the heights of all its subviews.
- (CGFloat)desiredHeight;

// Modifies this container to display infobars for the given
// |contents|.  Registers for INFOBAR_ADDED and INFOBAR_REMOVED
// notifications for |contents|.  If we are currently showing any
// infobars, removes them first and deregisters for any
// notifications.  |contents| can be NULL, in which case no infobars
// are shown and no notifications are registered for.
- (void)changeTabContents:(TabContents*)contents;

@end


@implementation InfoBarContainerController
- (id)initWithTabStripModel:(TabStripModel*)model
             resizeDelegate:(id<ViewResizer>)resizeDelegate {
  DCHECK(resizeDelegate);
  if ((self = [super initWithNibName:@"InfoBarContainer"
                              bundle:mac_util::MainAppBundle()])) {
    resizeDelegate_ = resizeDelegate;
    tabObserver_.reset(new TabStripModelObserverBridge(model, self));
    infoBarObserver_.reset(new InfoBarNotificationObserver(self));

    // NSMutableArray needs an initial capacity, and we rarely ever see
    // more than two infobars at a time, so that seems like a good choice.
    infobarControllers_.reset([[NSMutableArray alloc] initWithCapacity:2]);
  }
  return self;
}

- (void)dealloc {
  DCHECK([infobarControllers_ count] == 0);
  [super dealloc];
}

- (void)removeDelegate:(InfoBarDelegate*)delegate {
  DCHECK(currentTabContents_);
  currentTabContents_->RemoveInfoBar(delegate);
}

- (void)removeController:(InfoBarController*)controller {
  if (![infobarControllers_ containsObject:controller])
    return;

  // This code can be executed while InfoBarController is still on the stack, so
  // we retain and autorelease the controller to prevent it from being
  // dealloc'ed too early.
  [[controller retain] autorelease];
  [[controller view] removeFromSuperview];
  [infobarControllers_ removeObject:controller];
  [self positionInfoBarsAndRedraw];
}

// TabStripModelObserverBridge notifications
- (void)selectTabWithContents:(TabContents*)newContents
             previousContents:(TabContents*)oldContents
                      atIndex:(NSInteger)index
                  userGesture:(bool)wasUserGesture {
  [self changeTabContents:newContents];
}

- (void)tabDetachedWithContents:(TabContents*)contents
                        atIndex:(NSInteger)index {
  if (currentTabContents_ == contents)
    [self changeTabContents:NULL];
}

- (void)resizeView:(NSView*)view newHeight:(CGFloat)height {
  NSRect frame = [view frame];
  frame.size.height = height;
  [view setFrame:frame];
  [self positionInfoBarsAndRedraw];
}

- (void)setAnimationInProgress:(BOOL)inProgress {
  if ([resizeDelegate_ respondsToSelector:@selector(setAnimationInProgress:)])
    [resizeDelegate_ setAnimationInProgress:inProgress];
}

@end

@implementation InfoBarContainerController (PrivateMethods)

- (CGFloat)desiredHeight {
  CGFloat height = 0;
  for (InfoBarController* controller in infobarControllers_.get())
    height += NSHeight([[controller view] frame]);
  return height;
}

- (void)changeTabContents:(TabContents*)contents {
  registrar_.RemoveAll();
  [self removeAllInfoBars];

  currentTabContents_ = contents;
  if (currentTabContents_) {
    for (int i = 0; i < currentTabContents_->infobar_delegate_count(); ++i) {
      [self addInfoBar:currentTabContents_->GetInfoBarDelegateAt(i)
               animate:NO];
    }

    Source<TabContents> source(currentTabContents_);
    registrar_.Add(infoBarObserver_.get(),
                   NotificationType::TAB_CONTENTS_INFOBAR_ADDED, source);
    registrar_.Add(infoBarObserver_.get(),
                   NotificationType::TAB_CONTENTS_INFOBAR_REMOVED, source);
    registrar_.Add(infoBarObserver_.get(),
                   NotificationType::TAB_CONTENTS_INFOBAR_REPLACED, source);
  }

  [self positionInfoBarsAndRedraw];
}

- (void)addInfoBar:(InfoBarDelegate*)delegate animate:(BOOL)animate {
  scoped_ptr<InfoBar> infobar(delegate->CreateInfoBar());
  InfoBarController* controller = infobar->controller();
  [controller setContainerController:self];
  [[controller animatableView] setResizeDelegate:self];
  [[self view] addSubview:[controller view]];
  [infobarControllers_ addObject:[controller autorelease]];

  if (animate)
    [controller animateOpen];
  else
    [controller open];
}

- (void)closeInfoBarsForDelegate:(InfoBarDelegate*)delegate
                         animate:(BOOL)animate {
  for (InfoBarController* controller in
       [NSArray arrayWithArray:infobarControllers_.get()]) {
    if ([controller delegate] == delegate) {
      if (animate)
        [controller animateClosed];
      else
        [controller close];
    }
  }
}

- (void)replaceInfoBarsForDelegate:(InfoBarDelegate*)old_delegate
                              with:(InfoBarDelegate*)new_delegate {
  [self closeInfoBarsForDelegate:old_delegate animate:NO];
  [self addInfoBar:new_delegate animate:NO];
}

- (void)removeAllInfoBars {
  for (InfoBarController* controller in infobarControllers_.get()) {
    [[controller animatableView] stopAnimation];
    [[controller view] removeFromSuperview];
  }
  [infobarControllers_ removeAllObjects];
}

- (void)positionInfoBarsAndRedraw {
  NSRect containerBounds = [[self view] bounds];
  int minY = 0;

  // Stack the infobars at the bottom of the view, starting with the
  // last infobar and working our way to the front of the array.  This
  // way we ensure that the first infobar added shows up on top, with
  // the others below.
  for (InfoBarController* controller in
           [infobarControllers_ reverseObjectEnumerator]) {
    NSView* view = [controller view];
    NSRect frame = [view frame];
    frame.origin.x = NSMinX(containerBounds);
    frame.size.width = NSWidth(containerBounds);
    frame.origin.y = minY;
    minY += frame.size.height;
    [view setFrame:frame];
  }

  [resizeDelegate_ resizeView:[self view] newHeight:[self desiredHeight]];
}

@end
