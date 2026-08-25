# Non-Sandboxed Full Access Floating Shelf Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a non-sandboxed, fully-featured menu bar manager with a floating sub-bar that uses Accessibility (`AXUIElement`) and `CGEvent` mouse click injection to open live, authentic system tray menus without Notch clipping or App Store sandbox limitations.

**Architecture:**
1. CleanBar runs outside the App Sandbox with Accessibility permissions (`AXIsProcessTrusted`).
2. CleanBar hosts a clean 24px Eye icon on the menu bar.
3. On hover or click, a frosted glass floating sub-bar opens right below the menu bar (underneath the notch).
4. The floating sub-bar displays all active menu bar utility items with live status and tooltips.
5. Clicking an item sends a native `CGEvent` click to the actual status item's screen coordinates, opening the real live system dropdown menu (e.g. Battery, Little Snitch, Wi-Fi, Docker).

**Tech Stack:** Swift 6.0, AppKit, SwiftUI, ApplicationServices (Accessibility `AXUIElement`), CoreGraphics (`CGEvent`).

---

### Task 1: Project Configuration (Disable Sandbox & Enable Hardened Runtime)

**Files:**
- Modify: `CleanBar.xcodeproj/project.pbxproj`
- Modify: `CleanBar/CleanBar.entitlements`

- [ ] **Step 1: Update CleanBar.entitlements**
Remove `com.apple.security.app-sandbox` so the app runs with full native privileges.

- [ ] **Step 2: Update project.pbxproj**
Set `ENABLE_APP_SANDBOX = NO`.

- [ ] **Step 3: Verify build**
Run `xcodebuild -project CleanBar.xcodeproj -scheme CleanBar -configuration Release build` to verify clean build.

---

### Task 2: Native Click Forwarding Engine (`StatusBarObserver.swift`)

**Files:**
- Modify: `CleanBar/Services/StatusBarObserver.swift`
- Test: `CleanBarTests/StatusBarObserverTests.swift`

- [ ] **Step 1: Write test for item trigger and coordinate resolution**
Test that `triggerItem(id:)` queries running applications and resolves target bounds.

- [ ] **Step 2: Implement CGEvent click injector**
Query target app's `AXUIElement` -> `AXExtrasMenuBar` / `AXMenuBarItem` bounds. Send left click via `CGEventPost` to the item's screen position, or activate the application.

- [ ] **Step 3: Verify tests pass**
Run `swift test`.

---

### Task 3: Floating Sub-Bar View & Panel Controller

**Files:**
- Create: `CleanBar/Views/FloatingShelfView.swift`
- Create: `CleanBar/Services/FloatingShelfController.swift`

- [ ] **Step 1: Implement FloatingShelfView.swift**
SwiftUI view rendering 28x28 icon tiles for all active menu bar utilities with hover highlight, tooltips, click actions, and a settings button.

- [ ] **Step 2: Implement FloatingShelfController.swift**
NSPanel with `.floating` / `.popUpMenu` level, frosted glass visual effect, right-aligned to CleanBar's Eye icon.

---

### Task 4: Coordination & Lifecycle in MenuBarSpacerController & CleanBarApp

**Files:**
- Modify: `CleanBar/Services/MenuBarSpacerController.swift`
- Modify: `CleanBar/CleanBarApp.swift`

- [ ] **Step 1: Configure MenuBarSpacerController**
Maintain clean 24px Eye status item. On hover or click, toggle `FloatingShelfController`.

- [ ] **Step 2: Update CleanBarApp**
Wire `HoverMonitor` to show/hide the floating shelf smoothly.

---

### Task 5: End-to-End Verification & /Applications Deployment

**Files:**
- Modify: `CleanBar.xcodeproj/project.pbxproj` (add post-build copy to `/Applications/CleanBar.app`)

- [ ] **Step 1: Run full test suite**
`swift test`.

- [ ] **Step 2: Run Release build and install in /Applications**
`xcodebuild -project CleanBar.xcodeproj -scheme CleanBar -configuration Release build`.

- [ ] **Step 3: Commit and push feature branch**
`git add . && git commit -m "..." && git push origin feature/non-sandboxed-floating-shelf`.
