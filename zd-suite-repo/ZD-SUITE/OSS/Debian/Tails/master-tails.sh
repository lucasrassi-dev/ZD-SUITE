#!/usr/bin/bash

mkdir ~resources/ &>/dev/null
mkdir ~resources/~keychain &>/dev/null
cd ~resources 

IMG="tails.img"

if [[ $# -lt 1 ]]; then 

	wget -q --show-progress https://tails.net/tails-signing.key -O "~keychain/tails-signing.key"

	gpg --import < "~keychain/tails-signing.key"
	gpg --keyring=/usr/share/keyrings/debian-keyring.gpg --export chris@chris-lamb.co.uk | gpg --import
	gpg --keyid-format 0xlong --check-sigs A490D0F4D311A4153E2BB7CADBB802B258ACD84F
	gpg --lsign-key A490D0F4D311A4153E2BB7CADBB802B258ACD84F

	wget -q --show-progress https://download.tails.net/tails/stable/tails-amd64-7.4/tails-amd64-7.4.img -O $IMG 

	wget -q --show-progress https://tails.net/torrents/files/tails-amd64-7.4.img.sig 

	TZ=UTC gpg --no-options --keyid-format long --verify tails-amd64-7.4.img.sig tails-amd64-7.4.img 
fi

if [[ -n "$1" ]]; then
	sudo dd if=$IMG of=$1 bs=16M oflag=direct status=progress
fi

