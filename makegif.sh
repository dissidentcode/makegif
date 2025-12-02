#!/bin/bash
# Script Created by DissidentCode github.carry327@passinbox.com

# Global temp file tracking
TEMP_FILES=()

# Function to clean up temporary files
cleanup() {
	if [ ${#TEMP_FILES[@]} -gt 0 ]; then
		rm -f "${TEMP_FILES[@]}" 2>/dev/null
	fi
}

# Set up cleanup trap globally
trap cleanup EXIT INT TERM

# Check if gum is installed and offer to install it
# Returns:
#   0 if gum is installed or successfully installed
#   1 if user declines installation or installation fails
check_and_install_gum() {
	if command -v gum &>/dev/null; then
		return 0
	fi

	echo "🎨 Enhanced TUI mode requires 'gum' (a lightweight, beautiful TUI tool)"
	echo ""
	read -r -p "Would you like to install gum? (yes/no): " install_gum

	if [ "$install_gum" != "yes" ]; then
		echo "Falling back to standard interactive mode..."
		return 1
	fi

	echo "Installing gum..."

	# Detect OS and install accordingly
	if [[ "$OSTYPE" == "darwin"* ]]; then
		if command -v brew &>/dev/null; then
			brew install gum
		else
			echo "Error: Homebrew not found. Please install Homebrew first." >&2
			return 1
		fi
	elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
		# Try to detect package manager
		if command -v apt-get &>/dev/null; then
			sudo mkdir -p /etc/apt/keyrings
			curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
			echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
			sudo apt-get update && sudo apt-get install -y gum
		elif command -v dnf &>/dev/null; then
			echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | sudo tee /etc/yum.repos.d/charm.repo
			sudo dnf install -y gum
		else
			echo "Error: Unsupported package manager. Please install gum manually:" >&2
			echo "  https://github.com/charmbracelet/gum#installation" >&2
			return 1
		fi
	else
		echo "Error: Unsupported OS. Please install gum manually:" >&2
		echo "  https://github.com/charmbracelet/gum#installation" >&2
		return 1
	fi

	# Verify installation
	if command -v gum &>/dev/null; then
		echo "✅ Successfully installed gum!"
		return 0
	else
		echo "Error: gum installation failed." >&2
		return 1
	fi
}

# Check if required dependencies (ffmpeg and gifsicle) are installed
# Provides platform-specific installation instructions if dependencies are missing
# Returns:
#   0 if all dependencies are installed
#   Number of missing dependencies otherwise
check_dependencies() {
	local missing_deps=0
	local deps_list=""

	for dep in ffmpeg gifsicle; do
		if ! command -v "$dep" &>/dev/null; then
			echo "Error: $dep is not installed or not in PATH." >&2
			missing_deps=$((missing_deps + 1))
			deps_list="$deps_list $dep"
		fi
	done

	if [ $missing_deps -gt 0 ]; then
		echo "" >&2
		echo "Missing dependencies:$deps_list" >&2
		echo "" >&2
		echo "To install on macOS with Homebrew:" >&2
		echo "  brew install$deps_list" >&2
		echo "" >&2
		echo "To install on Ubuntu/Debian:" >&2
		echo "  sudo apt-get install$deps_list" >&2
		echo "" >&2
		echo "To install on Fedora/RHEL:" >&2
		echo "  sudo dnf install$deps_list" >&2
		echo "" >&2
	fi

	return $missing_deps
}

# Detect black bars in a video and return crop parameters
# Uses adaptive sampling: samples at 10% into video (or 5 minutes max) for better detection
# Parameters:
#   $1 - source_video: Path to the video file
# Returns:
#   0 and outputs crop parameters (format: width:height:x:y) on success
#   1 if crop detection fails or video duration cannot be determined
get_crop_params() {
	local source_video=$1

	# Get video duration using ffprobe
	local video_duration=$(ffprobe -v error -show_entries format=duration \
		-of default=noprint_wrappers=1:nokey=1 "$source_video" 2>/dev/null)

	if [ -z "$video_duration" ]; then
		echo "Error: Could not determine video duration for crop detection." >&2
		return 1
	fi

	# Choose sample point (10% into video, or 5 minutes max)
	local sample_time=$(echo "$video_duration * 0.1" | bc | cut -d. -f1)
	[ "$sample_time" -gt 300 ] && sample_time=300

	# Sample duration (10 seconds or remaining duration)
	local sample_duration=$(echo "$video_duration - $sample_time" | bc | cut -d. -f1)
	[ "$sample_duration" -gt 10 ] && sample_duration=10
	[ "$sample_duration" -lt 1 ] && sample_time=0 && sample_duration=1

	echo "Detecting black bars (sampling ${sample_duration}s at ${sample_time}s)..." >&2

	local crop_params=$(ffmpeg -ss "$sample_time" -t "$sample_duration" -i "$source_video" \
		-vf "cropdetect=24:16:0" -f null - 2>&1 | \
		grep -oE 'crop=[0-9]+:[0-9]+:[0-9]+:[0-9]+' | \
		sort | uniq -c | sort -nr | head -n 1 | awk '{print $2}' | sed 's/crop=//')

	if [ -z "$crop_params" ]; then
		echo "Warning: Could not detect black bars." >&2
		echo "  This may mean: no black bars, irregular bars, or incompatible format" >&2
		return 1
	fi

	echo "Detected crop parameters: $crop_params" >&2
	echo "$crop_params"
}

# Validate input video file path
# Expands tilde paths, checks file existence, readability, and validates it's a video
# Parameters:
#   $1 - file: Path to the video file (may contain ~)
# Returns:
#   0 and outputs expanded path on success
#   1 if file doesn't exist, isn't readable, or isn't a valid video
validate_input_file() {
	local file=$1

	# Expand tilde properly
	file="${file/#\~/$HOME}"

	# Check existence
	if [ ! -f "$file" ]; then
		echo "Error: File '$file' does not exist." >&2
		return 1
	fi

	# Check readability
	if [ ! -r "$file" ]; then
		echo "Error: Cannot read file '$file' (permission denied)." >&2
		return 1
	fi

	# Validate file type using ffprobe - check if it has a video stream
	if ! ffprobe -v error -select_streams v:0 -show_entries stream=codec_type -of csv=p=0 "$file" 2>/dev/null | grep -q "video"; then
		echo "Error: '$file' does not appear to be a valid video file." >&2
		return 1
	fi

	echo "$file"
}

# Validate output GIF file path
# Checks filename ends with .gif, prompts for overwrite if exists, validates directory is writable
# Parameters:
#   $1 - output: Path to the output GIF file
# Returns:
#   0 and outputs validated path on success
#   1 if path is invalid, directory doesn't exist/isn't writable, or user cancels overwrite
validate_output_path() {
	local output=$1

	# Check if output ends with .gif
	if [[ ! "$output" =~ \.gif$ ]]; then
		echo "Error: Output file must end with '.gif'. Got: '$output'" >&2
		return 1
	fi

	# Check if file already exists
	if [ -f "$output" ]; then
		echo "Warning: File '$output' already exists." >&2
		read -r -p "Overwrite? (yes/no): " confirm
		if [ "$confirm" != "yes" ]; then
			echo "Operation cancelled." >&2
			return 1
		fi
	fi

	# Check directory is writable
	local dir=$(dirname "$output")
	if [ ! -d "$dir" ]; then
		echo "Error: Directory '$dir' does not exist." >&2
		return 1
	fi

	if [ ! -w "$dir" ]; then
		echo "Error: Cannot write to directory '$dir' (permission denied)." >&2
		return 1
	fi

	echo "$output"
}

# Validate time format parameter
# Accepts: HH:MM:SS, MM:SS, seconds (with optional decimal)
# Parameters:
#   $1 - time: Time value to validate
#   $2 - param_name: Name of parameter for error messages
# Returns:
#   0 if time format is valid
#   1 if time format is invalid
validate_time_format() {
	local time=$1
	local param_name=$2

	# Accept formats: HH:MM:SS, MM:SS, SS, or numeric seconds (with optional decimals)
	if [[ "$time" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
		# Plain seconds - valid
		return 0
	elif [[ "$time" =~ ^[0-9]{1,2}:[0-9]{2}$ ]]; then
		# MM:SS format - valid
		return 0
	elif [[ "$time" =~ ^[0-9]{1,2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?$ ]]; then
		# HH:MM:SS format (with optional milliseconds) - valid
		return 0
	else
		echo "Error: Invalid $param_name format: '$time'" >&2
		echo "  Accepted formats: HH:MM:SS, MM:SS, seconds (e.g., 10, 1:30, 01:30:00)" >&2
		return 1
	fi
}

# Validate numeric parameter is within specified bounds
# Parameters:
#   $1 - value: Value to validate
#   $2 - param_name: Name of parameter for error messages
#   $3 - min: Minimum allowed value
#   $4 - max: Maximum allowed value
# Returns:
#   0 if value is valid (positive integer within bounds)
#   1 if value is invalid (non-numeric, negative, or out of bounds)
validate_numeric_param() {
	local value=$1
	local param_name=$2
	local min=$3
	local max=$4

	# Check if numeric
	if ! [[ "$value" =~ ^[0-9]+$ ]]; then
		echo "Error: $param_name must be a positive integer. Got: '$value'" >&2
		return 1
	fi

	# Check bounds
	if [ "$value" -lt "$min" ]; then
		echo "Error: $param_name must be at least $min. Got: $value" >&2
		return 1
	fi

	if [ "$value" -gt "$max" ]; then
		echo "Error: $param_name cannot exceed $max. Got: $value" >&2
		return 1
	fi

	return 0
}

# Create a GIF from a video file segment
# Main function that handles GIF creation with optional high quality palette generation,
# black bar removal, and square aspect ratio conversion
# Parameters:
#   $1  - source_video: Path to input video file
#   $2  - start_time: Start timestamp (HH:MM:SS, MM:SS, or seconds)
#   $3  - duration: Length of GIF (HH:MM:SS, MM:SS, or seconds)
#   $4  - output_gif: Path to output .gif file
#   $5  - quality: 'high' or 'low' (default: low)
#   $6  - width: Width in pixels (default: 640)
#   $7  - fps: Frames per second (default: 10)
#   $8  - num_colors: Color palette size 2-256 (default: 256)
#   $9  - remove_black_bars: 'yes' or 'no' (default: no)
#   $10 - square_aspect: 'yes' or 'no' (default: no)
# Returns:
#   0 on success
#   1 on failure (invalid input, ffmpeg error, gifsicle error, etc.)
create_gif() {
	local source_video=$1
	local start_time=$2
	local duration=$3
	local output_gif=$4
	local quality=$5
	local width=$6
	local fps=$7
	local num_colors=$8
	local remove_black_bars=$9
	local square_aspect=${10}

	# Validate input file and output path
	source_video=$(validate_input_file "$source_video") || return 1
	output_gif=$(validate_output_path "$output_gif") || return 1

	# Validate time formats
	validate_time_format "$start_time" "start time" || return 1
	validate_time_format "$duration" "duration" || return 1

	# Validate numeric parameters
	validate_numeric_param "$width" "width" 32 7680 || return 1
	validate_numeric_param "$fps" "fps" 1 60 || return 1
	validate_numeric_param "$num_colors" "number of colors" 2 256 || return 1

	local filters="fps=$fps"

	# Apply crop first if removing black bars
	if [ "$remove_black_bars" = "yes" ]; then
		local crop_params=$(get_crop_params "$source_video")
		if [ -n "$crop_params" ]; then
			filters="$filters,crop=$crop_params"
		else
			echo "Warning: Could not detect black bars, proceeding without crop."
		fi
	fi

	# Then apply scaling (square or width-based)
	if [ "$square_aspect" = "yes" ]; then
		# Scale to fill square (increase ensures smaller dimension matches target), then center crop
		filters="$filters,scale=${width}:${width}:force_original_aspect_ratio=increase,crop=${width}:${width}"
	else
		filters="$filters,scale=${width}:-1"
	fi

	# Create unique temp files (add to cleanup array immediately)
	# Note: mktemp on macOS requires XXXXXX at end, so we append extension after
	local temp_gif="$(mktemp "${TMPDIR:-/tmp}/makegif_gif_XXXXXX").gif"
	TEMP_FILES+=("$temp_gif")  # Add immediately to minimize cleanup race condition

	local palette="$(mktemp "${TMPDIR:-/tmp}/makegif_palette_XXXXXX").png"
	TEMP_FILES+=("$palette")   # Add immediately to minimize cleanup race condition

	local use_gum=false
	command -v gum &>/dev/null && use_gum=true

	if [ "$use_gum" = true ]; then
		gum style --foreground 33 --bold "Creating your GIF..."
		gum style --foreground 242 "  Source: $source_video"
		gum style --foreground 242 "  Segment: $start_time + $duration"
		gum style --foreground 242 "  Dimensions: ${width}px width"
		gum style --foreground 242 "  Quality: $quality"
		echo ""
	else
		echo "Creating GIF (this may take a few minutes)..."
		echo "  Source: $source_video"
		echo "  Segment: $start_time + $duration"
		echo "  Dimensions: ${width}px width"
		echo "  Quality: $quality"
		echo "  Filters: $filters"
		echo ""
	fi

	local ffmpeg_output
	if [ "$quality" = "high" ]; then
		if [ "$use_gum" = true ]; then
			gum style --foreground 242 "  Generating color palette..."
			ffmpeg -v warning -ss "$start_time" -t "$duration" -i "$source_video" \
				-filter_complex "$filters,palettegen=stats_mode=full" -y "$palette" >/dev/null 2>&1
			local palette_exit=$?
		else
			echo "Step 1/2: Generating optimized color palette..."
			ffmpeg_output=$(ffmpeg -v warning -stats -ss "$start_time" -t "$duration" -i "$source_video" \
				-filter_complex "$filters,palettegen=stats_mode=full" -y "$palette" 2>&1)
			local palette_exit=$?
		fi

		if [ $palette_exit -ne 0 ]; then
			if [ "$use_gum" = true ]; then
				gum style --foreground 196 "Palette generation failed. Check your input file."
			else
				echo "Error: Palette generation failed." >&2
				echo "FFmpeg output:" >&2
				echo "$ffmpeg_output" >&2
			fi
			return 1
		fi

		if [ "$use_gum" = true ]; then
			gum style --foreground 242 "  Creating GIF with palette..."
			ffmpeg -v warning -ss "$start_time" -t "$duration" -i "$source_video" -i "$palette" \
				-filter_complex "$filters,paletteuse=dither=floyd_steinberg:diff_mode=rectangle" \
				-an "$temp_gif" >/dev/null 2>&1
			local gif_exit=$?
		else
			echo "Step 2/2: Creating GIF with palette..."
			ffmpeg_output=$(ffmpeg -v warning -stats -ss "$start_time" -t "$duration" -i "$source_video" -i "$palette" \
				-filter_complex "$filters,paletteuse=dither=floyd_steinberg:diff_mode=rectangle" \
				-an "$temp_gif" 2>&1)
			local gif_exit=$?
		fi

		if [ $gif_exit -ne 0 ]; then
			if [ "$use_gum" = true ]; then
				gum style --foreground 196 "GIF creation failed. Check your input file and settings."
			else
				echo "Error: GIF creation failed." >&2
				echo "FFmpeg output:" >&2
				echo "$ffmpeg_output" >&2
			fi
			return 1
		fi
	else
		if [ "$use_gum" = true ]; then
			gum style --foreground 242 "  Creating GIF..."
			ffmpeg -v warning -ss "$start_time" -t "$duration" -i "$source_video" \
				-vf "$filters" -an "$temp_gif" >/dev/null 2>&1
			local gif_exit=$?
		else
			echo "Creating GIF..."
			ffmpeg_output=$(ffmpeg -v warning -stats -ss "$start_time" -t "$duration" -i "$source_video" \
				-vf "$filters" -an "$temp_gif" 2>&1)
			local gif_exit=$?
		fi

		if [ $gif_exit -ne 0 ]; then
			if [ "$use_gum" = true ]; then
				gum style --foreground 196 "GIF creation failed. Check your input file and settings."
			else
				echo "Error: GIF creation failed." >&2
				echo "FFmpeg output:" >&2
				echo "$ffmpeg_output" >&2
			fi
			return 1
		fi
	fi

	# Verify temp GIF was created
	if [ ! -f "$temp_gif" ]; then
		if [ "$use_gum" = true ]; then
			gum style --foreground 196 "Temporary GIF was not created."
		else
			echo "Error: Temporary GIF was not created." >&2
		fi
		return 1
	fi

	local temp_size=$(du -h "$temp_gif" | cut -f1)

	if [ "$use_gum" = true ]; then
		echo ""
		gum style --foreground 242 "  Optimizing GIF..."
		gifsicle -O3 --colors "$num_colors" "$temp_gif" -o "$output_gif" >/dev/null 2>&1
		local gifsicle_exit=$?
	else
		echo ""
		echo "Optimizing GIF (this may take a minute)..."
		echo "  Unoptimized size: $temp_size"
		echo "  Target colors: $num_colors"
		local gifsicle_output=$(gifsicle -O3 --colors "$num_colors" "$temp_gif" -o "$output_gif" 2>&1)
		local gifsicle_exit=$?
	fi

	if [ $gifsicle_exit -ne 0 ]; then
		if [ "$use_gum" = true ]; then
			gum style --foreground 196 "GIF optimization failed."
		else
			echo "Error: GIF optimization failed." >&2
		fi
		return 1
	fi

	if [ ! -f "$output_gif" ]; then
		if [ "$use_gum" = true ]; then
			gum style --foreground 196 "Output GIF was not created."
		else
			echo "Error: Output GIF was not created." >&2
		fi
		return 1
	fi

	rm "$temp_gif"

	local final_size=$(du -h "$output_gif" | cut -f1)

	if [ "$use_gum" = true ]; then
		echo ""
		gum style \
			--foreground 214 --border-foreground 214 --border rounded \
			--align center --width 60 --margin "1 2" --padding "1 2" \
			"Success! GIF created!" \
			"" \
			"File: $output_gif" \
			"Size: $final_size (was $temp_size)"
	else
		echo ""
		echo "Success! GIF created: $output_gif"
		echo "  Final size: $final_size (was $temp_size)"
	fi
}

# ============================================================================
# TUI COLOR PALETTE
# ============================================================================
readonly COLOR_HEADER=212        # Magenta for headers
readonly COLOR_HEADER_ALT=51     # Cyan for accents
readonly COLOR_STEP=51           # Bright cyan for steps
readonly COLOR_TEXT=15           # White for text
readonly COLOR_HINT=242          # Dim gray for hints
readonly COLOR_SUCCESS=46        # Bright green for success
readonly COLOR_ERROR=196         # Bright red for errors
readonly COLOR_SELECTION=226     # Yellow for selections

# Validate color constants
validate_colors() {
	# Directly validate each color constant (more portable than indirection)
	[[ "$COLOR_HEADER" =~ ^[0-9]+$ ]] || { echo "Error: Invalid COLOR_HEADER" >&2; return 1; }
	[[ "$COLOR_HEADER_ALT" =~ ^[0-9]+$ ]] || { echo "Error: Invalid COLOR_HEADER_ALT" >&2; return 1; }
	[[ "$COLOR_STEP" =~ ^[0-9]+$ ]] || { echo "Error: Invalid COLOR_STEP" >&2; return 1; }
	[[ "$COLOR_TEXT" =~ ^[0-9]+$ ]] || { echo "Error: Invalid COLOR_TEXT" >&2; return 1; }
	[[ "$COLOR_HINT" =~ ^[0-9]+$ ]] || { echo "Error: Invalid COLOR_HINT" >&2; return 1; }
	[[ "$COLOR_SUCCESS" =~ ^[0-9]+$ ]] || { echo "Error: Invalid COLOR_SUCCESS" >&2; return 1; }
	[[ "$COLOR_ERROR" =~ ^[0-9]+$ ]] || { echo "Error: Invalid COLOR_ERROR" >&2; return 1; }
	[[ "$COLOR_SELECTION" =~ ^[0-9]+$ ]] || { echo "Error: Invalid COLOR_SELECTION" >&2; return 1; }
	return 0
}

# ============================================================================
# TUI HELPER FUNCTIONS
# ============================================================================

# Draw simple header
tui_draw_header() {
	echo ""
	gum style --foreground $COLOR_HEADER --bold --align center \
		'█▀▄▀█ ▄▀█ █▄▀ █▀▀ █▀▀ █ █▀▀' \
		'█ ▀ █ █▀█ █ █ ██▄ █▄█ █ █▀'
	echo ""
}

# Clear screen and redraw header
tui_clear_and_header() {
	clear
	tui_draw_header
	echo ""
}

# Draw progress bar showing current step
tui_progress() {
	local current=$1
	local total=$2
	local filled=$((current * 20 / total))
	local empty=$((20 - filled))
	local bar=$(printf '█%.0s' $(seq 1 $filled))$(printf '░%.0s' $(seq 1 $empty))
	gum style --foreground $COLOR_HEADER "$bar  Step $current of $total"
	echo ""
}

# Show step with prominent styling
tui_show_step() {
	local title=$1
	local hint=$2
	gum style --foreground $COLOR_STEP --bold "$title"
	[ -n "$hint" ] && gum style --foreground $COLOR_HINT "   $hint"
}

# Show success message
tui_success() {
	gum style --foreground $COLOR_SUCCESS "✓ $1"
}

# Show error message
tui_error() {
	gum style --foreground $COLOR_ERROR "✗ $1"
}

# Validate time format (returns 0 if valid)
tui_validate_time() {
	local time=$1
	[[ "$time" =~ ^[0-9]+(\.[0-9]+)?$ ]] && return 0
	[[ "$time" =~ ^[0-9]{1,2}:[0-9]{2}$ ]] && return 0
	[[ "$time" =~ ^[0-9]{1,2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?$ ]] && return 0
	return 1
}

# Convert time string to seconds
convert_time_to_seconds() {
	local time=$1
	if [[ "$time" =~ ^[0-9]+$ ]]; then
		echo "$time"
	elif [[ "$time" =~ ^([0-9]+):([0-9]+)$ ]]; then
		echo $(( ${BASH_REMATCH[1]} * 60 + ${BASH_REMATCH[2]} ))
	elif [[ "$time" =~ ^([0-9]+):([0-9]+):([0-9]+)$ ]]; then
		echo $(( ${BASH_REMATCH[1]} * 3600 + ${BASH_REMATCH[2]} * 60 + ${BASH_REMATCH[3]} ))
	else
		echo "5"  # fallback
	fi
}

# Get video duration in seconds
get_video_duration() {
	ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null | cut -d. -f1
}

# Select video file using gum filter
select_video_file_tui() {
	gum style --foreground $COLOR_HINT "Searching for video files..." >&2
	echo "" >&2

	local videos=""

	# Only search current directory if it's not huge (avoid slowness)
	local pwd_file_count=$(find . -maxdepth 1 -type f 2>/dev/null | wc -l)
	if [ "$pwd_file_count" -lt 1000 ]; then
		# Safe to search current directory (with timeout and reduced depth)
		videos=$(timeout 3 find . -maxdepth 2 -type f \( \
			-name "*.mp4" -o -name "*.mov" -o -name "*.avi" -o \
			-name "*.mkv" -o -name "*.webm" -o -name "*.m4v" -o -name "*.flv" \) \
			2>/dev/null | head -n 50)
	fi

	# Search common directories (with timeout)
	local common_videos=$(timeout 5 find "$HOME/Movies" "$HOME/Downloads" "$HOME/Desktop" \
		-maxdepth 3 -type f \( \
		-name "*.mp4" -o -name "*.mov" -o -name "*.avi" -o \
		-name "*.mkv" -o -name "*.webm" -o -name "*.m4v" -o -name "*.flv" \) \
		2>/dev/null | head -n 150)

	# Combine results (remove duplicates, limit to 200)
	if [ -n "$videos" ] && [ -n "$common_videos" ]; then
		videos=$(printf "%s\n%s" "$videos" "$common_videos" | sort -u | head -n 200)
	elif [ -n "$common_videos" ]; then
		videos="$common_videos"
	fi

	if [ -z "$videos" ]; then
		# No videos found - ask user to enter path manually
		gum style --foreground $COLOR_HINT "No videos found in common directories" >&2
		echo "" >&2
		gum style --foreground $COLOR_TEXT "Enter the full path to your video file:" >&2
		gum input --placeholder "/path/to/video.mp4"
	else
		# Show filtered list with browse and manual entry options
		local count=$(echo "$videos" | wc -l | tr -d ' ')
		gum style --foreground $COLOR_SUCCESS "Found $count video files" >&2
		echo "" >&2

		# Add special options to the list
		local options=$(printf "📁 Browse files...\n✏️  Enter path manually...\n%s" "$videos")
		local selection=$(echo "$options" | gum filter --height 12 --placeholder "Type to search..." --prompt "Select: " --indicator "➤ " --indicator.foreground $COLOR_SELECTION)

		# Check which option was selected
		if [[ "$selection" == "📁 Browse files..." ]]; then
			tui_clear_and_header >&2
			tui_progress 1 10 >&2
			tui_show_step "Browse for video file" >&2
			echo "" >&2
			gum file --height 15 --cursor "➤ " --cursor.foreground $COLOR_SELECTION
		elif [[ "$selection" == "✏️  Enter path manually..." ]]; then
			tui_clear_and_header >&2
			tui_progress 1 10 >&2
			tui_show_step "Enter video file path" >&2
			echo "" >&2
			gum input --placeholder "/path/to/video.mp4" --width 80
		else
			echo "$selection"
		fi
	fi
}

# TUI interactive mode using gum
# Provides a beautiful, colorful interface for creating GIFs
# Returns:
#   0 on success
#   1 on failure or cancellation
# Step 1: Select source video
step_1_select_video() {
	local total_steps=10

	while true; do
		tui_clear_and_header
		tui_progress 1 $total_steps
		tui_show_step "Select your video file" "Use arrow keys or type to search"
		echo ""

		source_video=$(select_video_file_tui)
		local gum_exit=$?

		# Handle cancel
		if [ $gum_exit -ne 0 ] || [ -z "$source_video" ]; then
			local choice=$(gum choose "🔙 Exit" "🔁 Try again" --height 3 --header "What would you like to do?")
			case "$choice" in
				"🔙 Exit")
					if gum confirm "Are you sure you want to exit?"; then
						STEP_ACTION="exit"
						return
					fi
					continue ;;
				"🔁 Try again") continue ;;
				*) continue ;;
			esac
		fi

		# Trim whitespace and quotes from user input
		source_video=$(echo "$source_video" | xargs | tr -d "'\"")

		# Validate - capture stderr to show user if it fails
		local validation_result
		validation_result=$(validate_input_file "$source_video" 2>&1)
		local validation_exit=$?

		if [ $validation_exit -eq 0 ]; then
			source_video="$validation_result"
			tui_clear_and_header
			tui_progress 1 $total_steps
			tui_show_step "Select your video file"
			echo ""
			tui_success "Selected: $(basename "$source_video")"

			# Show video info
			vid_duration=$(get_video_duration "$source_video")
			[ -n "$vid_duration" ] && gum style --foreground $COLOR_HINT "   Duration: ${vid_duration}s"

			sleep 0.8
			STEP_ACTION="next"
			return
		else
			# Strip ANSI codes from validation error
			local clean_error=$(echo "$validation_result" | sed 's/\x1b\[[0-9;]*[mGKH]//g')

			tui_error "Not a valid video file"
			echo ""
			# Display error without gum style to avoid ANSI conflicts
			if [ -n "$clean_error" ]; then
				echo "$clean_error"  # Show full error
			fi
			echo ""
			gum style --foreground $COLOR_HINT "Please select an MP4, MOV, MKV, or other video file"
			echo ""
			gum style --foreground $COLOR_SELECTION "Press Enter to continue..."
			read -r
		fi
	done
}

# Step 2: Start time
step_2_start_time() {
	local total_steps=10

	while true; do
		tui_clear_and_header
		tui_progress 2 $total_steps
		tui_show_step "Enter start time" "Format: seconds (10), MM:SS (1:30), or HH:MM:SS (01:30:45)"
		echo ""

		start_time=$(gum input --placeholder "0" --prompt "Start time: " --width 30)
		local gum_exit=$?

		# Check for cancel (escape key)
		if [ $gum_exit -ne 0 ]; then
			local choice=$(gum choose "⬅️  Go back" "🔙 Exit" "🔁 Try again" --height 4 --header "What would you like to do?")
			case "$choice" in
				"⬅️  Go back") STEP_ACTION="back"; return ;;
				"🔙 Exit")
					if gum confirm "Are you sure you want to exit?"; then
						STEP_ACTION="exit"
						return
					fi
					continue ;;
				"🔁 Try again") continue ;;
				*) continue ;;
			esac
		fi

		# Process input and validate
		start_time=$(echo "$start_time" | xargs)
		if [ -z "$start_time" ]; then
			start_time="0"
		fi

		if tui_validate_time "$start_time"; then
			start_sec=$(convert_time_to_seconds "$start_time")
			if [ -n "$vid_duration" ] && [ "$start_sec" -ge "$vid_duration" ]; then
				tui_error "Start time (${start_sec}s) exceeds video duration (${vid_duration}s)"
				sleep 1.5
				continue
			fi

			tui_success "Start time: $start_time"
			sleep 0.5
			STEP_ACTION="next"
			return
		else
			tui_error "Invalid time format"
			gum style --foreground $COLOR_HINT "Examples: 0, 10, 1:30, 0:01:30"
			sleep 1.5
			continue
		fi
	done
}

