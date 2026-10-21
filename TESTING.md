# Testing Cue on your iPhone: day one

About 20 minutes. You need a Mac with Xcode 26 or later, your iPhone, and a cable or the same Wi-Fi network.

## 1. Open and run

1. Clone the repo and check out `feature/cue-prototype` (or `main` once the PR is merged).
2. Double-click **`Cue.xcodeproj`**. Nothing needs installing: no CocoaPods, no XcodeGen, no packages to download.
3. Open **`Config/Signing.xcconfig`** and change one line:
   `CUE_BUNDLE_ID = com.yourname.cue` (any ID nobody else has used).
   You can also set `CUE_TEAM_ID`, or leave it empty and pick your team in step 4.
4. Select the **Cue** target, go to **Signing & Capabilities** and pick your **Team** (your Apple ID works). Signing is automatic.
5. Pick your iPhone as the run destination and press **Run** (⌘R).
   - First time on this phone: on the iPhone, open **Settings → General → VPN & Device Management** and trust your developer certificate. Also turn on **Settings → Privacy & Security → Developer Mode** if iOS asks, then run again.

You can also press Run with an iPhone **Simulator** selected. There the camera is simulated (a slate background with a moving bar), so everything except real video works.

## 2. What to tap and what you should see

| # | Do this | You should see |
|---|---|---|
| 1 | First launch | A welcome screen with the privacy promise: "Cue never sends your scripts, audio or video anywhere. iOS may download a speech model once, the same way Dictation does." Tap **Continue**. |
| 2 | Permissions page | Three rows (Microphone, Camera, Speech recognition), each with a one-line reason and an **Allow** button. Tap each one: the system prompt appears only after you tap. Tap **Start using Cue**. |
| 3 | Library | **All scripts** with three samples: "Welcome to Cue", "Product update, 60 seconds" and "Conference talk opener". Each row shows the time since it was edited and a read time such as "45 sec". |
| 4 | Swipe a row left | **Delete** and **Duplicate**. Swipe right: **Prompter**. Long-press: Open prompter, Duplicate, Move to folder, Delete. |
| 5 | Pull down on the list | A search field. Type "habits": only "Conference talk opener" is left. |
| 6 | ⋯ menu | Sort by **Last edited** or **Title**, and **Import from Files** (.txt, .md, .rtf). |
| 7 | Back to the sidebar | **All scripts**, **Takes**, and a **Samples** folder. Tap **New folder** to make one. |
| 8 | Open "Welcome to Cue" | The editor. `[pause]` and `[breathe]` are tinted, `*Cue*` is tinted bold, `// notes` are grey italic, and `---` is grey. The bottom bar says "About … sec" and "… words", plus a **140 wpm** menu. |
| 9 | Type a few words | The read time updates as you type. Change the pace to 180 wpm: the estimate drops. |
| 10 | Keyboard toolbar | Buttons to insert pause, breathe, emphasis, note and section break at the cursor. |
| 11 | Tap ▶︎ (Open prompter) | A dark slate stage with the first line inside a warm tungsten glow band. |
| 12 | Tap the big play button | A 3-2-1 countdown with a light tap of haptics on each number, then the text scrolls smoothly. The controls fade out after 2 seconds. Lines that have scrolled above the band dim. |
| 13 | Tap the stage | Pauses and the controls come back. Tap again to resume. |
| 14 | Double-tap the stage | Glides to the next section (after the next `---`), with a haptic. |
| 15 | Drag with two fingers | Scrubs up and down through the script. |
| 16 | Tortoise and hare buttons | Slower and faster. |
| 17 | **Aa** button | Display settings: typeface (SF Pro or New York), size, line spacing, margins, alignment, speed, reading-line position, countdown and **Mirror text**. Turn Mirror on: the text flips left to right. |
| 18 | Presets in the same sheet | **Rig mode** (big, mirrored, centered), **Selfie mode** (reading line near the top, follows your voice) and **Rehearsal** (New York, follows your voice). Tap one to apply it. **Save as preset** stores your current settings. |
| 19 | Waveform button (top bar) | Turns on **Follow my voice**. Tap play and read aloud: the script keeps pace with you. Words you've said dim, it waits when you stop, and it catches up smoothly when you skip a line or ad-lib. |
| 19b | **Polish** (wand) in the editor toolbar | Only on iPhones with Apple Intelligence turned on; it's hidden everywhere else. Select some text (or nothing, for the whole script) and choose **Make it sound spoken**, **Trim to… seconds** or **Add pause marks**. A sheet shows the suggestion as a diff: removed words struck through, added words underlined, plus the read time before and after. **Use this** replaces the text (shake to undo). **Keep original** leaves it alone. |
| 20 | Close (✕), then **Record** (⏺) in the editor | The front-camera preview with the script in a panel at the top of the screen, near the lens. Turn the phone sideways: the panel moves to the side nearest the camera. |
| 21 | Camera button | Switch camera, Resolution (only the sizes your phone supports), Frame rate, and Microphone if you have one plugged in. |
| 22 | Red record button | Recording starts with a haptic and a red-dot timer, and the prompter counts down. Read part of the script, then tap stop. |
| 23 | After you stop | A **Take saved** sheet with the Delivery card: your pace against the target, how much of the script you covered, the longest pauses, any off-script stretches by section, and filler words ("um", "uh", "like" when it isn't in your script…). These are neutral facts, not a score. |
| 24 | Sidebar → **Takes** | Your take with a thumbnail. Open it to play it. The script overlay is **not** in the video. Use ⋯ → **Export to Photos**, which asks for add-only Photos access the first time, or **Share**. |
| 25 | Settings (gear in the sidebar) | The privacy statement, default pace, "Follow my voice" status (for example "Ready, works offline"), permissions, and an **iCloud** toggle. It's disabled with an explanation because sync isn't set up in this build. |
| 26 | Settings → **Debug tools** (debug builds only) | **Play fake transcript**: pick a script, a pace and a "messiness" level, and watch voice pacing follow a simulated speaker without you talking. **Reset sample data** restores the three samples and built-in presets. |

## 3. Airplane-mode check for voice pacing

1. With internet on, open **Settings** in Cue. "Follow my voice" should say **Ready, works offline**. If it says "Needs a one-time download", tap **Download speech model** and wait.
2. Turn on **Airplane Mode** in Control Center and make sure Wi-Fi is off too.
3. Open a script, turn on the waveform (Follow my voice), press play and read aloud. **It should follow you exactly as it did online.**
4. Record a take in Airplane Mode as well. The Delivery card should still appear.
5. Edge case: on a phone where the model has never been downloaded, start in Airplane Mode. The prompter should show a short message ("Voice pacing needs a speech model that iOS downloads once…") and scroll at a steady speed instead. It should never show a blank or dead screen.

## 4. Keyboard or presentation clicker

Pair a Bluetooth keyboard or clicker, then open the prompter:

- **Space** or **Return**: play or pause
- **→** or **Page Down**: next section
- **←** or **Page Up**: previous section
- **↑** and **↓**: faster and slower

## 5. Accessibility spot checks

- **Settings → Accessibility → Display & Text Size → Larger Text**: the library and editor grow. Stage size is set in Cue itself.
- **Increase Contrast**: the reading line becomes a solid tungsten rule with a flat band, and read text dims less.
- **Reduce Motion**: no animated transitions and the countdown snaps.
- **VoiceOver**: the stage reads the current line. Swipe up or down for the "Next section" and "Previous section" actions.

## 6. If something goes wrong

- Build error about signing: recheck steps 3 and 4. The bundle ID must be unique to you.
- "Untrusted developer": see the note under step 5 of section 1.
- Camera shows "Cue doesn't have access to the camera": tap **Open Settings** and allow Camera.
