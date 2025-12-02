# MakeGIF

Turn any video into a perfectly optimized GIF.

MakeGIF is a command-line tool that makes it easy to create high-quality GIFs from video files. It comes with a beautiful interactive interface, automatic black bar removal, and smart optimization to keep file sizes small.

## Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/nathan-kennedy/makegif/main/install.sh | bash
```

This will download MakeGIF, add it to your shell, and offer to install any missing dependencies.

## Features

- **Interactive TUI** - A guided step-by-step interface (powered by [gum](https://github.com/charmbracelet/gum)) that walks you through every option
- **High & Low Quality Modes** - High quality uses advanced palette generation for better colors; low quality is faster and smaller
- **Auto Black Bar Removal** - Automatically detects and removes letterbox bars from widescreen videos
- **Square Crop** - Crop GIFs to square for social media with customizable alignment
- **Smart Optimization** - Uses gifsicle to compress GIFs without losing quality
- **Flexible Time Input** - Enter times as `10`, `1:30`, or `01:30:45` — whatever's easiest
- **Works Everywhere** - macOS and Linux with bash or zsh

## Usage

MakeGIF has three ways to run:

### Interactive Mode (Recommended)

Just type `makegif` with no arguments. You'll get a beautiful interface that guides you through each step:

```bash
makegif
```

The TUI lets you browse for video files, preview your settings, and go back to change options before creating your GIF.

### Quick Command Mode

Pass all your options directly:

```bash
makegif video.mp4 0:30 5 output.gif high
```

This creates a 5-second GIF starting at 30 seconds into the video, using high quality mode.

### Full Syntax

```bash
makegif <video> <start> <duration> <output.gif> [quality] [width] [fps] [colors] [remove_bars] [square]
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `video` | Yes | - | Path to your video file (MP4, MOV, MKV, AVI, WebM, etc.) |
| `start` | Yes | - | Start time (`10`, `1:30`, or `01:30:45`) |
| `duration` | Yes | - | How long the GIF should be |
| `output.gif` | Yes | - | Output filename (must end in `.gif`) |
| `quality` | No | `low` | `high` for better colors, `low` for faster/smaller |
| `width` | No | `640` | Output width in pixels (32-7680) |
| `fps` | No | `10` | Frames per second (1-60) |
| `colors` | No | `256` | Color palette size (2-256). Lower = smaller files |
| `remove_bars` | No | `no` | `yes` to auto-remove black bars |
| `square` | No | `no` | `yes` to crop to square aspect ratio |

## Examples

**Basic GIF from a video:**
```bash
makegif movie.mp4 1:23:45 3 reaction.gif
```

**High quality, smaller size:**
```bash
makegif clip.mov 0 10 demo.gif high 480 15 128
```

**Remove letterbox bars:**
```bash
makegif widescreen.mp4 5:00 8 scene.gif low 640 10 256 yes
```

**Square crop for Instagram:**
```bash
# First create the GIF
makegif video.mp4 0:15 4 post.gif high

# Then crop it square (center-aligned)
squaregif post.gif post-square.gif center
```

### Square Crop Options

The `squaregif` command lets you choose which part to keep:

```bash
squaregif <input.gif> <output.gif> [alignment]
```

Alignment options: `left`, `right`, `center` (default), `top`, `bottom`

## Reducing File Size

GIFs can get large. Here's how to keep them small:

- **Lower the width** - `480` or `320` instead of `640`
- **Reduce colors** - `64` or `128` colors still look good and save a lot of space
- **Lower FPS** - `8` or `10` fps is usually smooth enough
- **Shorter duration** - Every second adds frames

## Dependencies

MakeGIF needs these tools installed:

- **ffmpeg** - Does the actual video processing
- **gifsicle** - Optimizes the final GIF
- **gum** (optional) - Powers the pretty TUI interface

The install script will offer to install these for you. If you prefer to install manually:

```bash
# macOS
brew install ffmpeg gifsicle gum

# Ubuntu/Debian
sudo apt install ffmpeg gifsicle
# For gum: https://github.com/charmbracelet/gum#installation

# Fedora
sudo dnf install ffmpeg gifsicle
```

## Manual Installation

If you prefer not to use the install script:

1. Download `makegif.sh` from this repo
2. Add this line to your `~/.zshrc` or `~/.bashrc`:

```bash
source /path/to/makegif.sh
```

3. Restart your terminal or run `source ~/.zshrc`

## Troubleshooting

**"command not found: makegif"**
- Make sure you've sourced the script in your shell config
- Try opening a new terminal window

**GIF is too large**
- Reduce width, colors, or fps (see "Reducing File Size" above)

**Colors look bad**
- Use `high` quality mode for better color accuracy
- Increase the color count (up to 256)

**Black bars still showing**
- Try `yes` for the `remove_bars` option
- The detection works best with solid black bars

## License

[MIT License](LICENSE)

## Contributing

Contributions welcome! Feel free to open issues or submit pull requests.
