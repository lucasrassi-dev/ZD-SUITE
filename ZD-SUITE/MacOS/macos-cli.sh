#!/bin/bash

# ========================================

#======================
#      MacOS CLI
#======================


# Create Alias
ln -s ~/Library/Mobile\ Documents/com~apple~CloudDocs/Documents ~/Desktop/iCloud-Documents


# DiskUtil Commands

# To List Disks
diskUtil list

# To Erase a Disk
diskUtil eraseDisk JHFS+ DiskName /dev/disk10


# Move Files
mv * /path/to/folder/
find . -maxdepth 1 -name '*.*' -print0 | xargs -0 -I {} mv {} /path/to/folder/