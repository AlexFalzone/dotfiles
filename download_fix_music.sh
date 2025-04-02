#!/bin/bash
set -euo pipefail

# Global temporary directory (created at the start)
TMP_DIR=$(mktemp -d)

# Cleanup function to remove the temporary directory on exit or error
cleanup() {
    echo "Cleaning up..."
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"
}
# Ensure cleanup on error or when the script exits
trap 'echo "An error occurred. Cleaning up..."; cleanup; exit 1' ERR

# Usage function
usage() {
    echo "Usage: $0 [--verbose] <playlist_url>"
    exit 1
}

# Parse command-line arguments (verbose mode and playlist URL)
VERBOSE=0
if [[ $# -ge 1 && $1 == "--verbose" ]]; then
    VERBOSE=1
    shift
fi
if [[ $# -ne 1 ]]; then
    usage
fi
PLAYLIST_URL="$1"

# Verify that required commands are installed
for cmd in yt-dlp rsync beet find ls rm mktemp xargs; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: the required command '$cmd' is not installed."
        exit 1
    fi
done

# Global yt-dlp options (note: we removed -N to avoid nested parallelism)
YTDLP_OPTS=( --extract-audio --audio-format mp3 \
    --write-thumbnail --embed-thumbnail --embed-metadata \
    --parse-metadata 'artist:re.sub(r"\s+(?:[Ff]eat\.|[Ff][Tt]\.).*", "", value)' \
    --cookies-from-browser brave \
    --extractor-args youtubetab:skip=authcheck \
    -o "$TMP_DIR/%(artist)s/%(album)s/%(title)s.%(ext)s" )

# Function to download music using parallel processing
download_music() {
    echo "=== Starting download process ==="
    echo "Playlist URL: '$PLAYLIST_URL'"

    # Extract video URLs from the playlist and save them to a file
    local url_file="$TMP_DIR/video_urls.txt"
    yt-dlp --flat-playlist --print "https://www.youtube.com/watch?v=%(id)s" "$PLAYLIST_URL" > "$url_file"

    echo "Found video URLs:"
    cat "$url_file"

    # Download each video concurrently (4 at a time)
    if [ $VERBOSE -eq 1 ]; then
        xargs -P 4 -I {} yt-dlp "${YTDLP_OPTS[@]}" {} < "$url_file"
    else
        xargs -P 4 -I {} yt-dlp "${YTDLP_OPTS[@]}" {} < "$url_file" > /dev/null
    fi

    echo "Download process completed."
}

# Function to merge all downloaded MP3 files into one directory
merge_files() {
    echo "=== Merging downloaded MP3 files ==="
    local merged_dir="$TMP_DIR/merged"
    mkdir -p "$merged_dir"
    find "$TMP_DIR" -type f -name "*.mp3" -exec mv {} "$merged_dir" \;
    echo "All MP3 files have been moved to: $merged_dir"
}

# Function to import the merged files using beets
import_music() {
    echo "=== Starting beets import ==="
    local merged_dir="$TMP_DIR/merged"
    if [ $VERBOSE -eq 1 ]; then
        beet import --move "$merged_dir"
    else
        beet import --move "$merged_dir" --quiet > /dev/null
    fi
    local exit_code=$?
    echo "Beets import finished with exit code: $exit_code"
}

# Main function to run the whole process
main() {
    download_music
    merge_files
    import_music
    echo "=== Process completed successfully ==="
    cleanup
}

# Run the main function
main