# Step 3: Duration
step_3_duration() {
	local total_steps=10

	while true; do
		tui_clear_and_header
		tui_progress 3 $total_steps
		tui_show_step "Enter duration" "Tip: Keep under 10 seconds for reasonable file sizes"
		echo ""

		duration=$(gum input --placeholder "5" --prompt "Duration: " --width 30)
		local gum_exit=$?

		# Check for cancel (escape key)
		if [ $gum_exit -ne 0 ]; then
			local choice=$(gum choose "⬅️  Go back" "🔙 Exit" "🔁 Try again" --height 4 --header "What would you like to do?")
			case "$choice" in
				"⬅️  Go back") STEP_ACTION="back"; return ;;
				"🔙 Exit")
					if gum confirm "Are you sure you want to exit?"; then
						STEP_ACTION="exit"
						return
					fi
					continue ;;
				"🔁 Try again") continue ;;
				*) continue ;;
			esac
		fi

		# Process input and validate
		duration=$(echo "$duration" | xargs)
		if [ -z "$duration" ]; then
			duration="5"
		fi

		if tui_validate_time "$duration"; then
			duration_sec=$(convert_time_to_seconds "$duration")

			if [ "$duration_sec" -le 0 ]; then
				tui_error "Duration must be greater than 0"
				sleep 1.5
				continue
			fi

			# Check against video duration if available
			if [ -n "$vid_duration" ] && [ -n "$start_sec" ]; then
				local remaining=$((vid_duration - start_sec))
				if [ "$duration_sec" -gt "$remaining" ]; then
					tui_error "Duration (${duration_sec}s) exceeds remaining video (${remaining}s)"
					gum style --foreground $COLOR_HINT "Max duration from start point: ${remaining}s"
					sleep 2
					continue
				fi
			fi

			tui_success "Duration: $duration"
			sleep 0.5
			STEP_ACTION="next"
			return
		else
			tui_error "Invalid time format"
			gum style --foreground $COLOR_HINT "Examples: 5, 10.5, 1:30, 0:05:00"
			sleep 1.5
			continue
		fi
	done
}

