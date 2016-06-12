#import "Cocoa/Cocoa.h"
#import "types.h"
#include "axlib/axlib.h"
#include "border.h"

extern void UpdateActiveSpace();
extern screen_info *GetDisplayOfWindow(window_info *Window);
extern void SetKwmFocus(AXUIElementRef WindowRef);
extern void GiveFocusToScreen(unsigned int ScreenIndex, tree_node *Focus, bool Mouse, bool UpdateFocus);
extern window_info *GetWindowByID(int WindowID);
extern space_info *GetActiveSpaceOfScreen(screen_info *Screen);
extern tree_node *GetTreeNodeFromWindowIDOrLinkNode(tree_node *RootNode, int WindowID);
extern bool IsWindowFloating(int WindowID, int *Index);
extern bool IsFocusedWindowFloating();
extern void ClearFocusedWindow();
extern void ClearMarkedWindow();
extern bool FocusWindowOfOSX();
extern int GetSpaceFromName(screen_info *Screen, std::string Name);

extern kwm_focus KWMFocus;
extern kwm_screen KWMScreen;
extern kwm_thread KWMThread;

int GetActiveSpaceOfDisplay(screen_info *Screen)
{
    int CurrentSpace = -1;
    NSString *CurrentIdentifier = (__bridge NSString *)Screen->Identifier;

    CFArrayRef ScreenDictionaries = CGSCopyManagedDisplaySpaces(CGSDefaultConnection);
    for(NSDictionary *ScreenDictionary in (__bridge NSArray *)ScreenDictionaries)
    {
        NSString *ScreenIdentifier = ScreenDictionary[@"Display Identifier"];
        if ([ScreenIdentifier isEqualToString:CurrentIdentifier])
        {
            CurrentSpace = [ScreenDictionary[@"Current Space"][@"id64"] intValue];
            break;
        }
    }

    CFRelease(ScreenDictionaries);
    return CurrentSpace;
}

int GetNumberOfSpacesOfDisplay(screen_info *Screen)
{
    int Result = 0;
    NSString *CurrentIdentifier = (__bridge NSString *)Screen->Identifier;

    CFArrayRef ScreenDictionaries = CGSCopyManagedDisplaySpaces(CGSDefaultConnection);
    for(NSDictionary *ScreenDictionary in (__bridge NSArray *)ScreenDictionaries)
    {
        NSString *ScreenIdentifier = ScreenDictionary[@"Display Identifier"];
        if ([ScreenIdentifier isEqualToString:CurrentIdentifier])
        {
            NSArray *Spaces = ScreenDictionary[@"Spaces"];
            Result = CFArrayGetCount((__bridge CFArrayRef)Spaces);
        }
    }

    CFRelease(ScreenDictionaries);
    return Result;
}

int GetSpaceNumberFromCGSpaceID(screen_info *Screen, int CGSpaceID) { }

int GetCGSpaceIDFromSpaceNumber(screen_info *Screen, int SpaceID) {
}

extern "C" int CGSRemoveWindowsFromSpaces(int cid, CFArrayRef windows, CFArrayRef spaces);
extern "C" int CGSAddWindowsToSpaces(int cid, CFArrayRef windows, CFArrayRef spaces);
extern "C" void CGSHideSpaces(int cid, CFArrayRef spaces);
extern "C" void CGSShowSpaces(int cid, CFArrayRef spaces);
extern "C" void CGSManagedDisplaySetIsAnimating(int cid, CFStringRef display, bool animating);
extern "C" void CGSManagedDisplaySetCurrentSpace(int cid, CFStringRef display, int space);

