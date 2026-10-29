# InstantReplay — UX Specification (v0.1 polish)

> Status: **Draft** · 2026-10-29 · From a user interview. Complements [SPEC.md](SPEC.md) §5–6.
> Goal: simple and intuitive for **one coach who sets up and runs everything alone**, under match pressure.

## 1. Who and when

| Question | Answer |
|---|---|
| Who sets up the Camera and uses the Viewer | **The same coach**, alone: mounts the tripod, then goes to the bench |
| Viewer device | **Any**: phone (one hand, standing), tablet (bench), laptop (table). All three must work well |
| After saving a play | **Keep watching live** and **tag it quickly**; no forced review |
| When clips are reviewed | **During the match**: time-outs and half-time, under time pressure |

Design consequences:
- Nothing on the main Viewer screen may take more than **one tap**, or hide the live view for more than a moment.
- Technical information is **out of the way** unless something needs action.
- The Camera, once mounted, must **need no attention**.

## 2. Camera role

### 2.1 Setup screen (mounting on the tripod)
- **Large preview** to frame the shot, plus the **QR and 6-digit code** to connect a Viewer. Nothing else in plain sight.
- An **"Advanced"** section (collapsed): quality profile, live statistics, diagnostics, test save.
- Warnings appear only when relevant: not charging, overheating, no network.

### 2.2 Operating mode (automatic)
- When the **first Viewer connects**, the Camera switches by itself to the **black operating screen**, with the preview off. That saves battery and heat.
- A **tap anywhere** wakes it back to the setup screen.
- The minimal status line stays (REC dot, buffer, viewers, temperature).

## 3. Viewer role

### 3.1 First connection
- **Phone:** scan the Camera's QR with the system camera. The Viewer opens already paired.
- **Tablet / laptop:** open the address shown on the Camera and type the code.
- After that, it **reconnects by itself** (stored token). **No onboarding or tutorial**: the screens must explain themselves.

### 3.2 Live screen (during the match)
**Balanced layout:** a large live view **and** a large Save button. The clip list is compact and secondary.

| Element | Behaviour |
|---|---|
| Live view | As large as the layout allows; reconnects by itself |
| **Save** | One big button with the default duration (20 s), plus 10 / 30 / 60 s chips next to it (current behaviour kept) |
| **Post-save tag bar** | Right after saving, a row of tag buttons appears for ~6 s. One tap tags the clip; if nothing is tapped it fades away. It never blocks the live view or the next save. Unlimited tags: the row scrolls horizontally |
| Camera status | **Minimal**: a REC dot (green = recording, red = problem). **Tap for details** (fps, buffer, pending clips, temperature, battery). Problems surface as a short warning without a tap |
| Clip list | Compact, newest first (see 3.3) |

Layouts:
- **Phone portrait:** live on top, Save + chips below, tag bar over the Save area, clip list underneath (scroll).
- **Phone landscape / tablet / laptop:** live on the left, a right panel with Save, chips, the tag bar and the clip list.

### 3.3 Clip list (finding the play in a time-out)
- Chronological, **newest first**.
- Each row: **thumbnail**, **name = tag + wall-clock time** (e.g. "Bien · 12:41"; "Clip · 12:41" if untagged), duration, tag colour, and state (recording / downloading / ready).
- **Filter chips by tag** at the top of the list.
- Tap a row to open the review. Tags can also be changed from the row or the review.

### 3.4 Review
- **Full screen, 1×, loop** (current behaviour).
- Controls: play/pause, scrub bar, ±1 frame, speeds 0.25× / 0.5× / 1×, close, and change tag.
- Web: Download. Native (later): gallery / share.

### 3.5 Tags
- **Stored per Viewer** (on web: browser storage; it may be lost if the browser data is cleared).
- **Default set: Bien · Mal · Otros**, editable (add, rename, delete, reorder, colour) from a simple screen reachable from the Viewer menu.
- No limit on the number of tags; the post-save bar scrolls.

## 4. Visual style
- Keep **dark + amber/cream** (current), high contrast, touch targets ≥ 56 dp for primary actions.
- Every glyph must exist in the bundled font. Today one status character renders as a box (tofu); use an icon instead.

## 5. Scope note
Most of this is presentation and layout. Four items add small features:
- automatic operating mode on the Camera;
- the post-save tag bar, tag editing, and tags on clips;
- thumbnails;
- tag filters.

None of them change the protocol: tags live on the Viewer, and thumbnails are taken from the downloaded clip.
