#!/usr/bin/bash

echo -e "\n====================================================="
echo -e "----------- LR's MasterQubes OPSEC SETUP ------------"
echo -e "=====================================================\n\n"

mkdir ~resources/ &>/dev/null
mkdir ~resources/QMSK &>/dev/null
mkdir ~resources/ISO &> /dev/null
mkdir ~resources/RSK &> /dev/null

# QubesOS <Master Signing Key ; Release Signing Key ; ISO ; ISO .DIGESTS ; ISO Detached PGP>
#	~Variable Declarations
PWDV=$(pwd)
QMSK1="~resources/QMSK/qubes-master-signing-key.asc"
QMSK2="~resources/QMSK/qmsk2.asc"
QMSK3="~resources/QMSK/qmsk3.asc"
RSK="~resources/RSK/rsk.asc"
ISO="~resources/ISO/Qubes-R4.3.0-x86_64.iso"
ISOD="~resources/ISO/Qubes-R4.3.0-x86_64.iso.DIGESTS"
ISOPGP="~resources/ISO/Qubes-R4.3.0-x86_64.iso.asc"

#	~Functions Declaration
getgpg() {
	if [[ $1 == "fpr" ]]; then
		gpg2 --show-keys --with-colons --fingerprint $2 | awk -F: '/^fpr/ {print $10}'
	fi
	if [[ $1 == "id" ]]; then
		gpg2 --status-fd 1 --import $2 2>/dev/null | awk '/^\[GNUPG:\] IMPORT_OK / {print $4;
		exit}'
	fi
}
authgpg() {
	found=0
	AUTHSIG=(
		"$QMSK_FPR"
		"$RSK_FPR"
	)
	if [[ $1 == "signature" ]]; then
		while IFS=: read -r type status _ _ _ _ _ _ _ _ _ _ signer _ _ _; do
			if [[ "$type" == "sig" && "$status" == *"!"* ]]; then
    				for fp in "${AUTHSIG[@]}"; do
      					[[ "$signer" == "$fp" ]] && ((found++))
    				done
  			fi
		done < <(gpg2 --status-fd 1 --with-colons --check-signatures $2)
	fi

	if [[ $1 == "verify" ]]; then
		while IFS= read -r line; do
			case "$line" in
				"[GNUPG:] VALIDSIG "*)
					signer=$(awk '{print $3}' <<< "$line")
			
    				for fp in "${AUTHSIG[@]}"; do
      					[[ "$signer" == "$fp" ]] && ((found++))
    				done
  				;;
  			esac
		done < <(gpg2  --verify --status-fd 1  $2 $3)	
	fi

	echo $found
}
airgap() {
	if [[ $1 == "ON" ]]; then 
		sudo iptables -P INPUT DROP
		sudo iptables -P OUTPUT DROP
		sudo iptables -P FORWARD DROP

		for iface in $(ip -o link show | awk -F': ' '{print $2}'); do
    			sudo ip link set "$iface" down || true
		done	
	fi
	if [[ $1 == "OFF" ]]; then
		sudo iptables -P INPUT ACCEPT
		sudo iptables -P OUTPUT ACCEPT
		sudo iptables -P FORWARD ACCEPT
		sudo nft flush ruleset
		sudo systemctl restart NetworkManager
	fi
}

#	~Repository Downloads
echo -e  "\n====================================================="
echo -e  " Repositories Downloads\n"

sudo apt install gnupg2 -y &> /dev/null
wget -q -L --show-progress "https://keys.qubes-os.org/keys/qubes-master-signing-key.asc" -O $QMSK1
wget -q -L --show-progress "https://13754266818915104063.googlegroups.com/attach/790c4f769230a491/qubes-master-signing-key.asc?part=0.0.1&amp;vt=ANaJVrG-GZZljd-roIXp1FqUvIJhtvXzdRvajn-gituOFrv_BcnBT0jSYPLpbmcfyr62T8mCNLo5uHmqlTqwyha4keVL1RSv1S6yIX-lXezZ5d6MHNDfTGI" -O $QMSK2
wget -q -L --show-progress "https://raw.githubusercontent.com/QubesOS/qubes-secpack/refs/heads/main/keys/master-key/qubes-master-key.asc" -O $QMSK3
wget -q -L --show-progress "https://keys.qubes-os.org/keys/qubes-release-4.3-signing-key.asc" -O $RSK
wget -q -L --show-progress "https://mirrors.edge.kernel.org/qubes/iso/Qubes-R4.3.0-x86_64.iso.DIGESTS" -O $ISOD
wget -q -L --show-progress "https://mirrors.edge.kernel.org/qubes/iso/Qubes-R4.3.0-x86_64.iso.asc" -O $ISOPGP
wget -q -L --show-progress "https://mirrors.edge.kernel.org/qubes/iso/Qubes-R4.3.0-x86_64.iso" -O $ISO

airgap ON

# QubesOS Master Signing Key <QMSK>
#~ 	QMSK Cross Validation
FPR1=$(getgpg fpr $QMSK1)
FPR2=$(getgpg fpr $QMSK2)
FPR3=$(getgpg fpr $QMSK3)

echo -e "\n\n====================================================="
echo -e " QubesOS PGP Master Signing Key Cross Validation\n"

if [[ "$FPR1" == "$FPR2" && "$FPR2" == "$FPR3" ]]; then
	echo -e "$FPR1"
	echo -e "\n====================================================="
	echo -e "[+] QMSK Cross Validated"
	echo -e "=====================================================\n\n"
else
	echo -e "\n====================================================="
	echo -e "[-] QMSK Cross Validation Failed"
	echo -e "=====================================================\n\n"
	exit 1
