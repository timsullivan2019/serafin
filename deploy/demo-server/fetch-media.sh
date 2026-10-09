#!/usr/bin/env bash
set -euo pipefail

# Fetches the demo server's library: Blender open films only, every one CC BY. Each
# title's source and licence is in SOURCES.md. Needs curl, unzip, ffmpeg and yt-dlp.
# Anything already in the library is skipped, so this can be run again after a change.

MEDIA="${MEDIA_DIR:-$(pwd)/media}"
TMP="${TMP_DIR:-$(pwd)/tmp}"
SHOW="$MEDIA/Shows/Caminandes"
mkdir -p "$MEDIA/Movies" "$SHOW/Season 01" "$TMP"

download() {
	if [[ -f "$2" ]]; then
		echo "have $2"
	else
		curl -fL --retry 5 --retry-delay 5 -C - -o "$2" "$1"
	fi
}

# Downloads a YouTube video as H.264 and AAC, at most 1080p, so normalise only remuxes it.
youtube() {
	if [[ -f "$2" ]]; then
		echo "have $2"
	else
		yt-dlp --no-playlist -S 'vcodec:h264,res:1080,acodec:m4a' -f 'bv*+ba/b' \
			--merge-output-format mp4 -o "$2" "$1"
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

# movie <title> <year> <tmdb id> <youtube url>. The tmdbid tag in the folder name makes
# Jellyfin match the right film, since titles like Spring, Hero and Charge are shared
# with other films on TMDB. The download is deleted once normalised, to save disk.
movie() {
	local out="$MEDIA/Movies/$1 ($2) [tmdbid-$3]/$1 ($2).mp4"
	if [[ -f "$out" ]]; then
		echo "have $out"
		return
	fi
	local src="$TMP/tmdb-$3.mp4"
	youtube "$4" "$src"
	normalise "$src" "$out"
	rm -f "$src"
}

# episode <number> <title> <fetch command...>. The fetch command gets the download path last.
episode() {
	local out="$SHOW/Season 01/Caminandes - S01E0$1 - $2.mp4"
	local src="$TMP/caminandes$1.mp4"
	if [[ -f "$out" ]]; then
		echo "have $out"
		return
	fi
	"${@:3}" "$src"
	normalise "$src" "$out"
	rm -f "$src"
}

# frame <video> <seconds> <filter> <out>: a still from the film itself, for artwork.
frame() {
	if [[ -f "$4" ]]; then
		echo "have $4"
	else
		ffmpeg -y -hide_banner -loglevel warning -ss "$2" -i "$1" -frames:v 1 -update 1 -vf "$3" -q:v 2 "$4"
		echo "wrote $4"
	fi
}

if [[ ! -f "$MEDIA/Movies/Big Buck Bunny (2008)/Big Buck Bunny (2008).mp4" ]]; then
	download "https://mirrors.mit.edu/kodi/demo-files/BBB/bbb_sunflower_1080p_30fps_normal.mp4" "$TMP/bbb.mp4"
	normalise "$TMP/bbb.mp4" "$MEDIA/Movies/Big Buck Bunny (2008)/Big Buck Bunny (2008).mp4"
	rm -f "$TMP/bbb.mp4"
fi

if [[ ! -f "$MEDIA/Movies/Sintel (2010)/Sintel (2010).mp4" ]]; then
	download "https://download.blender.org/demo/movies/Sintel.2010.1080p.mkv" "$TMP/sintel.mkv"
	normalise "$TMP/sintel.mkv" "$MEDIA/Movies/Sintel (2010)/Sintel (2010).mp4"
	rm -f "$TMP/sintel.mkv"
fi

movie "Elephants Dream" 2006 9761 "https://www.youtube.com/watch?v=TLkA0RELQ1g"
movie "Cosmos Laundromat" 2015 358332 "https://www.youtube.com/watch?v=Y-rmzh0PI3c"
movie "Glass Half" 2015 420577 "https://www.youtube.com/watch?v=lqiN98z6Dak"
movie "Hero" 2018 615324 "https://www.youtube.com/watch?v=pKmSdY56VtY"
movie "Spring" 2019 593048 "https://www.youtube.com/watch?v=WhWc3b3KhnY"
movie "Coffee Run" 2020 717986 "https://www.youtube.com/watch?v=PVGeM40dABA"
movie "Sprite Fright" 2021 891761 "https://www.youtube.com/watch?v=_cMxraX_5RE"
movie "Charge" 2022 1062079 "https://www.youtube.com/watch?v=UXqq0ZvbOnk"
movie "Wing It!" 2023 1177628 "https://www.youtube.com/watch?v=u9lj-c29dxI"

caminandes2() {
	download "https://cdimage.debian.org/mirror/blender.org/demo/movies/caminandes_gran_dillama.mp4.zip" "$TMP/caminandes2.zip"
	unzip -o -j "$TMP/caminandes2.zip" -d "$TMP/caminandes2_unzipped"
	mv "$(find "$TMP/caminandes2_unzipped" -iname '*.mp4' | head -n 1)" "$1"
	rm -rf "$TMP/caminandes2.zip" "$TMP/caminandes2_unzipped"
}

episode 1 "Llama Drama" download "https://archive.org/download/Caminandes1LlamaDrama/01_llama_drama_1080p.mp4"
episode 2 "Gran Dillama" caminandes2
episode 3 "Llamigos" youtube "https://www.youtube.com/watch?v=L6mLFxGRFI4"

# TMDB lists the three Caminandes films as separate movies, not as a series, so the show's
# details come from these NFO files and its artwork from stills of Llamigos.
cat >"$SHOW/tvshow.nfo" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<tvshow>
  <title>Caminandes</title>
  <plot>Koro the llama wanders the far south of Patagonia, where the tastiest grass is always on the wrong side of a road, a fence or a penguin. Short animated films from the Blender Foundation.</plot>
  <year>2013</year>
  <genre>Animation</genre>
  <genre>Comedy</genre>
  <genre>Family</genre>
  <studio>Blender Foundation</studio>
  <lockdata>true</lockdata>
</tvshow>
EOF

nfo() {
	cat >"$SHOW/Season 01/Caminandes - S01E0$1 - $2.nfo" <<EOF
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<episodedetails>
  <title>$2</title>
  <season>1</season>
  <episode>$1</episode>
  <year>$3</year>
  <plot>$4</plot>
  <director>Pablo Vazquez</director>
  <lockdata>true</lockdata>
</episodedetails>
EOF
}
nfo 1 "Llama Drama" 2013 "Koro wants to cross a lonely Patagonian highway. The highway has other ideas."
nfo 2 "Gran Dillama" 2013 "The grass beyond the electric fence is greener, and Koro will try anything to reach it."
nfo 3 "Llamigos" 2016 "Winter has come to Patagonia. Koro meets Oti, a penguin with his eye on the same last berries."

LLAMIGOS="$SHOW/Season 01/Caminandes - S01E03 - Llamigos.mp4"
frame "$LLAMIGOS" 116 "crop=ih*2/3:ih:(iw-ih*2/3)/2+90:0,scale=1000:-2" "$SHOW/poster.jpg"
frame "$LLAMIGOS" 14 "scale=1920:-2" "$SHOW/backdrop.jpg"

rmdir "$TMP" 2>/dev/null || true

echo
echo "Done. Library tree:"
find "$MEDIA" -type f | sort
du -sh "$MEDIA"
df -h /
