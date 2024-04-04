#!/bin/bash

# This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
# You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <https://www.gnu.org/licenses/>. 

# Colour formatting stuff
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script description
echo Welcome to my ffmpeg GPU accelerator thingy

# This part checks if lshw is installed or not
if command -- lshw >/dev/null 2>&1; then
    echo -e "${GREEN}lshw is installed\n${NC}"
else
    echo -e "${RED}lshw not found, please install lshw before running this script.\n${NC}"
    exit 1
fi

echo "--------------------"

# Lists out GPU in a system, ignores errors about the command running in non-sudo mode, then filters out the vendors
listGPU=$( (lshw -C video) 2>/dev/null | awk '$1=="vendor:"{$1=""; print}')

declare -i GPUType
GPUType=0

detect_intel () {
    # echo -e "${BLUE}Intel${NC} GPU detected"
    Intel=true
	GPUType+=1
}

detect_AMD () {
	# echo -e "${RED}AMD${NC} GPU detected"
	AMD=true
	GPUType+=3
}

detect_Nvidia () {
	# echo -e "${GREEN}NVIDIA${NC} GPU detected"
	Nvidia=true
	GPUType+=5
}

# Logic for checking which GPU exists in system
if (grep NVIDIA <<< $listGPU) 1>/dev/null ; then
    detect_Nvidia
fi

if (grep AMD <<< $listGPU) 1>/dev/null ; then
	detect_AMD
fi

if (grep Intel <<< $listGPU) 1>/dev/null ; then
    detect_intel
else
    echo Unknown GPU
fi

case $GPUType in
	1)
		echo -e "Only ${BLUE}Intel${NC} GPU detected, possibly integrated graphics or Intel Arc"
		;;
	3)
		echo -e "Only ${RED}AMD${NC} GPU detected, probably an AMD-only system."
		;;
	4)
		echo -e "${BLUE}Intel${NC} and ${RED}AMD${NC} detected, probably a system with an Intel processor with iGPU and AMD graphics."
		;;
	5)
		echo -e "Only ${GREEN}Nvidia${NC} GPU detected. Possibly a system with a single dedicated Nvidia graphics."
		;;
	6)
		echo -e "${BLUE}Intel${NC} and ${GREEN}Nvidia${NC} detected, possibly a hybrid system like a laptop."
		;;
	8)
		echo -e "${RED}AMD${NC} and ${GREEN}Nvidia${NC} detected, probably a system with AMD APU and Nvidia GPU."
		;;
	*)
		echo "Unknown system type"
		;;
esac

echo -e "--------------------\n"

read -p 'Please type input filename or path here: ' inputfile
read -p 'Please type output filename or path here (without extensions): ' outputfile

# Video codec choice
PS3=$'Which video codec do you want to use? (Make sure your hardware supports it!)\n'
select vidcodecchoice in h264 hevc
do
	case $vidcodecchoice in
		h264)
			printf "$vidcodecchoice selected\n"
			break
			;;
		hevc)
			printf "$vidcodecchoice selected\n"
			break
			;;
		*)
			echo $RED "Invalid option" $NC
			;;
	esac
done

# Video quality choice
read -p 'Please enter your desired video quality (CQP): ' vidqual

# This part checks whether or not $inputfile has mp3 or aac audio codec already. If it does, then it'll just copy the audio stream over to avoid re-encoding.
eval $(ffprobe -v quiet -select_streams a:0 -of flat=s=_ -show_entries stream=codec_name "$inputfile")
if [[ $streams_stream_0_codec_name == "mp3" || $streams_stream_0_codec_name == "aac" ]]; then
	audcodec="copy"
else
	read -p 'Please enter your desired audio quality (bitrate): ' audqual
	audcodec="aac -b:a $audqual"
fi

# Change resolution choice
printf "Do you want to change resolutions?\n"
read changeres

