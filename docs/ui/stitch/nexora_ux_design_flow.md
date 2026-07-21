# Nexora UX Flow & Information Architecture

Nexora is designed as a high-velocity utility. The UX prioritizes a "thumb-zone" friendly layout for one-handed use, following modern Material 3 principles.

## 1. Information Architecture (Bottom Navigation)
- **Home (Primary):** The "Control Center." All download actions happen here.
- **Downloads:** Active WebSocket-tracked jobs.
- **History:** Searchable archive of completed files.
- **Settings:** App preferences (download location, theme, etc.).

## 2. The "Fast-Path" Home Screen Workflow
To minimize taps, the Home screen uses a dynamic state-based layout:

### State A: Empty / Ready
- **Top:** Minimalist brand logo (Nexora).
- **Center:** Large, focused URL input field with a "Paste from Clipboard" shortcut.
- **Bottom:** Primary "Fetch" button positioned in the lower third for easy thumb reach.

### State B: Metadata Loaded (Post-Fetch)
- **Preview Card:** High-quality thumbnail, Title, Uploader, and Duration.
- **Selection Area:** 
    - **Video Qualities:** Horizontal chips or a simple list (e.g., 1080p, 720p, 480p).
    - **Audio Toggle:** A clear "Extract MP3" option.
- **Primary Action:** "Download" button replaces the "Fetch" button.

## 3. Interaction Design & Speed Optimizations
- **Auto-Paste:** When the app opens, it checks the clipboard for a valid URL and offers a one-tap paste/fetch.
- **One-Handed Focus:** Interactive elements (buttons, quality chips) are concentrated in the bottom 60% of the screen.
- **Status Feedback:** Smooth transitions between "Fetching," "Ready," and "Starting Download."

## 4. Scalability for Future Platforms
- The metadata card is platform-agnostic. 
- Whether it's a YouTube video, a TikTok, or an Instagram Reel, the UI remains consistent: **Thumbnail > Title > Quality Options > Download.**

---

**Next Steps:**
1. Establish a **Design System** (Colors, Typography, Material 3 components).
2. Generate the **Home Screen** (Ready and Loaded states).
3. Generate **Downloads, History, and Settings** screens.