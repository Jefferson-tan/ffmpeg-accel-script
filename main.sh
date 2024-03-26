#!/bin/bash

echo Welcome to my simple ffmpeg GPU accelerator thingy

read -p 'Please type input name here: ' inputfile
read -p 'Please type output name here (without extensions): ' outputfile

PS3=$'Which video codec do you want to use?\n'
select vidcodecchoice in h264 hevc
do
	case $vidcodecchoice in
		h264)
			printf "$vidcodecchoice selected\n"
			vidcodec=${vidcodecchoice}_vaapi
			break
			;;
		hevc)
			printf "$vidcodecchoice selected\n"
			vidcodec=${vidcodecchoice}_vaapi
			break
			;;
		*)
			echo "Invalid option"
			;;
	esac
done

read -p 'Please enter your desired video quality (CQP): ' vidqual
eval $(ffprobe -v quiet -select_streams a:0 -of flat=s=_ -show_entries stream=codec_name "$inputfile")

if [[ $streams_stream_0_codec_name == "mp3" || $streams_stream_0_codec_name == "aac" ]]; then
	audcodec="copy"
else
	read -p 'Please enter your desired audio quality (bitrate): ' audqual
	audcodec="aac -b:a $audqual"
fi

printf "Do you want to change resolutions?\n"
read changeres

if [ $changeres == yes ]; then
	printf "\n"
	read -p "enter the width here: " vidwidth
	read -p 'enter the height here: ' vidheight
	vidfilter="format=nv12,hwupload,deinterlace_vaapi=rate=field:auto=1,scale_vaapi=w=$vidwidth:h=$vidheight"
elif [ $changeres == no ]; then
	vidfilter="format=nv12,hwupload,deinterlace_vaapi=rate=field:auto=1"
else
	printf "Unknown parameter"
fi

ffmpeg -vaapi_device /dev/dri/renderD128 -i "$inputfile" -vf $vidfilter -c:v $vidcodec -fps_mode passthrough -rc_mode CQP -qp $vidqual -c:a $audcodec "$outputfile.mp4"
