# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MakeGIF is a bash-based CLI tool that converts video files to optimized GIFs. It features an interactive TUI (powered by `gum`), automatic black bar detection/removal, and smart optimization via `gifsicle`.

## Architecture

The entire tool is contained in a single file `makegif.sh` which is sourced into the user's shell. It provides two main functions:
- `makegif` - Main entry point with three modes: TUI (interactive with gum), standard interactive (text prompts), and argument mode
- `squaregif` - Utility to crop existing GIFs to square aspect ratio

### Key Components in makegif.sh

1. **Dependency checking** (`check_dependencies`, `check_and_install_gum`) - Validates ffmpeg/gifsicle are installed
2. **Input validation** (`validate_input_file`, `validate_output_path`, `validate_time_format`, `validate_numeric_param`) - Strict validation with helpful error messages
3. **Video processing** (`get_crop_params`, `create_gif`) - FFmpeg-based GIF creation with optional palette generation for high quality mode
4. **TUI system** (step_1 through step_10 functions, `makegif_tui`) - State machine-based navigation with back/forward support

### Processing Pipeline

1. Validate inputs and check dependencies
2. Optionally detect black bars via ffmpeg cropdetect
3. Generate color palette (high quality mode only)
4. Create GIF with ffmpeg using fps/scale/crop filters
5. Optimize with gifsicle for size reduction

## Testing Changes

No automated tests exist. To manually test:

```bash
# Source the script
source makegif.sh

# Test TUI mode (requires gum)
makegif

# Test argument mode
makegif video.mp4 0:00 5 output.gif high 480 15 128 no no

# Test square crop utility
squaregif input.gif output.gif center
```

## Dependencies

- **ffmpeg** - Video processing and GIF creation
- **gifsicle** - GIF optimization
- **gum** (optional) - TUI interface from Charm (charmbracelet/gum)

## Parameter Ranges

- width: 32-7680 pixels
- fps: 1-60
- colors: 2-256
- Time formats: seconds (10), MM:SS (1:30), HH:MM:SS (01:30:45)
