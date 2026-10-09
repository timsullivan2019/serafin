#!/usr/bin/env bash
set -euo pipefail

MEDIA="${MEDIA_DIR:-$(pwd)/media}"
TMP="${TMP_DIR:-$(pwd)/tmp}"
mkdir -p "$MEDIA/Movies" "$MEDIA/Shows/Caminandes/Season 01" "$TMP"

download() {
	if [[ -f "$2" ]]; then
		echo "have $2"
	else
		curl -fL --retry 5 --retry-delay 5 -C - -o "$2" "$1"
	fi
}

normalise() {
	local in="$1" out="$2"
	if [[ -f "$out" ]]; then
		echo "have $out"
		return
	fi
	mkdir -p "$(dirname "$out")"
	local vcodec
	vcodec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$in")
	local vargs=(-c:v copy)
	if [[ "$vcodec" != "h264" ]]; then
		echo "video is $vcodec; re-encoding to h264 (slow)"
		vargs=(-c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p)
	fi
	ffmpeg -y -hide_banner -loglevel warning -i "$in" \
		-map 0:v:0 -map 0:a:0 -sn -dn \
		"${vargs[@]}" \
		-c:a aac -ac 2 -b:a 192k \
		-movflags +faststart \
		"$out"
	echo "wrote $out"
}

download "https://mirrors.mit.edu/kodi/demo-files/BBB/bbb_sunflower_1080p_30fps_normal.mp4" "$TMP/bbb.mp4"
normalise "$TMP/bbb.mp4" "$MEDIA/Movies/Big Buck Bunny (2008)/Big Buck Bunny (2008).mp4"

download "https://download.blender.org/demo/movies/Sintel.2010.1080p.mkv" "$TMP/sintel.mkv"
normalise "$TMP/sintel.mkv" "$MEDIA/Movies/Sintel (2010)/Sintel (2010).mp4"


download "https://cdimage.debian.org/mirror/blender.org/demo/movies/caminandes_gran_dillama.mp4.zip" "$TMP/caminandes2.zip"
if [[ ! -f "$TMP/caminandes2.mp4" ]]; then
	unzip -o -j "$TMP/caminandes2.zip" -d "$TMP/caminandes2_unzipped"
	mv "$(find "$TMP/caminandes2_unzipped" -iname '*.mp4' | head -n 1)" "$TMP/caminandes2.mp4"
fi
normalise "$TMP/caminandes2.mp4" "$MEDIA/Shows/Caminandes/Season 01/Caminandes - S01E02 - Gran Dillama.mp4"

for n in 1 3; do
	src=$(find "$TMP" -maxdepth 1 -iname "caminandes$n.*" | head -n 1 || true)
	if [[ -n "$src" ]]; then
		title=$([[ "$n" == "1" ]] && echo "Llama Drama" || echo "Llamigos")
		normalise "$src" "$MEDIA/Shows/Caminandes/Season 01/Caminandes - S01E0$n - $title.mp4"
	else
		echo "note: caminandes$n not found in $TMP; add it later and re-run"
	fi
done

echo
echo "Done. Library tree:"
find "$MEDIA" -type f | sort