resChange () {
	if [[ $changeres == yes || $changeres == y ]]; then
		printf "\n"
		read -p "enter the width here: " vidwidth
		read -p "enter the height here: " vidheight
		vidfilterVAAPI="-vf format=nv12,hwupload,deinterlace_vaapi=rate=field:auto=1,scale_vaapi=w=$vidwidth:h=$vidheight"
		vidfilterQSV="-vf format=qsv,hwupload,deinterlace_qsv,scale_qsv=w=$vidwidth:h=$vidheight"
		vidfilterCUDA="-vf format=cuda,hwupload,yadif_cuda=deint=interlaced,scale_cuda=w=$vidwidth:h=$vidheight"
	elif [[ $changeres == no || $changeres == n ]]; then
		vidfilterVAAPI="-vf format=nv12,hwupload,deinterlace_vaapi=rate=field:auto=1"
		vidfilterQSV="-vf format=qsv,hwupload,deinterlace_qsv"
		vidfilterCUDA="-vf format=cuda,hwupload,yadif_cuda=deint=interlaced"
	else
		printf "Unknown parameter"
	fi
}

# Choose encoder type based on detected GPUs
encType () {
	case $GPUType in
		1) # Intel GPU
			hwEncode="$vidfilterQSV -c:v ${vidcodecchoice}_qsv -global_quality $vidqual"
			hwDecode="-hwaccel qsv -hwaccel_output_format qsv -c:v ${vidcodecchoice}_qsv"
			echo $vidcodecchoice
			;;
		3 | 4) # AMD GPU
			hwEncode="$vidfilterVAAPI ${vidcodecchoice}_vaapi -rc_mode CQP -qp $vidqual"
			hwDecode="-vaapi_device /dev/dri/renderD128"
			echo $vidcodecchoice
			;;
		5 | 6 | 8) # Nvidia GPU
			hwEncode="$vidfilterCUDA -c:v ${vidcodecchoice}_nvenc -cq $vidqual"
			hwDecode="-hwaccel cuda -hwaccel_output_format cuda"
			echo $vidcodecchoice
			;;
		*)
			echo "Something went wrong!"
			exit 1
			;;
	esac
}

# Final command for running ffmpeg
run_ffmpeg () {
	resChange
	encType
	ffmpeg -hide_banner $hwDecode -i "$inputfile" $hwEncode -fps_mode passthrough -c:a $audcodec "$outputfile.mp4"
}

on_error() {
    echo -e "${RED}Exit code: $?${NC}"
	# Detects if system is an Nvidia + Intel hybrid
    if [[ $GPUType == 6 || ! $? == 0 ]] ; then
		read -p "Oh no! Nvidia transcoding failed! Do you want to try again with Intel QSV? " tryIntel
		case $tryIntel in
			[Yy][Ee][Ss] | [Yy] | [Tt][Rr][Uu][Ee] | [Tt])
				# *Hopefully* overrides GPU type to Intel only so it'll only run the commands for Intel graphics
				GPUType=1
				echo ""
				run_ffmpeg || on_error "Error occured!"
				;;
			[Nn][Oo] | [Nn] | [Ff][Aa][Ll][Ss][Ee] | [Ff])
				echo "Goodbye!"
				exit 0
				;;
			*)
				echo "Invalid input: $tryIntel"
				;;
		esac
	# Detects if system is an Nvidia + AMD hybrid
	elif [[ $GPUType == 8 || ! $? == 0 ]] ; then
		read -p "Oh no! Nvidia transcoding failed! Do you want to try again with Intel QSV? " tryAMD
		case $tryAMD in
			[Yy][Ee][Ss] | [Yy] | [Tt][Rr][Uu][Ee] | [Tt])
				# Same thing as comment on line 182 but AMD Edition
				GPUType=3
				echo ""
				run_ffmpeg || on_error "Error occured!"
				;;
			[Nn][Oo] | [Nn] | [Ff][Aa][Ll][Ss][Ee] | [Ff])
				echo "Goodbye!"
				exit 0
				;;
			*)
				echo "Invalid input: $tryAMD"
				;;
		esac
	fi
}

run_ffmpeg || on_error "Error occured!"