void ActivateSpaceWithoutTransition(std::string SpaceID)
{
    if(KWMScreen.Current)
    {
        int TotalSpaces = GetNumberOfSpacesOfDisplay(KWMScreen.Current);
        int ActiveSpace = GetSpaceNumberFromCGSpaceID(KWMScreen.Current, KWMScreen.Current->ActiveSpace);
        int DestinationSpaceID = ActiveSpace;
        if(SpaceID == "left")
        {
            DestinationSpaceID = ActiveSpace > 1 ? ActiveSpace-1 : 1;
        }
        else if(SpaceID == "right")
        {
            DestinationSpaceID = ActiveSpace < TotalSpaces ? ActiveSpace+1 : TotalSpaces;
        }
        else
        {
            int LookupSpace = GetSpaceFromName(KWMScreen.Current, SpaceID);
            if(LookupSpace != -1)
                DestinationSpaceID = GetSpaceNumberFromCGSpaceID(KWMScreen.Current, LookupSpace);
            else
                DestinationSpaceID = std::atoi(SpaceID.c_str());
        }

        if(DestinationSpaceID != ActiveSpace &&
           DestinationSpaceID > 0 && DestinationSpaceID <= TotalSpaces)
        {
            int CGSpaceID = GetCGSpaceIDFromSpaceNumber(KWMScreen.Current, DestinationSpaceID);
            NSArray *NSArraySourceSpace = @[ @(KWMScreen.Current->ActiveSpace) ];
            NSArray *NSArrayDestinationSpace = @[ @(CGSpaceID) ];
            KWMScreen.Transitioning = true;
            CGSManagedDisplaySetIsAnimating(CGSDefaultConnection, KWMScreen.Current->Identifier, true);
            CGSShowSpaces(CGSDefaultConnection, (__bridge CFArrayRef)NSArrayDestinationSpace);
            CGSHideSpaces(CGSDefaultConnection, (__bridge CFArrayRef)NSArraySourceSpace);
            CGSManagedDisplaySetCurrentSpace(CGSDefaultConnection, KWMScreen.Current->Identifier, CGSpaceID);
            CGSManagedDisplaySetIsAnimating(CGSDefaultConnection, KWMScreen.Current->Identifier, false);
        }
    }
}

void RemoveWindowFromSpace(int SpaceID, int WindowID)
{
    NSArray *NSArrayWindow = @[ @(WindowID) ];
    NSArray *NSArraySourceSpace = @[ @(SpaceID) ];
    CGSRemoveWindowsFromSpaces(CGSDefaultConnection, (__bridge CFArrayRef)NSArrayWindow, (__bridge CFArrayRef)NSArraySourceSpace);
}

void AddWindowToSpace(int SpaceID, int WindowID)
{
    NSArray *NSArrayWindow = @[ @(WindowID) ];
    NSArray *NSArrayDestinationSpace = @[ @(SpaceID) ];
    CGSAddWindowsToSpaces(CGSDefaultConnection, (__bridge CFArrayRef)NSArrayWindow, (__bridge CFArrayRef)NSArrayDestinationSpace);
}

void MoveWindowBetweenSpaces(int SourceSpaceID, int DestinationSpaceID, int WindowID)
{
    int SourceCGSpaceID = GetCGSpaceIDFromSpaceNumber(KWMScreen.Current, SourceSpaceID);
    int DestinationCGSpaceID = GetCGSpaceIDFromSpaceNumber(KWMScreen.Current, DestinationSpaceID);
    RemoveWindowFromSpace(SourceCGSpaceID, WindowID);
    AddWindowToSpace(DestinationCGSpaceID, WindowID);
}

void MoveFocusedWindowToSpace(std::string SpaceID)
{
    if(KWMScreen.Current && KWMFocus.Window)
    {
        int TotalSpaces = GetNumberOfSpacesOfDisplay(KWMScreen.Current);
        int ActiveSpace = GetSpaceNumberFromCGSpaceID(KWMScreen.Current, KWMScreen.Current->ActiveSpace);
        int DestinationSpaceID = ActiveSpace;
        if(SpaceID == "left")
        {
            DestinationSpaceID = ActiveSpace > 1 ? ActiveSpace-1 : 1;
        }
        else if(SpaceID == "right")
        {
            DestinationSpaceID = ActiveSpace < TotalSpaces ? ActiveSpace+1 : TotalSpaces;
        }
        else
        {
            int LookupSpace = GetSpaceFromName(KWMScreen.Current, SpaceID);
            if(LookupSpace != -1)
                DestinationSpaceID = GetSpaceNumberFromCGSpaceID(KWMScreen.Current, LookupSpace);
            else
                DestinationSpaceID = std::atoi(SpaceID.c_str());
        }

        MoveWindowBetweenSpaces(ActiveSpace, DestinationSpaceID, KWMFocus.Window->WID);
    }
}

bool IsWindowOnSpace(int WindowID, int CGSpaceID)
{
    NSArray *NSArrayWindow = @[ @(WindowID) ];
    CFArrayRef Spaces = CGSCopySpacesForWindows(CGSDefaultConnection, 7, (__bridge CFArrayRef)NSArrayWindow);
    int NumberOfSpaces = CFArrayGetCount(Spaces);
    for(int Index = 0; Index < NumberOfSpaces; ++Index)
    {
        NSNumber *ID = (__bridge NSNumber*)CFArrayGetValueAtIndex(Spaces, Index);
        if(CGSpaceID == [ID intValue])
            return true;
    }

    return false;
}
