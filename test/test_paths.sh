#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$root/RSBypass/RUN_PATCH_RS.command"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# External library holds the game and appid 221680. The default folder does not.
mkdir -p "$tmp/default/steamapps"
mkdir -p "$tmp/Games/SteamLibrary/steamapps/common/Rocksmith2014/Rocksmith2014.app/Contents/MacOS"
touch "$tmp/Games/SteamLibrary/steamapps/common/Rocksmith2014/Rocksmith2014.app/Contents/MacOS/Rocksmith2014"
touch "$tmp/Games/SteamLibrary/steamapps/appmanifest_221680.acf"
cat >"$tmp/libraryfolders.vdf" <<EOF
"libraryfolders"
{
	"0"
	{
		"path"		"$tmp/default"
		"apps"
		{
			"228980"		"0"
		}
	}
	"1"
	{
		"path"		"$tmp/Games/SteamLibrary"
		"apps"
		{
			"221680"		"42"
		}
	}
}
EOF

got=$(rs_pick_game "$tmp/libraryfolders.vdf" "$tmp/default")
want="$tmp/Games/SteamLibrary/steamapps/common/Rocksmith2014/Rocksmith2014.app/Contents/MacOS/Rocksmith2014"
[ "$got" = "$want" ]

# Both libraries have the game. The one with the appmanifest wins.
mkdir -p "$tmp/default/steamapps/common/Rocksmith2014/Rocksmith2014.app/Contents/MacOS"
touch "$tmp/default/steamapps/common/Rocksmith2014/Rocksmith2014.app/Contents/MacOS/Rocksmith2014"
got=$(rs_pick_game "$tmp/libraryfolders.vdf" "$tmp/default")
[ "$got" = "$want" ]

# Spaces in the library path, old vdf shape (no "path" key).
mkdir -p "$tmp/My Games/Steam/steamapps/common/Rocksmith2014/Rocksmith2014.app/Contents/MacOS"
touch "$tmp/My Games/Steam/steamapps/common/Rocksmith2014/Rocksmith2014.app/Contents/MacOS/Rocksmith2014"
cat >"$tmp/old.vdf" <<EOF
"LibraryFolders"
{
	"TimeNextStatsReport"		"1"
	"1"		"$tmp/My Games/Steam"
}
EOF
got=$(rs_pick_game "$tmp/old.vdf" "$tmp/empty-default")
want="$tmp/My Games/Steam/steamapps/common/Rocksmith2014/Rocksmith2014.app/Contents/MacOS/Rocksmith2014"
[ "$got" = "$want" ]

# A dylib beside the script wins over a legacy Sonoma/ folder.
mkdir -p "$tmp/kit/Sonoma"
echo new >"$tmp/kit/libRSBypass.dylib"
echo old >"$tmp/kit/Sonoma/libRSBypass.dylib"
got=$(rs_find_dylib "$tmp/kit")
[ "$got" = "$tmp/kit/libRSBypass.dylib" ]

mkdir -p "$tmp/repo/RSBypass"
echo tool >"$tmp/repo/insert_dylib"
got=$(rs_find_insert "$tmp/repo/RSBypass")
[ "$got" = "$tmp/repo/insert_dylib" ]

rs_has_x86_64 "$root/insert_dylib"

hash_a=$(rs_hash "/tmp/same")
hash_b=$(rs_hash "/tmp/same")
hash_c=$(rs_hash "/tmp/other")
[ "$hash_a" = "$hash_b" ]
[ "$hash_a" != "$hash_c" ]

echo "path tests ok"
