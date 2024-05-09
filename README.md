
# Music Zigulizer
## Inspired from Tsoding
**FFT Visualizer**

A dynamic and interactive music visualizer built with Zig and Raylib. Experience your music like never before!

**Features**

* **Drag-and-drop Simplicity:** Easily load your MP3 files directly into the visualizer.
* **Intuitive Playback Control:** Pause, restart, and switch songs effortlessly.
* **Customizable Visualizations:** Explore different visualization settings for unique experiences 
* **Hotkey Shortcuts:** Conveniently navigate and control the visualizer with keyboard shortcuts.

**Installation**

1. **Prerequisites:** 
   * Zig compiler ([https://ziglang.org/download/](https://ziglang.org/download/))
   * Raylib library ([https://www.raylib.com/](https://www.raylib.com/))
2. **Clone this repository:** `git clone https://github.com/your-username/fft-visualizer`
3. **Build:** `zig build -Drelease-fast=true` 
4. **Run:** `./zig-out/bin/fft-visualizer`

**Usage**

* Drag and drop an MP3 file onto the visualizer window.
* Enjoy the music and the synchronized visualizations!

**Hotkey Shortcuts**

* **SPACE:** Pause / Resume music
* **R:** Restart music 
* **G:** Load a new song (from a file dialog)
* **U:** Unload any currently loaded files
* **F:** List dropped files (for debugging)
* **L:** Switch to the next MP3 file among the dropped files
* **H:** Switch to the previous MP3 file among the dropped files

**Planned Features** (maybe)

* More visualization styles
* User-adjustable color schemes
* Ability to save visualization settings

