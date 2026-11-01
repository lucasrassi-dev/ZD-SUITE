#!/usr/bin/env bash
# masterhash-check.sh
# Compares 2 CSV Reports created by masterhash.sh , line-by-line
# Compares only column 3 (hash) , but shows column 2 (paths) for context
# Outputs :
#	1) Colorized human-readable Match & Diff to Terminal
#	2) Timestamped CSV report saved to current directory 

# Color Codes
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m]"
RESET="\e[0m"

# Validate Input
if [[ $# -ne 2 ]]; then
	echo -e "${RED}Usage: $0 <file1.csv> <file2.csv> ${RESET}"
	exit 1
fi

file1="$1"
file2="$2"

if [[ ! -f "$file1" ]]; then
	echo -e "${RED}Error: File not found -> $file1${RESET}"
	exit 1
fi

if [[ ! -f "$file2" ]]; then
	echo -e "${RED}Error: File not found -> $file1${RESET}" 
        exit 1
fi

echo -e "${CYAN}===========LR's MASTER HASH COMPARISON============${RESET}"
echo -e "File 1: ${YELLOW}$file1${RESET}"
echo -e "File 2: ${YELLOW}$file2${RESET}"
echo 

timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
output_file="masterhash-check_report_${timestamp}"
echo "line,status,path_file1,path_file2,hash_file1,hash_file2" > "$output_file"

line_number=0

while IFS=, read -r _ path1 hash1; do
	line_number=$((line_number + 1))
	
	#Read same line from file2
	file2_line=$(sed -n "${line_number}p" "$file2")
	IFS=, read -r _ path2 hash2 <<< "$file2_line"

# If File 2 has fewer lines 
	if [[ -z "$file2_line" ]]; then
		echo -e "${RED}Line $line_number: Missing in File2 ${RESET}"
		echo -e "$line_number,missing,$path1,,${hash1}," >> "$output_file"
		continue
	fi

# COMPARE HASHES ONLY
	if [[ "$hash1" == "$hash2" ]]; then
		echo -e "${GREEN}Line $line_number : HASHES MATCH ${RESET}"
		echo  "$line_number,MATCH,$path1,$path2,$hash1,$hash2" >> "$output_file"
	else 
		echo -e "${RED}Line $line_number : HASH DIFF ${RESET}"
		echo -e " 	${YELLOW}Path1:${RESET} $path1"
		echo -e "       ${YELLOW}Path2:${RESET} $path2"
		echo -e "       ${CYAN}Hash1:${RESET} $hash1"
		echo -e "       ${CYAN}Hash2:${RESET} $hash2"
		echo "$line_number,DIFF,$path1,$path2,$hash1,$hash2" >> "$output_file"
	fi
done < "$file1"

echo
echo -e " ${CYAN}Report saved as:${RESET} $output_file"
