#!/usr/bin/env bash
# Rebuilds everything in store/ from the real game: Steam screenshots, the trailer,
# the capsule art and the icons. Needs Godot 4.3 (GODOT=path, default "godot"),
# xvfb-run and ffmpeg; ImageMagick's convert for the .ico and .jpg icons.
#   tools/store/make_store_assets.sh            # everything
#   tools/store/make_store_assets.sh shots art  # just some of it (shots, trailer, art)
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT=${GODOT:-godot}
STEPS=${*:-shots trailer art}
RUN=(xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path . --rendering-driver opengl3)
mkdir -p store/screenshots store/trailer store/art
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

for step in $STEPS; do
	case $step in
	shots)
		rm -rf build/store/raw
		"${RUN[@]}" res://tools/store/capture.tscn -- --shots
		# the game draws at 480x270; Steam wants 1920x1080, so each pixel becomes 4x4
		for f in build/store/raw/*.png; do
			ffmpeg -loglevel error -y -i "$f" -vf scale=1920:1080:flags=neighbor "store/screenshots/$(basename "$f")"
		done
		;;
	trailer)
		rm -rf build/store/trailer && mkdir -p build/store/trailer
		"${RUN[@]}" --resolution 1920x1080 --fixed-fps 30 --write-movie build/store/trailer/frame.png \
			res://tools/store/capture.tscn -- --trailer
		ffmpeg -loglevel error -y -framerate 30 -i build/store/trailer/frame%08d.png -i build/store/trailer/frame.wav \
			-vf "scale=1920:1080:flags=neighbor,format=yuv420p" -c:v libx264 -preset slow -crf 20 -tune animation \
			-c:a aac -b:a 192k -shortest -movflags +faststart store/trailer/vault_manager_trailer.mp4
		;;
	art)
		rm -rf build/store/art
		"$GODOT" --headless --path . res://tools/store/key_art.tscn
		cp build/store/art/*.png store/art/
		cp build/store/art/icon_256.png icon.png
		convert build/store/art/icon_32.png -scale 50% /tmp/vm_icon_16.png
		convert build/store/art/icon_32.png -scale 150% /tmp/vm_icon_48.png
		convert /tmp/vm_icon_16.png build/store/art/icon_32.png /tmp/vm_icon_48.png build/store/art/icon_256.png store/art/icon.ico
		convert build/store/art/community_icon.png -quality 95 store/art/community_icon.jpg
		;;
	*)
		echo "unknown step: $step (use shots, trailer or art)" >&2
		exit 1
		;;
	esac
done
echo "Store assets are in store/"
