#!/usr/bin/env bash

echo "==========================================="
echo "  LR's MasterVentoy"
echo -e "===========================================\n"

if (( $# < 2 )); then
    echo -e "\nUsage: $0 [OPTIONS] [DEVICE]\n"
    echo "Modes (choose one):"
    echo "  -i, --install"
    echo "  -u, --update"
    exit 1
fi

PARSED=$(getopt \
    --options iu \
    --longoptions install,update \
    --name "$0" -- "$@") || exit 1

eval set -- "$PARSED"

MODE=""

while true; do
    case "$1" in
        -i|--install)
            MODE="install"
            shift
            ;;
        -u|--update)
            MODE="update"
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Invalid option: $1"
            exit 1
            ;;
    esac
done

USB="$1"

if [[ -z "$USB" ]]; then
    echo "Error: DEVICE is required."
    exit 1
fi

URL="https://sitsa.dl.sourceforge.net/project/ventoy/v1.1.17/ventoy-1.1.17-linux.tar.gz?viasf=1&fid=0106a9c69f57a6b7&e=1785765033&st=Lnw5HOHNdN8Ibq3sZprVcQ"
FILE=$(echo $URL | awk -F '[/?]' '{print $(NF-1)}')
PWD="/tmp"

wget -L -q --show-progress $URL -O ${PWD}/${FILE}
cd $PWD

tar -xvf $FILE
cd "ventoy"*/

lsblk
sudo umount "$USB"

case "$MODE" in
    install)
        sudo bash Ventoy2Disk.sh -I "$USB"
        echo "==================================="
        echo " Ventoy Installed on $USB "
        echo "==================================="
        ;;
    update)
        sudo bash Ventoy2Disk.sh -u "$USB"
        echo "==================================="
        echo " Ventoy Updated on $USB "
        echo "==================================="
        ;;
    *)
        echo "Error: choose --install or --update."
        exit 1
        ;;
esac