# Step 4: Output filename
step_4_output_filename() {
	local total_steps=10

	while true; do
		tui_clear_and_header
		tui_progress 4 $total_steps
		tui_show_step "Choose output location"
		echo ""

		# Offer common directories
		local current_dir_display=$(pwd | sed "s|$HOME|~|")
		local dir_choice=$(gum choose \
			"📂 Current directory ($current_dir_display)" \
			"🖥️  Desktop" \
			"📥 Downloads" \
			"✏️  Enter custom path..." \
			--height 6 --header "Where to save the GIF?" --cursor "➤ " --cursor.foreground $COLOR_SELECTION)

		local gum_exit=$?
		if [ $gum_exit -ne 0 ]; then
			# Handle escape/back
			local choice=$(gum choose "⬅️  Go back" "🔙 Exit" "🔁 Try again" --height 4 --header "What would you like to do?")
			case "$choice" in
				"⬅️  Go back") STEP_ACTION="back"; return ;;
				"🔙 Exit")
					if gum confirm "Are you sure you want to exit?"; then
						STEP_ACTION="exit"
						return
					fi
					continue ;;
				*) continue ;;
			esac
		fi

		# Set output directory based on choice
		local output_dir
		case "$dir_choice" in
			*"Current directory"*) output_dir="$(pwd)" ;;
			*"Desktop"*) output_dir="$HOME/Desktop" ;;
			*"Downloads"*) output_dir="$HOME/Downloads" ;;
			*"Enter custom"*)
				tui_clear_and_header
				tui_progress 4 $total_steps
				tui_show_step "Enter output directory"
				echo ""
				output_dir=$(gum input --placeholder "$HOME/Movies" --prompt "Directory: " --width 60)
				output_dir=$(echo "$output_dir" | xargs)
				# Expand tilde
				output_dir="${output_dir/#\~/$HOME}"
				;;
		esac

		# Validate directory exists
		if [ ! -d "$output_dir" ]; then
			tui_error "Directory does not exist: $output_dir"
			sleep 1.5
			continue
		fi

		if [ ! -w "$output_dir" ]; then
			tui_error "Cannot write to directory: $output_dir"
			sleep 1.5
			continue
		fi

		# Now ask for filename
		tui_clear_and_header
		tui_progress 4 $total_steps
		local dir_display=$(echo "$output_dir" | sed "s|$HOME|~|")
		tui_show_step "Enter filename" "Will be saved to: $dir_display"
		echo ""

		local filename=$(gum input --placeholder "output.gif" --prompt "Filename: " --width 40)
		local input_exit=$?

		# Check for cancel on filename input
		if [ $input_exit -ne 0 ]; then
			continue  # Go back to directory selection
		fi

		filename=$(echo "$filename" | xargs)

		if [ -z "$filename" ]; then
			filename="output.gif"
		fi

		# Auto-add .gif extension
		[[ "$filename" != *.gif ]] && filename="${filename}.gif"

		# Combine path
		output_gif="$output_dir/$filename"

		# Check if file exists
		if [ -f "$output_gif" ]; then
			if ! gum confirm "File exists. Overwrite $output_gif?"; then
				continue
			fi
		fi

		tui_success "Output: $output_gif"
		sleep 0.5
		STEP_ACTION="next"
		return
	done
}

