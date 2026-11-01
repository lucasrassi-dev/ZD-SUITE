#!/usr/bin/env bash

echo -e "\n===========================================================\n"
echo -e "             LR's DECENTRALIZED NETWORK NODE"
echo -e "                       TOR-NETWORK"
echo -e "\n===========================================================\n"

SCRIPTROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPODIR="${SCRIPTROOT}/~resources/~repo"
TORARCHIVE="$(basename "${URL[0]}")"
TORVERSION="${TORARCHIVE%.tar.gz}"

# Firewall Reset
sudo nft flush ruleset

# Repository Downloads
mkdir -p "$REPODIR" &>/dev/null

URL=(
'https://dist.torproject.org/tor-0.4.8.21.tar.gz'
'https://dist.torproject.org/tor-0.4.8.21.tar.gz.sha256sum'
'https://dist.torproject.org/tor-0.4.8.21.tar.gz.sha256sum.asc'
)

for file in "${URL[@]}"; do
	wget -L -q --show-progress \
		-O "$REPODIR/$(basename "$file")" \
		"$file"
done

# Repository Integrity Validations
#~	SHA256 Validation
echo -e "\n================================="
echo -e " HASH SHA256 \n"

cd "$REPODIR"

#~	OpenPGP Validation
echo -e "\n================================="
echo -e " OpenPGP Signature \n\n"

TOR_KEY=(
"514102454D0A87DB0767A1EBBE6A0531C18A9179"
"B74417EDDF22AC9F9E90F49142E86A2A11F48D36"
"2133BC600AB133E1D826D173FE43009C4607B1FB"
)

# Fetch Tor signing keys
gpg --auto-key-locate nodefault,wkd --locate-keys ahf@torproject.org
gpg --auto-key-locate nodefault,wkd --locate-keys dgoulet@torproject.org
gpg --auto-key-locate nodefault,wkd --locate-keys nickm@torproject.org

mkdir -p "$REPODIR/~keychain" &>/dev/null

KEYRING="$REPODIR/~keychain/tor.keyring"

rm -f "$KEYRING"

# Export Tor signing keys into the dedicated keyring
gpg --yes \
	--output "$KEYRING" \
	--export "${TOR_KEY[@]}"

if [[ ! -s "$KEYRING" ]]; then
	echo -e "\n=============================="
	echo -e "[-] Tor Keyring Creation Failed"
	echo -e "==============================\n"
	exit 1
fi

# Verify OpenPGP signature
if gpgv \
	--keyring "$KEYRING" \
	"$REPODIR/$(basename "${URL[2]}")" \
	"$REPODIR/$(basename "${URL[1]}")"; then

	echo -e "\n=============================="
	echo -e "[+] Valid Signature on PGP"
	echo -e "==============================\n"

else

	echo -e "\n=============================="
	echo -e "[-] Validation Error on PGP"
	echo -e "==============================\n"
	exit 1

fi

#~	SHA256 Validation
echo -e "\n================================="
echo -e " HASH SHA256 \n"

if sha256sum -c "$(basename "${URL[1]}")"; then

	echo -e "\n================================="
	echo -e "[+] Valid Hashes"
	echo -e "=================================\n"

else

	echo -e "\n================================="
	echo -e "[-] Hashes Validation Failed"
	echo -e "=================================\n"
	exit 1

fi

# Repository Install
tar -xzf "$REPODIR/$TORARCHIVE" -C "$REPODIR"

TORDIR="$REPODIR/$TORVERSION"

echo "$TORDIR"

cd "$TORDIR"

./configure > /dev/null
make &> /dev/null
sudo make install &> /dev/null

# Network / Firewall Settings
cd "$SCRIPTROOT/~resources"

sudo cp torrc /usr/local/etc/tor/torrc
sudo cp firewall-tor /etc/nftables.conf
sudo nft -c -f /etc/nftables.conf
sudo nft -f /etc/nftables.conf
sudo cp disable-ipv6 /etc/sysctl.d/99-disable-ipv6.conf
sudo sysctl -p /etc/sysctl.d/99-disable-ipv6.conf &> /dev/null


echo -e "\n\n\n=============================="
echo -e "[*] Firewall Updated "
echo -e "==========================================================\n"
echo -e "------------------------TOR-PROJECT-----------------------"
echo -e "---------------Welcome to the Onion-Network---------------"
echo -e "\n==========================================================\n"

sudo service tor stop
tor
