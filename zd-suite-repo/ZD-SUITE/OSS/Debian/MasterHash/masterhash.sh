#!/usr/bin/env bash

#Usage : ./master_hash.sh /path/ report_id

set -euo pipefail
echo 
echo "==================================================="
echo "LR's Master Hash (TailsOS - Debian Based Optimized)"
echo "==================================================="
echo
INPUT="${1:-}"
ID="${2:-}"
if [[ -z "$INPUT" ]]; then
	echo "ERROR : No Folder or File Specified."
	echo "Usage : $0 /path/ id"
	exit 1
fi

if [[ ! -e "$INPUT" ]] ; then 
	echo "ERROR : '$INPUT' does not exist."
	exit 1
fi 

REPORT_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="hash_report_${ID}_${REPORT_TIMESTAMP}.csv"

echo "Timestamp , Path , SHA256 , Size (bytes)" > "$REPORT_FILE"
echo "Processing : $INPUT"
echo "Creating report : $REPORT_FILE"
echo 
get_file_info() {
	local file="$1"
	local size timestamp
	size=$(stat -c%s "$file")
	timestamp=$(stat -c%y "$file")
	echo "$size|$timestamp"
}
process_file() {
	local file="$1"
	local hash size timestamp
	
	hash=$(sha256sum "$file" | awk '{print $1}')
	size=$(stat -c%s "$file")
	timestamp=$(stat -c%y "$file")
	
	echo "\"$timestamp\",\"$file\",\"$hash\",\"$size\"" >> "$REPORT_FILE"
}
if [[ -f "$INPUT" ]];then
	process_file "$INPUT"
elif [[ -d "$INPUT" ]]; then 
	while IFS= read -r -d '' file ; do
		process_file "$file"
	done < <(find "$INPUT" -type f -print0 | sort -z)
else 
	echo "ERROR : Not a regular File or Directory."
	exit 1
fi
echo
echo "Individual Hashing Complete."

#Generate master hash from the report
MASTER_HASH=$(sha256sum "$REPORT_FILE" | awk '{print $1}')

echo "-----------------------------------------------------------"
echo "MASTER HASH COMPLETE :"
echo "$MASTER_HASH"
echo "----------------------------------------------------------"

echo "Master Hash : $MASTER_HASH" >> "$REPORT_FILE"
echo
echo "Report Saved As : $REPORT_FILE"
echo "Done."