# Step 5: Quality
step_5_quality() {
	local total_steps=10

	while true; do
		tui_clear_and_header
		tui_progress 5 $total_steps
		tui_show_step "Select quality" "High = better colors but slower"
		echo ""

		quality=$(gum choose --height 5 --cursor "➤ " --cursor.foreground $COLOR_SELECTION --selected.foreground $COLOR_SELECTION "high" "low")
		local gum_exit=$?

		# Check for cancel (escape key)
		if [ $gum_exit -ne 0 ] || [ -z "$quality" ]; then
			local choice=$(gum choose "⬅️  Go back" "🔙 Exit" "🔁 Try again" --height 4 --header "What would you like to do?")
			case "$choice" in
				"⬅️  Go back") STEP_ACTION="back"; return ;;
				"🔙 Exit")
					if gum confirm "Are you sure you want to exit?"; then
						STEP_ACTION="exit"
						return
					fi
					continue ;;
				"🔁 Try again") continue ;;
				*) continue ;;
			esac
		fi

		tui_success "Quality: $quality"
		sleep 0.5
		STEP_ACTION="next"
		return
	done
}

# Step 6: Width
step_6_width() {
	local total_steps=10

	while true; do
		tui_clear_and_header
		tui_progress 6 $total_steps
		tui_show_step "Select width" "Smaller = smaller file size"
		echo ""

		width=$(gum choose --height 8 --cursor "➤ " --cursor.foreground $COLOR_SELECTION --selected.foreground $COLOR_SELECTION "480" "640" "800" "1024" "1280" "Custom...")
		local gum_exit=$?

		# Check for cancel (escape key)
		if [ $gum_exit -ne 0 ] || [ -z "$width" ]; then
			local choice=$(gum choose "⬅️  Go back" "🔙 Exit" "🔁 Try again" --height 4 --header "What would you like to do?")
			case "$choice" in
				"⬅️  Go back") STEP_ACTION="back"; return ;;
				"🔙 Exit")
					if gum confirm "Are you sure you want to exit?"; then
						STEP_ACTION="exit"
						return
					fi
					continue ;;
				"🔁 Try again") continue ;;
				*) continue ;;
			esac
		fi

		if [ "$width" = "Custom..." ]; then
			width=$(gum input --placeholder "640" --prompt "Custom width: " --width 20)
			local custom_exit=$?

			# Check for cancel
			if [ $custom_exit -ne 0 ]; then
				continue
			fi

			# Trim whitespace
			width=$(echo "$width" | xargs)

			# Apply default if empty
			if [ -z "$width" ]; then
				width="640"
			fi
		fi

		if validate_numeric_param "$width" "width" 32 7680 2>/dev/null; then
			tui_success "Width: ${width}px"
			sleep 0.5
			STEP_ACTION="next"
			return
		fi
		tui_error "Width must be 32-7680"
		sleep 1
	done
}

