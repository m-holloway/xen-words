# Multi-Profile Feature Design

## 🎯 Overview

Add support for multiple child profiles to enable:
- **Families:** Multiple children sharing one device
- **Teachers:** Track 20-30 students individually  
- **Personalization:** Each child sees their own name/progress
- **Guest Mode:** Quick sessions without logging

---

## 📊 Data Model

### ChildProfile Model (`lib/models/child_profile.dart`) ✅ CREATED
```dart
class ChildProfile {
  final String id;              // Unique identifier
  final String name;            // Child's first name
  final int? ageYears;          // Optional age
  final DateTime createdDate;
  final DateTime lastActiveDate;
  final Color color;            // Profile theme color
  final String emoji;           // Fun identifier (🎓🌟🚀)
  final int currentWeek;        // Progress per profile
  final String rugFontFamily;   // Personalization per profile
}
```

### ProfileService (`lib/services/profile_service.dart`) ✅ CREATED
- `loadProfiles()` - Get all profiles
- `createProfile()` - Add new child
- `updateProfile()` - Edit profile
- `deleteProfile()` - Remove profile & data
- `getActiveProfile()` - Current user
- `setActiveProfile()` - Switch user
- `loadProgress(profileId)` - Per-profile progress
- `saveProgress(profileId, progress)` - Per-profile tracking

---

## 🎨 User Experience Flows

### Flow 1: First Time User (Onboarding)
```
App Launch
    ↓
Onboarding Page 1-2 (Welcome & Privacy)
    ↓
Onboarding Page 3: Create First Profile
    ├─ "Create profile for your child"
    ├─ Enter name
    ├─ Select age (optional)
    ├─ Pick emoji & color
    └─ Button: "Create Profile & Start!"
    ↓
Profile created → Set as active
    ↓
Splash Screen → Game
```

### Flow 2: Returning User - Single Profile
```
App Launch
    ↓
Load profiles → Found 1 profile
    ↓
Auto-select that profile
    ↓
Splash Screen → Game
```

### Flow 3: Returning User - Multiple Profiles
```
App Launch
    ↓
Load profiles → Found 2+ profiles
    ↓
Profile Selector Screen
    ├─ Show all profiles (name, emoji, color, "Active 2 days ago")
    ├─ "+ Add New Profile" button
    ├─ "👤 Guest Mode" button
    └─ Select profile
    ↓
Set active profile
    ↓
Splash Screen → Game
```

### Flow 4: Guest Mode
```
Profile Selector
    ↓
Tap "👤 Guest Mode"
    ↓
Create temporary guest profile
    ↓
Splash Screen → Game
(Progress not saved)
```

### Flow 5: Profile Management
```
Settings (Parental Gate)
    ↓
Tap "Manage Profiles"
    ↓
Profile Manager Screen
    ├─ List all profiles
    ├─ Edit profile (name, emoji, color, age)
    ├─ View progress summary per profile
    ├─ Delete profile (with confirmation)
    └─ Add new profile
```

---

## 🖼️ Screen Designs

### Profile Selector Screen
```
┌─────────────────────────────────┐
│  Choose Who's Learning Today    │
├─────────────────────────────────┤
│                                 │
│  ┌───────────────────────────┐ │
│  │ 🎓 Emma                   │ │
│  │ Age 6 • Active today      │ │
│  │ [Blue theme]              │ │
│  └───────────────────────────┘ │
│                                 │
│  ┌───────────────────────────┐ │
│  │ 🚀 Lucas                  │ │
│  │ Age 8 • Active yesterday  │ │
│  │ [Green theme]             │ │
│  └───────────────────────────┘ │
│                                 │
│  ┌───────────────────────────┐ │
│  │ + Add New Profile         │ │
│  └───────────────────────────┘ │
│                                 │
│  ┌───────────────────────────┐ │
│  │ 👤 Guest Mode             │ │
│  │ (Progress not saved)      │ │
│  └───────────────────────────┘ │
│                                 │
│         [Manage Profiles] ⚙️    │
└─────────────────────────────────┘
```

### Profile Manager Screen (Parental Gate)
```
┌─────────────────────────────────┐
│ ← Manage Profiles              │
├─────────────────────────────────┤
│                                 │
│  🎓 Emma (Age 6)               │
│  Week 12 • 45 words mastered   │
│  Created Oct 15, 2025          │
│  [Edit] [View Progress]        │
│  ─────────────────────────────  │
│                                 │
│  🚀 Lucas (Age 8)              │
│  Week 8 • 32 words mastered    │
│  Created Oct 20, 2025          │
│  [Edit] [View Progress]        │
│  ─────────────────────────────  │
│                                 │
│  [+ Add Another Child]          │
│                                 │
│  [Delete a Profile] (Red)       │
│                                 │
└─────────────────────────────────┘
```

