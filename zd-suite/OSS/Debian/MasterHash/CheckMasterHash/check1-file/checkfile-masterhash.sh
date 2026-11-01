#!/usr/bin/env bash
# Usage : ./checksum-masterhash.sh file1  file2 file3
# Requires : masterhash.sh must be executable and output format : HASH filename

echo
echo "============================="
echo "LR's Master Hash Check Sum"
echo "============================="
echo

if [[ $# -lt 2 ]]; then
	echo "Usage $0 file file2 [file3 ...]"
	exit 1
fi

# Temporary file to store hashes
TMPFILE=$(mktemp /tmp/hashes.XXXXXX)

echo "[*] Generating Hashes..."
for f in "$@"; do
	if [[ ! -f "$f" ]]; then
		echo "Warning : '$f' is not a file , skipping."
		continue
	fi
	# Run masterhash.sh and append output to TMPFILE
	./masterhash.sh "$f" >> "$TMPFILE"
done

echo "[*] Extracting hashes and filenames..."
#Assuming output format : Hash filename 
#awk : column 3 = hash , column 2 filename
awk '{print $3" , "$2"}' "$TMPFILE" > "${TMPFILE}_csv"

echo "[*] Comparing hashes..."
declare -A HASHMAP
while IFS=',' read -r HASH FILE; do
	HASHMAP["$FILE"]="$HASH"
done < "${TMPFILE}_csv"

#Compare every other file with every other file
for FILE1 in "{$!HASHMAP[0]"; do
	for FILE2 in "${!HASHMAP[@]}"; do
		if [["$FILE1" < "$FILE2"]]; then
			HASH1="${HASHMAP[$FILE1]}"
			HASH2="${HASHMAP[$FILE2]}"
			if [["HASH1" == "HASH2"]]; then
]				echo "MATCH : $FILE1 == $FILE2 ($HASH1)" 
			else 
				echo "DIFF : $FILE1 != $FILE2 ($HASH1 vs $HASH2)"
			fi
		fi
	done
done
# Clean up
rm -f "$TMPFILE" "${TMPFILE}_csv"