# Step 7: FPS
step_7_fps() {
	local total_steps=10

	while true; do
		tui_clear_and_header
		tui_progress 7 $total_steps
		tui_show_step "Select frame rate (FPS)" "Higher = smoother but larger file"
		echo ""

		fps=$(gum choose --height 8 --cursor "➤ " --cursor.foreground $COLOR_SELECTION --selected.foreground $COLOR_SELECTION "10" "15" "20" "24" "30" "Custom...")
		local gum_exit=$?

		# Check for cancel (escape key)
		if [ $gum_exit -ne 0 ] || [ -z "$fps" ]; then
			local choice=$(gum choose "⬅️  Go back" "🔙 Exit" "🔁 Try again" --height 4 --header "What would you like to do?")
			case "$choice" in
				"⬅️  Go back") STEP_ACTION="back"; return ;;
				"🔙 Exit")
					if gum confirm "Are you sure you want to exit?"; then
						STEP_ACTION="exit"
						return
					fi
					continue ;;
				"🔁 Try again") continue ;;
				*) continue ;;
			esac
		fi

		if [ "$fps" = "Custom..." ]; then
			fps=$(gum input --placeholder "15" --prompt "Custom FPS: " --width 20)
			local custom_exit=$?

			# Check for cancel
			if [ $custom_exit -ne 0 ]; then
				continue
			fi

			# Trim whitespace
			fps=$(echo "$fps" | xargs)

			# Apply default if empty
			if [ -z "$fps" ]; then
				fps="15"
			fi
		fi

		if validate_numeric_param "$fps" "fps" 1 60 2>/dev/null; then
			# Warn about high FPS causing large files
			if [ "$fps" -gt 15 ]; then
				echo ""
				gum style --foreground $COLOR_ERROR --bold "⚠️  High FPS Warning"
				gum style --foreground $COLOR_HINT "FPS of $fps will create large files (many frames)."
				gum style --foreground $COLOR_HINT "Recommended: 10-15 FPS for reasonable file sizes."
				echo ""
				if ! gum confirm "Continue with $fps FPS?"; then
					continue  # Go back to FPS selection
				fi
			fi

			tui_success "FPS: $fps"
			sleep 0.5
			STEP_ACTION="next"
			return
		fi
		tui_error "FPS must be 1-60"
		sleep 1
	done
}