fi

#~	Importing QMSK

QMSK_FPR=$(getgpg id $QMSK1) 
printf "%s\n" fpr trust 5 y q \
| gpg2 --batch --yes --no-tty --command-fd 0 --edit-key $QMSK_FPR
gpg2 -k $QMSK_FPR


# QubesOS Release Signing Key <RSK>
#~ 	Importing RSK ~ RSK Cross Validation on QMSK

RSK_FPR=$(getgpg id $RSK)

echo -e "\n\n====================================================="
echo -e " RSK -> QMSK Signature Validation \n"

AUTH=$(authgpg signature $RSK_FPR)

if [[ $AUTH > 0 ]]; then
	echo -e $RSK_FPR
  	echo -e "\n====================================================="
	echo -e "[+] RSK Validated on QMSK "
	echo -e "=====================================================\n\n"
else
	echo -e "\n====================================================="
  	echo -e "[-] RSK Failed to Validate on QMSK"
	echo -e "=====================================================\n\n"
  	exit 1
fi
gpg2 -k $RSK_FPR

# QubesOS ISO 
#	~Hash Checksum Validation .ISO hashes on DIGESTS
cd "$(dirname "$ISO")"
HCS=()
HCS[1]="md5sum"
HCS[2]="sha1sum"
HCS[3]="sha256sum"
HCS[4]="sha512sum"

echo -e "\n\n====================================================="
echo -e " ISO Hash Validation\n\n"

for ((i=1;i<=4;i++)); do
	HASHCS="$(${HCS[$i]} -c $(basename "$ISOD"))"
	echo -e $HASHCS
	if $(echo -e $HASHCS | grep -q "OK") ; then
        	echo -e "\n================================="
        	echo -e "[+] "${HCS[$i]}" Valid Hashes"
        	echo -e "=================================\n"
	else
        	echo -e "\n================================="
        	echo -e "[-] "${HCS[$i]}" Validation Failed"
        	echo -e "=================================\n"
        	exit 1
        fi

done

cd $PWDV

# QubesOS .DIGESTS
#~ 	PGP Cross Validation on .DIGESTS

echo -e "\n\n====================================================="
echo -e " ISO Files Validation\n\n"

AUTH=$(authgpg verify $ISOD)
if [[ $AUTH > 0 ]]; then
  	echo -e "\n====================================================="
	echo -e "[+] ISO.DIGESTS Validated on RSK "
	echo -e "=====================================================\n\n"
else
	echo -e "\n====================================================="
  	echo -e "[-] ISO.DIGESTS Failed to Validate on RSK"
	echo -e "=====================================================\n\n"
  	exit 1
fi

AUTH=$(authgpg verify $ISOPGP $ISO)
if [[ $AUTH > 0 ]]; then
  	echo -e "\n====================================================="
	echo -e "[+] ISO & Detached PGP Validated on RSK"
	echo -e "=====================================================\n\n"
else
	echo -e "\n====================================================="
  	echo -e "[-] ISO & Detached PGP Failed to Validate on RSK"
	echo -e "=====================================================\n\n"
  	exit 1
fi

if [[ -n "$1" ]]; then
	echo -e "\n====================================================="
	echo -e " ISO IMAGE -> DD MEDIA WRITE on $1 \n"
	
	sudo dd if=$ISO of=$1 status=progress bs=1M conv=fsync
	
	echo -e "\n\n====================================================="
	echo -e "[+] ISO IMAGE Successfully Written on $1 "
	echo -e "====================================================="
	
	echo -e "\n\n====================================================="
	echo -e " DD WRITE -> ISO IMAGE Validation\n"
	
	ISOHASH=$(sha256sum $ISO | awk '{print $1}')
	DDHASH=$(sudo dd if=$1 bs=1M count=$(stat -c %s $ISO) iflag=count_bytes status=none | sha256sum | awk '{print $1}')
	
	if [[ $DDHASH == $ISOHASH ]]; then
		echo -e "\n====================================================="
		echo -e "[+] DD Hashes Validated on ISO IMAGE "
		echo -e "=====================================================\n\n"
	else
		echo -e "\n====================================================="
		echo -e "[-] DD Hashes Failed to Validate on ISO IMAGE "
		echo -e "=====================================================\n"
		exit 1
	
	fi
	
	ISOBYTES=8176568320
	DDHASH=$(sudo dd if=$1 bs=1M count=$ISOBYTES iflag=count_bytes status=none | sha256sum | awk '{print $1}')
	
	if [[ $DDHASH ==  $ISOHASH ]]; then
		echo -e "====================================================="
		echo -e "[+] DD Hashes Cross Validated on ISO IMAGE "
		echo -e "=====================================================\n\n"
	else
		echo -e "====================================================="
		echo -e "[-] DD Hashes Failed to Cross Validate on ISO IMAGE "
		echo -e "=====================================================\n\n"
		exit 1
	
	fi
	
	AUTH=$(sudo dd if=$1 bs=1M count=$(stat -c %s $ISO) iflag=count_bytes | authgpg verify $ISOPGP -)
	if [[ $AUTH > 0 ]]; then
	  	echo -e "\n====================================================="
		echo -e "[+] DD Validated on Detached PGP & RSK"
		echo -e "=====================================================\n\n"
	else
		echo -e "\n====================================================="
	  	echo -e "[-] DD Failed to Validate on Detached PGP & RSK"
		echo -e "=====================================================\n\n"
	  	exit 1
	  fi
fi	  
	  echo -e "===================================================="
	  echo -e " All Integrity Validations Were Successful "	
	  echo -e "====================================================\n\n"