### Create/Edit Profile Dialog
```
┌─────────────────────────────────┐
│  Create New Profile             │
├─────────────────────────────────┤
│                                 │
│  Child's Name                   │
│  [Emma_____________]            │
│                                 │
│  Age (optional)                 │
│  [6_] years old                 │
│                                 │
│  Choose an emoji:               │
│  🎓 🌟 🚀 🎨 ⚡ 🌈 🎯 🎪    │
│  🦄 🐶 🐱 🐼 🦊 🐸 🦋 🐝    │
│  (Selected: 🎓)                 │
│                                 │
│  Choose a color:                │
│  ⬤ ⬤ ⬤ ⬤ ⬤ ⬤ ⬤ ⬤          │
│  Blue Green Purple Orange...    │
│  (Selected: Blue)               │
│                                 │
│  [Cancel]  [Create Profile]     │
└─────────────────────────────────┘
```

---

## 💾 Data Storage Structure

### SharedPreferences Keys
```
child_profiles: JSON array of all profiles
active_profile_id: Currently selected profile ID
progress_{profileId}: Learning progress for each profile
onboarding_complete: Boolean (first launch)
```

### Example Data
```json
{
  "child_profiles": [
    {
      "id": "profile_1234567890",
      "name": "Emma",
      "ageYears": 6,
      "createdDate": "2025-10-15T10:00:00Z",
      "lastActiveDate": "2025-11-12T15:30:00Z",
      "color": 4280391411,
      "emoji": "🎓",
      "currentWeek": 12,
      "rugFontFamily": "Quicksand"
    },
    {
      "id": "profile_0987654321",
      "name": "Lucas",
      "ageYears": 8,
      "createdDate": "2025-10-20T14:00:00Z",
      "lastActiveDate": "2025-11-11T09:15:00Z",
      "color": 4283215696,
      "emoji": "🚀",
      "currentWeek": 8,
      "rugFontFamily": "Pacifico"
    }
  ],
  "active_profile_id": "profile_1234567890",
  "progress_profile_1234567890": {...},
  "progress_profile_0987654321": {...}
}
```

---

## 🔧 Implementation Checklist

### Phase 1: Core Data Model ✅ DONE
- [x] Create `ChildProfile` model
- [x] Create `ProfileService`
- [x] Update `LearningProgress` to be profile-aware

### Phase 2: UI Screens (TO DO)
- [ ] Create `ProfileSelectorScreen`
- [ ] Create `ProfileManagerScreen`  
- [ ] Create `ProfileEditorDialog`
- [ ] Update `OnboardingScreen` for first profile
- [ ] Add profile switcher to main app

### Phase 3: Integration (TO DO)
- [ ] Update `GameController` to use active profile
- [ ] Update progress tracking to save per profile
- [ ] Update settings to be profile-aware
- [ ] Update dashboard to show active profile data
- [ ] Add "Switch Profile" option in settings

### Phase 4: Testing (TO DO)
- [ ] Test multi-profile creation
- [ ] Test profile switching
- [ ] Test progress isolation per profile
- [ ] Test guest mode
- [ ] Test profile deletion
- [ ] Test teacher scenario (10+ profiles)

---

## 🎓 Use Cases

### Use Case 1: Family with 3 Kids
**Scenario:** Sarah (mom) has 3 children: Emma (6), Lucas (8), Mia (4)

**Flow:**
1. Install app → Onboarding creates Emma's profile
2. Settings → Manage Profiles → Add Lucas
3. Settings → Manage Profiles → Add Mia
4. Each morning, kids select their profile
5. Progress tracked separately
6. Sarah views each child's dashboard individually

### Use Case 2: Teacher with 25 Students
**Scenario:** Mr. Johnson teaches kindergarten, wants to track each student

**Flow:**
1. Install app → Create first student profile
2. Settings → Manage Profiles → Add 24 more students
3. During lesson, student comes to tablet
4. Student selects their profile (or teacher selects)
5. Student practices their words
6. Mr. Johnson views dashboard for each student
7. Can see which students need help

### Use Case 3: Babysitter with Multiple Families
**Scenario:** Jane babysits for 4 families, uses app with different kids

**Flow:**
1. Has profiles for all kids she watches
2. When kid arrives, selects their profile
3. Or uses Guest Mode for one-time sessions
4. Progress maintained per child
5. Parents can see progress on their own device (separate installs)

### Use Case 4: Trial Without Commitment
**Scenario:** Parent wants to try app before committing

**Flow:**
1. Install app → Skip profile creation
2. Tap "Guest Mode"
3. Try the app
4. If they like it, create real profile later
5. No data saved during guest sessions

---

## 🔐 Privacy Considerations

### Per-Profile Data Isolation
- Each profile's progress stored separately
- Deleting a profile deletes ALL their data
- No data shared between profiles
- Guest mode: ZERO data saved