# Step 8: Colors
step_8_colors() {
	local total_steps=10

	while true; do
		tui_clear_and_header
		tui_progress 8 $total_steps
		tui_show_step "Select color depth" "Fewer colors = smaller file. 64-128 often looks great!"
		echo ""

		num_colors=$(gum choose --height 6 --cursor "➤ " --cursor.foreground $COLOR_SELECTION --selected.foreground $COLOR_SELECTION "64" "128" "256" "Custom...")
		local gum_exit=$?

		# Check for cancel (escape key)
		if [ $gum_exit -ne 0 ] || [ -z "$num_colors" ]; then
			local choice=$(gum choose "⬅️  Go back" "🔙 Exit" "🔁 Try again" --height 4 --header "What would you like to do?")
			case "$choice" in
				"⬅️  Go back") STEP_ACTION="back"; return ;;
				"🔙 Exit")
					if gum confirm "Are you sure you want to exit?"; then
						STEP_ACTION="exit"
						return
					fi
					continue ;;
				"🔁 Try again") continue ;;
				*) continue ;;
			esac
		fi

		if [ "$num_colors" = "Custom..." ]; then
			num_colors=$(gum input --placeholder "128" --prompt "Custom colors (2-256): " --width 20)
			local custom_exit=$?

			# Check for cancel
			if [ $custom_exit -ne 0 ]; then
				continue
			fi

			# Trim whitespace
			num_colors=$(echo "$num_colors" | xargs)

			# Apply default if empty
			if [ -z "$num_colors" ]; then
				num_colors="128"
			fi
		fi

		if validate_numeric_param "$num_colors" "colors" 2 256 2>/dev/null; then
			tui_success "Colors: $num_colors"
			sleep 0.5
			STEP_ACTION="next"
			return
		fi
		tui_error "Colors must be 2-256"
		sleep 1
	done
}

