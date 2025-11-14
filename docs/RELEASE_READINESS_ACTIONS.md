# Release Readiness: Action Items Checklist

**Target:** Early Access Launch in 30 Days  
**Status:** COPPA Compliance Core Complete ✅

---

## ✅ **COMPLETED** (Today!)

- [x] Privacy Policy drafted
- [x] Terms of Service drafted
- [x] COPPA Compliance Checklist created
- [x] Parental gate implemented and integrated
- [x] Settings protected with parental gate
- [x] Release planning todo list created

---

## 🚨 **CRITICAL: Fill These In IMMEDIATELY**

### 1. Contact Information (Required for App Stores)

**Files to Update:**
- `PRIVACY_POLICY.md` (lines 98-99)
- `TERMS_OF_SERVICE.md` (lines 121-122)

**What you need:**
```markdown
**Email:** support@yourapp.com  (or your personal email)
**Website:** https://yourapp.com  (optional for early access)
```

**Action:** 
1. Create a support email (Gmail works fine: xenwords.support@gmail.com)
2. Update both files with your real email
3. (Optional) Set up a simple landing page with Carrd, GitHub Pages, or just a placeholder

---

### 2. Legal Jurisdiction (Required for Privacy Policy)

**File:** `PRIVACY_POLICY.md` (line 104)

**Current:** `[YOUR STATE/COUNTRY]`  
**Update to:** Your actual location (e.g., "California, United States")

**File:** `TERMS_OF_SERVICE.md` (line 158)

**Same update needed**

---

### 3. Host Privacy Policy Online

**Why:** App Store and Play Store require a publicly accessible URL

**Options:**

**A) Quick & Free: GitHub Gist**
1. Go to https://gist.github.com
2. Create new gist with `PRIVACY_POLICY.md` content
3. Copy the raw URL
4. Use in app store listings

**B) Simple Landing Page: Carrd.co**
1. Free tier is perfect
2. Create single page
3. Paste privacy policy
4. Done in 10 minutes

**C) GitHub Pages (If you have a repo)**
1. Enable GitHub Pages
2. Add privacy policy as page
3. Link from app

**What You'll Need:**
- Privacy Policy URL: `https://______________________`
- Terms URL (optional): `https://______________________`

**Add these URLs to:**
- App Store Connect listing (required)
- Play Console listing (required)
- In-app settings page (recommended)

---

## 📝 **WEEK 1 PRIORITIES** (Non-Compressible)

### Developer Account Setup (Start TODAY)

**Apple Developer Program**
- [ ] Go to: https://developer.apple.com/programs/enroll/
- [ ] Cost: $99/year
- [ ] Approval time: **24-48 hours** (sometimes instant)
- [ ] You need: Apple ID, payment method, legal entity info

**Google Play Developer**
- [ ] Go to: https://play.google.com/console/signup
- [ ] Cost: $25 one-time
- [ ] Approval time: **Usually instant** (sometimes 48hrs)
- [ ] You need: Google account, payment method

**Why Start Now:** These are non-compressible wait times. Start them ASAP!

---

### Bundle Identifiers (Finalize This Week)

**Current (from pubspec.yaml):**
- Package name: `xen_words`
- Version: `1.0.0+1`

**You Need to Decide:**
- iOS Bundle ID: `com.yourname.xenwords` (or `com.xenwords.app`)
- Android Package: `com.yourname.xenwords` (must match iOS format)

**Format:** `com.[company].[appname]`
- Use lowercase only
- No spaces or special characters
- Once set, can't change easily!

**Recommendation:** 
- If you might create a company later: `com.xenwords.app`
- If personal project: `com.yourname.xenwords`

**Files to Update:**
- [ ] `android/app/build.gradle.kts` (applicationId)
- [ ] `ios/Runner.xcodeproj` (bundle identifier)
- [ ] Pubspec.yaml name (optional, but good to match)

---

### App Name (Finalize This Week)

**Current:** "Xen Words" (internal) / "xen_words" (package)

**Considerations:**
- Is "Xen Words" your final public name?
- Check availability: Search App Store and Play Store
- Check domain: xenwords.com available? (Optional but nice)