### Parental Controls
- Profile Management requires parental gate
- Kids can't delete profiles
- Kids can't switch to other profiles during session
- Kids CAN select profile at start (it's their device)

### COPPA Compliance
- Each profile is treated as separate "user"
- All data still local-only
- No data transmitted
- Clear disclosure per profile
- Easy deletion per profile

---

## 📊 Success Metrics

### Adoption Metrics
- **Multi-profile adoption rate:** % of users with 2+ profiles
- **Average profiles per family:** Target 2.5
- **Teacher adoption:** % of users with 10+ profiles
- **Guest mode usage:** % of sessions in guest mode

### Engagement Metrics
- **Profile switching rate:** How often users switch
- **Per-profile session count:** Engagement per child
- **Profile retention:** Do profiles stay active?
- **Cross-profile comparison:** Parents comparing kids?

---

## 🚀 Launch Strategy

### MVP (Early Access)
- [x] Single profile (current state)
- [ ] Add multi-profile support
- [ ] Profile selector on launch
- [ ] Guest mode
- [ ] Profile management in settings

### V1.1 (Post-Launch)
- [ ] Profile import/export
- [ ] Profile sync across devices (optional, cloud)
- [ ] Profile sharing (for divorced parents, etc.)
- [ ] Classroom management features

### V2.0 (Future)
- [ ] Teacher dashboard (web portal?)
- [ ] Parent app (separate app to monitor)
- [ ] Profile insights & recommendations
- [ ] Comparative analytics (how is my kid doing?)

---

## 🎯 Implementation Priority

### High Priority (Week 1)
1. Profile selector screen
2. Basic profile creation
3. Profile switching
4. Update game controller for profiles

### Medium Priority (Week 2)
5. Profile manager screen
6. Profile editing
7. Profile deletion
8. Guest mode

### Low Priority (Week 3)
9. Profile import/export
10. Advanced profile settings
11. Profile icons/avatars
12. Profile themes

---

## 📝 Code Integration Points

### Files to Modify

**`lib/main.dart`**
- After onboarding, check profile count
- If 0 profiles: Force create first profile
- If 1 profile: Auto-select
- If 2+ profiles: Show profile selector

**`lib/controllers/game_controller.dart`**
- Add `_activeProfile` field
- Load profile on init
- Save progress to profile's storage
- Update settings per profile

**`lib/widgets/settings_page.dart`**
- Add "Manage Profiles" button
- Add "Switch Profile" button
- Show active profile name
- Per-profile settings vs global

**`lib/screens/parent_dashboard_screen.dart`**
- Show active profile's data
- Add profile selector dropdown
- Allow viewing other profiles

**`lib/screens/onboarding_screen.dart`**
- Page 3: Create first profile instead of just name
- Add emoji & color selection
- Create profile on completion

---

## 🧪 Testing Checklist

### Functional Tests
- [ ] Create first profile during onboarding
- [ ] Create additional profiles in settings
- [ ] Switch between profiles
- [ ] Guest mode works without saving
- [ ] Progress isolated per profile
- [ ] Edit profile name/emoji/color
- [ ] Delete profile removes all data
- [ ] Profile selector shows on launch (2+ profiles)
- [ ] Auto-select works (1 profile)

### Edge Cases
- [ ] What if 50 profiles? (UI overflow)
- [ ] What if profile name is 50 characters?
- [ ] What if all profiles deleted?
- [ ] What if switching mid-session?
- [ ] What if app crashes during profile creation?

### Performance
- [ ] Loading 30 profiles is fast
- [ ] Profile switching is instant
- [ ] Progress save doesn't lag
- [ ] Profile selector renders quickly

---

## 💰 Monetization Implications

### Free Tier
- **Limit:** 2 profiles maximum
- **Reason:** Allows siblings, tests multi-profile
- **Upgrade prompt:** "Add unlimited profiles with Premium!"

### Premium Tier ($2.99/mo or $19.99/yr)
- **Unlimited profiles**
- **Advanced profile management**
- **Profile-specific analytics**
- **Profile import/export**
- **Teacher features** (bulk add, class management)

### Classroom License ($99/yr)
- **Up to 30 profiles**
- **Teacher dashboard**
- **Progress reports**
- **Bulk profile management**

---

## 🎉 Launch Messaging

### App Store Description Update
Add to features list:
- "✨ **Multi-Profile Support** - Track progress for multiple children or students"
- "👤 **Guest Mode** - Try the app without creating a profile"
- "🎓 **Perfect for Classrooms** - Teachers can manage dozens of students"
- "👨‍👩‍👧‍👦 **Family Friendly** - Each child gets their own personalized experience"

### In-App Onboarding
"Do you have multiple children who will use this app?"
- ✅ Yes → "Great! You can add more profiles anytime in Settings."
- ✅ No → "No problem! You can always add more later."

---

**Status:** Design Complete, Ready for Implementation
**Estimated Time:** 1-2 weeks full implementation
**Priority:** Medium-High (great for launch, but not MVP blocker)

Would you like me to implement the UI screens next, or do you prefer to review this design first?