# Step 9: Remove black bars
step_9_remove_black_bars() {
	local total_steps=10

	while true; do
		tui_clear_and_header
		tui_progress 9 $total_steps
		tui_show_step "Remove black bars?" "Automatically detect and crop letterbox bars"
		echo ""

		if gum confirm --default=false "Remove black bars?"; then
			remove_black_bars="yes"
			tui_success "Will remove black bars"
		else
			local confirm_exit=$?

			# Check for cancel (escape key) - exit code 130, not 1 which means "No"
			if [ $confirm_exit -gt 1 ]; then
				local choice=$(gum choose "⬅️  Go back" "🔙 Exit" "🔁 Try again" --height 4 --header "What would you like to do?")
				case "$choice" in
					"⬅️  Go back") STEP_ACTION="back"; return ;;
					"🔙 Exit")
						if gum confirm "Are you sure you want to exit?"; then
							STEP_ACTION="exit"
							return
						fi
						continue ;;
					"🔁 Try again") continue ;;
					*) continue ;;
				esac
			fi

			remove_black_bars="no"
			tui_success "Keep original aspect ratio"
		fi

		sleep 0.5
		STEP_ACTION="next"
		return
	done
}

# Step 10: Square aspect
step_10_square_aspect() {
	local total_steps=10

	while true; do
		tui_clear_and_header
		tui_progress 10 $total_steps
		tui_show_step "Make it square?" "Crop to square aspect ratio (good for social media)"
		echo ""

		if gum confirm --default=false "Make square?"; then
			square_aspect="yes"
			tui_success "Will make square"
		else
			local confirm_exit=$?

			# Check for cancel (escape key) - exit code 130, not 1 which means "No"
			if [ $confirm_exit -gt 1 ]; then
				local choice=$(gum choose "⬅️  Go back" "🔙 Exit" "🔁 Try again" --height 4 --header "What would you like to do?")
				case "$choice" in
					"⬅️  Go back") STEP_ACTION="back"; return ;;
					"🔙 Exit")
						if gum confirm "Are you sure you want to exit?"; then
							STEP_ACTION="exit"
							return
						fi
						continue ;;
					"🔁 Try again") continue ;;
					*) continue ;;
				esac
			fi

			square_aspect="no"
			tui_success "Keep original proportions"
		fi

		sleep 0.5
		STEP_ACTION="next"
		return
	done
}

makegif_tui() {
	local total_steps=10

	# Declare all variables that will be shared across steps
	local source_video start_time duration output_gif quality
	local width fps num_colors remove_black_bars square_aspect
	local validation_result validation_exit vid_duration duration_sec start_sec

	# Current step counter
	local current_step=1
	STEP_ACTION=""

	# Main navigation loop
	while true; do
		STEP_ACTION=""

		case $current_step in
			1)
				step_1_select_video
				;;
			2)
				step_2_start_time
				;;
			3)
				step_3_duration
				;;
			4)
				step_4_output_filename
				;;
			5)
				step_5_quality
				;;
			6)
				step_6_width
				;;
			7)
				step_7_fps
				;;
			8)
				step_8_colors
				;;
			9)
				step_9_remove_black_bars
				;;
			10)
				step_10_square_aspect
				;;
			11)
				# All steps complete - show summary and create GIF
				tui_clear_and_header

				gum style \
					--foreground $COLOR_HEADER --border-foreground $COLOR_HEADER --border rounded \
					--align left --width 55 --margin "0 2" --padding "1 2" \
					"Configuration Summary" \
					"" \
					"Source:   $(basename "$source_video")" \
					"Start:    $start_time" \
					"Duration: $duration" \
					"Output:   $output_gif" \
					"" \
					"Quality:  $quality" \
					"Width:    ${width}px" \
					"FPS:      $fps" \
					"Colors:   $num_colors" \
					"Crop:     $remove_black_bars" \
					"Square:   $square_aspect"

				echo ""
				if ! gum confirm "Proceed with GIF creation?"; then
					# Go back to step 10 to allow editing
					current_step=10
					continue
				fi

				echo ""
				create_gif "$source_video" "$start_time" "$duration" "$output_gif" "$quality" "$width" "$fps" "$num_colors" "$remove_black_bars" "$square_aspect"
				return 0
				;;
			*)
				# Should never happen, but safeguard
				tui_error "Invalid step: $current_step"
				return 1
				;;
		esac

		# Process navigation result
		case "$STEP_ACTION" in
			"next")
				current_step=$((current_step + 1))
				;;
			"back")
				if [ $current_step -gt 1 ]; then
					current_step=$((current_step - 1))
				fi
				;;
			"exit")
				tui_error "Cancelled"
				return 0
				;;
			*)
				# Unexpected result
				tui_error "Navigation error"
				return 1
				;;
		esac
	done
}

