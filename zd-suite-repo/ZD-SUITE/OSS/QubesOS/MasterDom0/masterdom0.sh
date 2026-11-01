#!/usr/bin/bash

echo -e "==================================="
echo -e "          LR's MasterDom0"
echo -e "===================================\n"

echo -e "[~] Checking FileSystem Integrity...\n"
echo -e "===================================="

# Functions Declaration
process_arrays(){
	local title="$1"
	local localv2="$2"
	
	declare -n localarray="$localv2"

	echo -e "$title \n"
	
	
	for item in "${localarray[@]}"; do
		echo "$item"
		
	done
	
	echo -e "\n===================================="		
}

# sudo rpm -Va
# mapfile -t FS < <(sudo rpm -Va | tee /dev/stderr)
FS=("S.5...T. /usr/bin/sudo" "..M...... /usr/bin/ls" "missing /usr/lib/libfoo.so")

declare -a S=() M=() H5=() D=() U=() G=() T=() P=() m=() c=() 

for line in "${FS[@]}"; do
	flags=$(awk '{print $1}' <<< "$line")
	path=$(awk '{print $2}' <<< "$line")
	
	case "$flags" in 
		*S*) S+=("$path") ;;&
		*M*) M+=("$path")  ;;&
		*5*) H5+=("$path") ;;&
		*D*) D+=("$path")  ;;&
		*U*) U+=("$path") ;;&
		*G*) G+=("$path") ;;&
		*T*) T+=("$path")  ;;&
		*P*) P+=("$path")  ;;&
		missing) m+=("$path")  ;;&
		*c*) c+=("$path")  ;;& 
	esac
done

process_arrays "Modified Files" M 
process_arrays "Size Mismatches" S
process_arrays "Missing Files" m 
		
	


