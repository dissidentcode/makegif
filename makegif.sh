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

	# Validate file type using ffprobe
	if ! ffprobe -v error -i "$file" -t 0.1 -f null - >/dev/null 2>&1; then
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
		local square_size="min(iw,ih)"
		filters="$filters,scale=${square_size}:${square_size}"
	else
		filters="$filters,scale=${width}:-1"
	fi

	# Create unique temp files
	local temp_gif=$(mktemp "${TMPDIR:-/tmp}/makegif_XXXXXX.gif")
	local palette=$(mktemp "${TMPDIR:-/tmp}/makegif_palette_XXXXXX.png")
	TEMP_FILES+=("$temp_gif" "$palette")

	echo "Creating GIF (this may take a few minutes)..."
	echo "  Source: $source_video"
	echo "  Segment: $start_time + $duration"
	echo "  Dimensions: ${width}px width"
	echo "  Quality: $quality"
	echo "  Filters: $filters"
	echo ""

	local ffmpeg_output
	if [ "$quality" = "high" ]; then
		echo "Step 1/2: Generating optimized color palette..."
		ffmpeg_output=$(ffmpeg -v warning -stats -ss "$start_time" -t "$duration" -i "$source_video" \
			-filter_complex "$filters,palettegen=stats_mode=full" -y "$palette" 2>&1)
		local palette_exit=$?

		if [ $palette_exit -ne 0 ]; then
			echo "Error: Palette generation failed." >&2
			echo "FFmpeg output:" >&2
			echo "$ffmpeg_output" >&2
			return 1
		fi

		echo "Step 2/2: Creating GIF with palette..."
		ffmpeg_output=$(ffmpeg -v warning -stats -ss "$start_time" -t "$duration" -i "$source_video" -i "$palette" \
			-filter_complex "$filters,paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
			-an "$temp_gif" 2>&1)
		local gif_exit=$?

		if [ $gif_exit -ne 0 ]; then
			echo "Error: GIF creation failed." >&2
			echo "FFmpeg output:" >&2
			echo "$ffmpeg_output" >&2
			return 1
		fi
	else
		echo "Creating GIF..."
		ffmpeg_output=$(ffmpeg -v warning -stats -ss "$start_time" -t "$duration" -i "$source_video" \
			-vf "$filters" -an "$temp_gif" 2>&1)
		local gif_exit=$?

		if [ $gif_exit -ne 0 ]; then
			echo "Error: GIF creation failed." >&2
			echo "FFmpeg output:" >&2
			echo "$ffmpeg_output" >&2
			return 1
		fi
	fi

	# Verify temp GIF was created
	if [ ! -f "$temp_gif" ]; then
		echo "Error: Temporary GIF was not created." >&2
		return 1
	fi

	local temp_size=$(du -h "$temp_gif" | cut -f1)
	echo ""
	echo "Optimizing GIF (this may take a minute)..."
	echo "  Unoptimized size: $temp_size"
	echo "  Target colors: $num_colors"

	if ! gifsicle -O3 --colors "$num_colors" "$temp_gif" -o "$output_gif" 2>&1; then
		echo "Error: GIF optimization failed." >&2
		echo "Temporary GIF preserved at: $temp_gif" >&2
		return 1
	fi

	if [ ! -f "$output_gif" ]; then
		echo "Error: Output GIF was not created." >&2
		return 1
	fi

	rm "$temp_gif"

	local final_size=$(du -h "$output_gif" | cut -f1)
	echo ""
	echo "Success! GIF created: $output_gif"
	echo "  Final size: $final_size (was $temp_size)"
}

# Main entry point for makegif tool
# Supports two modes:
#   - Interactive mode (no arguments): Prompts user for all parameters
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
		# Interactive Mode
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