# Main entry point for makegif tool
# Supports three modes:
#   - TUI mode (no arguments + gum available): Beautiful interactive interface
#   - Standard interactive mode (no arguments, no gum): Text prompts
#   - Argument mode (5+ arguments): Accepts parameters as command-line arguments
# Usage (argument mode):
#   makegif <source_video> <start_time> <duration> <output_gif> [quality] [width] [fps] [num_colors] [remove_black_bars] [square_aspect]
# Returns:
#   0 on success
#   1 on failure (missing dependencies, invalid arguments, or GIF creation error)
makegif() {

	# Check for required dependencies
	if ! check_dependencies; then
		return 1
	fi

	if [ $# -eq 0 ]; then
		# Try TUI mode first
		if check_and_install_gum; then
			makegif_tui
			return $?
		fi

		# Fall back to standard Interactive Mode
		echo "Enter the source video path:"
		read -r source_video

		echo "Enter the start time (examples: 10, 1:30, 01:30:45)"
		echo "  This is where in the video your GIF will start."
		read -r start_time

		echo "Enter the duration (examples: 5, 0:10, 00:00:05)"
		echo "  This is how long your GIF will be."
		echo "  Tip: Keep under 10 seconds for reasonable file sizes."
		read -r duration

		echo "Enter the output GIF file name (must end with .gif):"
		read -r output_gif

		echo "Enter the quality (high/low, default: low). Press Enter to skip:"
		read -r quality
		quality=${quality:-low}

		echo "Enter the width in pixels (default: 640, range: 32-7680)"
		echo "  Smaller = smaller file size. 480 is good for mobile."
		echo "  Press Enter to use default:"
		read -r width
		width=${width:-640}

		echo "Enter FPS (default: 10, range: 1-60)"
		echo "  Higher FPS = smoother animation but larger file."
		echo "  10-15 is usually good enough. Press Enter to use default:"
		read -r fps
		fps=${fps:-10}

		echo "Enter number of colors (default: 256, range: 2-256)"
		echo "  Fewer colors = smaller file. 64-128 often looks fine."
		echo "  Press Enter to use default:"
		read -r num_colors
		num_colors=${num_colors:-256}

		echo "Remove black bars? (yes/no, default: no). Press Enter to skip:"
		read -r remove_black_bars
		remove_black_bars=${remove_black_bars:-no}

		echo "Make aspect ratio square? (yes/no, default: no). Press Enter to skip:"
		read -r square_aspect
		square_aspect=${square_aspect:-no}

		# Preview configuration
		echo ""
		echo "=== Configuration Summary ==="
		echo "Source: $source_video"
		echo "Start: $start_time, Duration: $duration"
		echo "Output: $output_gif"
		echo "Quality: $quality | Width: ${width}px | FPS: $fps | Colors: $num_colors"
		echo "Remove black bars: $remove_black_bars | Square aspect: $square_aspect"
		echo "=============================="
		echo ""
		read -r -p "Proceed with GIF creation? (yes/no): " confirm
		if [ "$confirm" != "yes" ]; then
			echo "Cancelled."
			return 0
		fi

		create_gif "$source_video" "$start_time" "$duration" "$output_gif" "$quality" "$width" "$fps" "$num_colors" "$remove_black_bars" "$square_aspect"
	elif [ $# -ge 5 ]; then
		# Argument Mode
		source_video=$1
		start_time=$2
		duration=$3
		output_gif=$4
		quality=${5:-low}
		width=${6:-640}
		fps=${7:-10}
		num_colors=${8:-256}
		remove_black_bars=${9:-no}
		square_aspect=${10:-no}

		create_gif "$source_video" "$start_time" "$duration" "$output_gif" "$quality" "$width" "$fps" "$num_colors" "$remove_black_bars" "$square_aspect"
	else
		# Insufficient Arguments
		echo "Usage: makegif <source_video> <start_time> <duration> <output_gif> [quality] [width] [fps] [num_colors] [remove_black_bars] [square_aspect]"
		echo ""
		echo "Parameters:"
		echo "  source_video       - Path to input video file"
		echo "  start_time         - Start time (HH:MM:SS, MM:SS, or seconds)"
		echo "  duration           - GIF duration (HH:MM:SS, MM:SS, or seconds)"
		echo "  output_gif         - Output filename (must end in .gif)"
		echo "  quality            - 'high' or 'low' (default: low)"
		echo "  width              - Width in pixels (default: 640)"
		echo "  fps                - Frames per second (default: 10)"
		echo "  num_colors         - Colors 2-256 (default: 256)"
		echo "  remove_black_bars  - 'yes' or 'no' (default: no)"
		echo "  square_aspect      - 'yes' or 'no' (default: no)"
		echo ""
		echo "Run without arguments for interactive mode."
		return 1
	fi
}

# Crop an existing GIF to square aspect ratio using FFmpeg
# Crops to the smallest dimension (width or height) with configurable positioning
# Parameters:
#   $1 - input_gif: Path to input GIF file
#   $2 - output_gif: Path to output GIF file
#   $3 - crop_side: Crop position - 'left', 'right', 'center', 'top', or 'bottom' (default: center)
# Returns:
#   0 on success
#   1 if FFmpeg is not installed or crop operation fails
# Usage:
#   squaregif "input.gif" "output.gif" [left|right|top|bottom|center]
function squaregif() {
    local input_gif=$1
    local output_gif=$2
    local crop_side=${3:-center}  # Default to center if no side is specified

    # Check if FFmpeg is installed
    if ! command -v ffmpeg &> /dev/null; then
        echo "FFmpeg is not installed. Please install FFmpeg to use this script."
        return 1
    fi

    # Get original dimensions using FFmpeg
    local dimensions=$(ffmpeg -i "$input_gif" 2>&1 | grep 'Stream #0:0' | grep -Eo '[0-9]+x[0-9]+')
    local width=$(echo "$dimensions" | cut -dx -f1)
    local height=$(echo "$dimensions" | cut -dx -f2)

    echo "Original dimensions: $width x $height"

    # Determine crop dimensions and offset
    local size
    local offset_x=0
    local offset_y=0
    if [ "$width" -lt "$height" ]; then
        size=$width
        if [[ "$crop_side" == "bottom" ]]; then
            offset_y=$(($height - $width))
        elif [[ "$crop_side" == "center" ]]; then
            offset_y=$((($height - $width) / 2))
        fi
    else
        size=$height
        if [[ "$crop_side" == "right" ]]; then
            offset_x=$(($width - $height))
        elif [[ "$crop_side" == "center" ]]; then
            offset_x=$((($width - $height) / 2))
        fi
    fi

    echo "Cropping to dimensions: $size x $size with offsets X: $offset_x Y: $offset_y"

    # Crop the GIF
    ffmpeg -i "$input_gif" -vf "crop=$size:$size:$offset_x:$offset_y" -y "$output_gif"
}

# Usage: crop_gif_square "input.gif" "output.gif" [left|right|top|bottom|center]

