#!/bin/bash
# Script Created by DissidentCode github.carry327@passinbox.com

# Function to clean up temporary files
cleanup() {
	rm -f "$temp_gif" "$palette"
}

# Function to check dependencies
check_dependencies() {
	local missing_deps=0
	for dep in ffmpeg gifsicle; do
		if ! command -v $dep &>/dev/null; then
			echo "Error: $dep is not installed."
			missing_deps=$((missing_deps + 1))
		fi
	done
	return $missing_deps
}

# Function to get crop parameters
get_crop_params() {
	local source_video=$1
	local crop_params=$(ffmpeg -ss 00:05:00 -t 10 -i "$source_video" -vf "cropdetect" -f null - 2>&1 | grep -oE 'crop=[0-9]+:[0-9]+:[0-9]+:[0-9]+' | sort | uniq -c | sort -nr | head -n 1 | awk '{print $2}' | sed 's/crop=//')
	echo $crop_params
}

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
	#local square_aspect=${10}

	trap cleanup EXIT

	if [[ "$source_video" == "~/"* ]]; then
		source_video="$HOME/${source_video:2}"
	fi

	if [ ! -f "$source_video" ]; then
		echo "Error: Source video does not exist."
		return 1
	fi

	# Validate start_time and duration format if necessary...

	local filters="fps=$fps"
	if [ "$remove_black_bars" = "yes" ]; then
		local crop_params=$(get_crop_params "$source_video")
		if [ -n "$crop_params" ]; then
			filters="$filters,crop=$crop_params"
		else
			echo "No valid crop parameters detected."
			return 1
		fi
	fi

	if [ "$square_aspect" = "yes" ]; then
		local square_size="min(iw,ih)"
		filters="$filters,scale=${square_size}:${square_size}"
	else
		filters="$filters,scale=${width}:-1"
	fi

	local temp_gif="temp_$output_gif"
	local palette="/tmp/palette.png"

	echo "Running ffmpeg with filters: $filters"
	echo "Executing ffmpeg command: ffmpeg -ss \"$start_time\" -t \"$duration\" -i \"$source_video\" -filter_complex \"$filters,palettegen=stats_mode=full\" -y \"$palette\""

	if [ "$quality" = "high" ]; then
		ffmpeg -ss "$start_time" -t "$duration" -i "$source_video" -filter_complex "$filters,palettegen=stats_mode=full" -y "$palette" &&
			ffmpeg -ss "$start_time" -t "$duration" -i "$source_video" -i "$palette" -filter_complex "$filters,paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" -an "$temp_gif"
	else
		ffmpeg -ss "$start_time" -t "$duration" -i "$source_video" -vf "$filters" -an "$temp_gif"
	fi

	if [ $? -ne 0 ]; then
		echo "Error during GIF creation."
		return 1
	fi

	echo "Optimizing GIF for smaller file size with $num_colors colors..."
	gifsicle -O3 --colors $num_colors "$temp_gif" -o "$output_gif" &&
		rm "$temp_gif" &&
		echo "Optimized GIF created: $output_gif"
}

makegif() {

	# Check for required dependencies
	if ! check_dependencies; then
		return 1
	fi

	if [ $# -eq 0 ]; then
		# Interactive Mode
		echo "Enter the source video path:"
		read source_video

		echo "Enter the start time (hh:mm:ss):"
		read start_time

		echo "Enter the duration (hh:mm:ss):"
		read duration

		echo "Enter the output GIF file name:"
		read output_gif

		echo "Enter the quality (high/low, default: low). Press Enter to skip:"
		read quality
		quality=${quality:-low}

		echo "Enter the width (default: 640). Press Enter to skip:"
		read width
		width=${width:-640}

		echo "Enter the frames per second (FPS, default: 10). Press Enter to skip:"
		read fps
		fps=${fps:-10}

		echo "Enter the number of colors for optimization (default: 256). Press Enter to skip:"
		read num_colors
		num_colors=${num_colors:-256}

		echo "Remove black bars? (yes/no, default: no). Press Enter to skip:"
		read remove_black_bars
		remove_black_bars=${remove_black_bars:-no}

		#echo "Make aspect ratio square? (yes/no, default: no). Press Enter to #skip:"
		#read square_aspect
		square_aspect=${square_aspect:-no}

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
		echo "Usage: makegif <source_video> <start_time> <duration> <output_gif (be sure to end in '.gif')> <quality (high or low)> [width (in pixels)] [fps] [num_colors (2 - 255)] [remove_black_bars (yes or no)]"
		echo "Run the function without arguments to use interactive mode."
		return 1
	fi
}

# Function to crop a GIF to be square using FFmpeg

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
    local width=$(echo $dimensions | cut -dx -f1)
    local height=$(echo $dimensions | cut -dx -f2)

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

