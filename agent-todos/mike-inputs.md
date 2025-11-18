This document contains todo items for agents.  If you ware working on a task and find a clear opportunity to address one of these todos with incremental effort low risk or high confidence, go ahead and take the opportunity.  Each of these items would improve the app in some way.

# Todo
- There are times when there is a prompt (child's turn) during story time, where we're asking the child to say a word, BUT the voice recognition doesn't seem to work and CONTINUE button is greyed out (for instance when we ask Adalyn to say the word "GO" in the default story time passage).  I may need to capture a trace unless the bug is apparent from code inspection.  I've noticed other times where it seems like the challenge is for the child to say a word, but the box is actually empty, so they don't know what they should say (I've noticed this in the story lab custom stories).  Hopefully there is resuable/common code that is used for both of those modes.  If not it should be, instead of copy/paste.  Should check that too.
- We need to add a feature to the story time/reader view.  When the user 'taps' a word, we should make that the active/next word (white on blue), and set the app/recognizer state accordingly.  This allows the parent or child to rewind/redo easily/naturally if the system gets a head or they just want to re-read something, etc.
# Completed
When an item above is completed/addressed fully (confirmed by the user), move it here, add the date/time, a summary of the original item and solution, and the original text from above.

- **2025-11-18 — Removed narration line progress bar**  
  Summary: Eliminated the blue horizontal progress bar beneath each word group to reduce clutter and reclaim vertical space in story reading mode.  
  Original: “I think perhaps get rid of the blue progress bar on each word box in reading mode (i.e story time/lab).  They don't seem to add value and they are a bit distracting.”

- **2025-11-18 — Narration completion waits for final word**  
  Summary: Story reader was flagging “Reading complete!” when the highlight reached the last token, even if the user hadn’t spoken it yet. We now keep `_finalWordConfirmed` false until Sherpa reports an anchor beyond the final script word, so the completion card and Continue button appear only after the last word is actually spoken.  
  Original: “In story/reading mode, the detection logic seems to 'jump the gun' so that when I speek the n-1 word of a passage, the logic jumps to the passage complete state indicating "Reading Complete!  (continue).  It should WAIT until the last word is actually uttered (possibly until confirmed via sherpa STT)”

- **2025-11-18 — Final word linger animation**  
  Summary: When the last word of a passage is spoken we now let the chip run its full linger/fade (white-on-indigo → indigo outline → grey read state) before the “Reading complete” banner appears. Sherpa anchors still advance the highlight instantly, but a 1 s completion timer ensures the child sees that lingering cue.  
  Original: “It's still jumping the gun on that final linger/fade.  It needs to run the FULL duration of the linger duration BEFORE it completes.”

- **2025-11-18 — Smooth narration auto-scroll**  
  Summary: Added scroll animation tracking in `GroupedWordDisplay` so in-flight auto-scroll animations finish even if the next word is recognized mid-scroll, eliminating the abrupt “jump” into the next word group.  
  Original: “The automatic scrolling during reading is generally gentle and smooth (which is natural and easy to follow).  However, there seem to be times where it 'jumps' to the next word box without smoothly animating the scroll.  This is not ideal.  As best as I can tell, this occurs when we read the first word of the next box during the time in which the scroll should be smoothly animating.  In that case, it seems to just "JUMP" into position, which is jarring.  We should NOT do this, but rather have a consistent behavior when scrolling -- that is, do the smooth scrolling animation even if the user reads the first word of the next box”