**If changing name:**
- [ ] Update `ios/Runner/Info.plist` (CFBundleDisplayName)
- [ ] Update `android/app/src/main/AndroidManifest.xml` (android:label)
- [ ] Update privacy policy and terms
- [ ] Update README

**Recommendation:** Keep "Xen Words" - it's unique and memorable!

---

## 📱 **WEEK 1-2 DEVELOPMENT PRIORITIES**

Now that COPPA is done, focus on these for MVP:

### 1. Basic Parent Dashboard (High Priority)

**Why:** Builds trust, shows you care about learning outcomes

**Minimum Features:**
- [ ] Words mastered count
- [ ] Total sessions count
- [ ] Current week/progress
- [ ] "View Data" button (shows what's stored locally)
- [ ] "Delete All Data" button

**Where:** New screen accessible from settings (already protected by parental gate!)

**Time Estimate:** 4-6 hours with AI assistance

---

### 2. Improved Loading Experience (High Priority)

**Why:** Your #1 UX pain point (10-15s initialization)

**Quick Wins:**
- [ ] Add percentage progress bar to splash screen
- [ ] Add loading messages: "Loading speech recognition model... 45%"
- [ ] Add educational tips during load
- [ ] Show estimated time remaining

**Files:** `lib/widgets/splash_screen.dart`

**Time Estimate:** 2-3 hours

---

### 3. First-Run Experience (Medium Priority)

**Why:** Set expectations, build trust, comply with stores

**Features:**
- [ ] Welcome screen explaining offline nature
- [ ] Child name/age input (optional)
- [ ] Microphone permission explanation
- [ ] Quick tutorial (3 screens max)

**Time Estimate:** 3-4 hours

---

### 4. In-App Privacy Policy Link (Required)

**Why:** App stores require it

**Implementation:**
- [ ] Add "Privacy Policy" button in settings
- [ ] Protect with parental gate
- [ ] Open browser to hosted URL
- [ ] Or: Show full text in-app dialog

**Time Estimate:** 30 minutes

---

## 🎨 **WEEK 2-3 ASSETS & BRANDING**

### App Icon (REQUIRED)

**Sizes Needed:**
- iOS: 1024×1024 PNG (no transparency, no rounded corners)
- Android: Adaptive icon (foreground + background)

**Design Tips:**
- Simple, recognizable at small sizes
- Related to words/learning/reading
- Kid-friendly but not childish
- Consider: Book, speech bubble, or abstract letterform

**Tools:**
- Figma (free)
- Canva (free tier)
- Adobe Express (free)
- Or hire on Fiverr: $20-50

**Action:**
- [ ] Design icon
- [ ] Export iOS format (1024×1024)
- [ ] Export Android adaptive (foreground + background layers)
- [ ] Replace icons in `/android/app/src/main/res/mipmap-*`
- [ ] Replace iOS icon in `ios/Runner/Assets.xcassets/AppIcon.appiconset`

---

### Screenshots (REQUIRED)

**iOS Requirements:**
- iPhone 6.7" (iPhone 14 Pro Max): 1290×2796
- iPhone 6.5" (iPhone 11 Pro Max): 1242×2688  
- iPad Pro 12.9" (3rd gen): 2048×2732
- Minimum: 3 screenshots, Maximum: 10

**Android Requirements:**
- Phone: 1080×1920 minimum
- 7" Tablet: 1200×1920 minimum
- 10" Tablet: 1600×2560 minimum
- Minimum: 2 screenshots, Maximum: 8

**What to Show:**
- Initial screen with character
- Child speaking into microphone
- Correct word celebration
- Week selection screen
- Settings (optional)

**Tools:**
- Take on real device (easiest)
- iOS Simulator → Cmd+S to save
- Android Emulator → Screenshot button
- Frame with https://www.mockuphone.com (optional, looks pro)

**Action:**
- [ ] Capture 5-8 key screens
- [ ] Add descriptive captions (optional)
- [ ] Export in required sizes

---

### App Description (REQUIRED)

**Template:**

```markdown
# Xen Words - Offline Speech Recognition for Kids

Help your child learn sight words through the power of their own voice!

✨ KEY FEATURES:
• 100% Offline - No internet required, no data collection
• Speech Recognition - Child speaks, app responds
• 61 Sight Words - Organized across 31 weeks
• Animated Character - Engaging 3D rabbit companion
• Parent Dashboard - Track progress and learning
• Privacy First - Zero tracking, zero ads, zero accounts

🔒 PRIVACY YOU CAN TRUST:
• All processing happens on your device
• No audio recordings saved
• No personal information collected
• Perfect for schools with strict privacy policies

📚 DESIGNED FOR LEARNING:
• Ages 4-8
• Research-based sight word progression
• Immediate feedback and encouragement
• Celebrates effort and success

🎯 PERFECT FOR:
• Homeschooling families
• Supplemental reading practice
• ESL learners
• Kids who love technology

FREE during early access - help us improve!

---

Your child's privacy is our highest priority. Learn more at [YOUR-WEBSITE]
```

**Action:**
- [ ] Customize description
- [ ] Add your website/support email
- [ ] Keep under character limits (4000 chars iOS, 4000 chars Android)

---

## 🧪 **WEEK 3 TESTING**

### Internal Testing Checklist

**Devices to Test:**
- [ ] Oldest iPhone you can find (iPhone 8 or SE 1st gen ideal)
- [ ] Latest iPhone (14/15 series)
- [ ] iPad
- [ ] Budget Android (Samsung A-series)
- [ ] Flagship Android (Pixel, Samsung S-series)
- [ ] Android tablet (if possible)

**Test Scenarios:**
- [ ] Fresh install (no data)
- [ ] Parental gate blocks kids
- [ ] Settings accessible to adults
- [ ] Speech recognition works in noisy environment
- [ ] App handles background/foreground correctly
- [ ] Uninstall removes all data
- [ ] Loading screen shows progress
- [ ] Character animations smooth
- [ ] Audio plays correctly

**Performance Targets:**
- App launch: < 15 seconds
- Speech recognition response: < 1 second
- Animations: 60 FPS
- Memory usage: < 300 MB
- Storage: < 250 MB

---

### Beta Testing (5-10 Families)

**Recruitment:**
- Friends/family with kids aged 4-8
- Local parenting groups (Facebook, Reddit)
- Homeschool communities
- Your social network

**What to Ask:**
- [ ] Did your child understand how to use it?
- [ ] Was the speech recognition accurate enough?
- [ ] Did you feel comfortable with privacy?
- [ ] Would you pay for premium features? What features?
- [ ] What frustrated you most?
- [ ] What delighted you most?

**TestFlight Setup (iOS):**
1. App Store Connect → TestFlight
2. Add internal testers (up to 100)
3. Send invite link
4. Collect feedback

**Google Play Internal Testing (Android):**
1. Play Console → Release → Testing → Internal testing
2. Create release
3. Add testers by email
4. Send invite link

---

## 🚀 **WEEK 4 SUBMISSION**

### Pre-Submission Checklist

**Code:**
- [ ] No debug logs in production
- [ ] Version number set (1.0.0)
- [ ] Build number incremented (+1)
- [ ] Release build tested on device
- [ ] No compiler warnings
- [ ] All TODOs resolved

**Assets:**
- [ ] App icon finalized
- [ ] Screenshots uploaded
- [ ] Description written
- [ ] Privacy policy URL live
- [ ] Support email working

**Legal:**
- [ ] Privacy policy hosted and accessible
- [ ] Terms of service accessible
- [ ] COPPA compliance verified
- [ ] Age rating determined (4+/Everyone)
- [ ] Content rating questionnaire completed

**Store Listings:**
- [ ] App name final
- [ ] Category selected (Education)
- [ ] Age rating set
- [ ] Privacy declarations complete
- [ ] Contact information correct

---

### iOS TestFlight External Testing (Fastest Path!)

**Why This First:**
- Faster review than full App Store (1-2 days vs 1-2 weeks)
- Get real users quickly
- Iterate faster
- TestFlight allows 10,000 external testers

**Steps:**
1. [ ] Build release IPA
2. [ ] Upload to App Store Connect
3. [ ] Submit for TestFlight External Testing Review
4. [ ] **Wait 1-2 days for review**
5. [ ] Share public TestFlight link
6. [ ] Collect feedback
7. [ ] Iterate

**Public Link Format:**
`https://testflight.apple.com/join/XXXXXXXX`

---

### Android Closed Testing (Even Faster!)

**Why:**
- No review for closed testing (<100 testers)
- Instant access
- Easy to add testers

**Steps:**
1. [ ] Build release APK/AAB
2. [ ] Upload to Play Console
3. [ ] Create closed testing track
4. [ ] Add testers by email
5. [ ] Send invite link
6. [ ] **Instant access** (no review!)

---

## 💰 **MONETIZATION SETUP** (For Later)

Since you want freemium with 14-day trial:

### In-App Purchase Structure (Implement Week 2-3)

**Free Tier:**
- 61 sight words
- Basic progress tracking
- Speech recognition
- Animated character

**Premium ($2.99/month or $19.99/year):**
- Parent dashboard with detailed analytics
- Custom word lists
- Progression speed adjustment
- Extended session history
- Priority support
- (Future) Voice morphing

**Implementation:**
- [ ] Use `in_app_purchase` Flutter package
- [ ] Set up products in App Store Connect
- [ ] Set up products in Play Console
- [ ] Implement 14-day trial logic
- [ ] Add restore purchases option
- [ ] Protect premium features with entitlement check

**Legal:**
- [ ] Update privacy policy (Apple/Google process payments)
- [ ] Add subscription terms to ToS
- [ ] Clearly display pricing before purchase
- [ ] Implement parental gate before purchase screen

---

## 📊 **30-DAY TIMELINE SUMMARY**

### Week 1 (Days 1-7): Foundation
- ✅ COPPA compliance (DONE!)
- [ ] Developer accounts (start Day 1)
- [ ] Bundle IDs finalized
- [ ] Privacy policy hosted
- [ ] Support email set up
- [ ] Basic parent dashboard built
- [ ] Improved loading UX

### Week 2 (Days 8-14): Polish & Assets
- [ ] App icon designed
- [ ] Screenshots captured
- [ ] Description written
- [ ] First-run experience
- [ ] Internal testing (devices you own)
- [ ] Bug fixes

### Week 3 (Days 15-21): Beta Testing
- [ ] TestFlight external testing submitted
- [ ] Closed testing (Android) live
- [ ] 5-10 families recruited
- [ ] Feedback collected
- [ ] Critical bugs fixed

### Week 4 (Days 22-30): Launch!
- [ ] Iterate based on feedback
- [ ] Final polish
- [ ] App store listings complete
- [ ] Public TestFlight link shared
- [ ] Early access announced!

---

## 🎉 **SUCCESS METRICS**

**Early Access Goals (First 30 Days):**
- 50+ TestFlight installs (iOS)
- 50+ Closed Testing installs (Android)
- <1% crash rate
- 4.5+ star rating (from feedback surveys)
- 10+ detailed feedback responses
- 30%+ session completion rate

**Red Flags (Address Immediately):**
- >2% crash rate
- <3.5 star equivalent feedback
- <10% session completion
- Consistent complaints about specific feature

---

## ✉️ **YOUR NEXT ACTIONS** (Do Today!)

1. **Create support email** → xenwords.support@gmail.com (or similar)
2. **Update privacy policy & terms** → Add your email
3. **Start developer accounts** → Apple ($99) + Google ($25)
4. **Host privacy policy** → GitHub Gist or Carrd.co
5. **Finalize bundle ID** → Decide on com.xenwords.app or com.yourname.xenwords

**Tomorrow:**
6. Build parent dashboard
7. Improve loading screen
8. Create app icon

**This Week:**
9. Take screenshots
10. Write app description
11. Internal testing

---

## 📞 **NEED HELP?**

**Stuck on:**
- Developer account setup → DM me the error
- App icon design → Use Canva templates, search "app icon kids learning"
- Screenshots → Just take them on device, no fancy tools needed
- Privacy policy questions → Reference COPPA_COMPLIANCE_CHECKLIST.md

**Remember:** Perfect is the enemy of shipped. Get to beta, get feedback, iterate!

---

🚀 **You've got this! The hard part (COPPA compliance) is DONE. The rest is execution.** 🚀

