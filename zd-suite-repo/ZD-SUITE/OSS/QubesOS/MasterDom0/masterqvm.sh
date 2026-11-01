#!/usr/bin/bash

# QubesOS XFCE Commands

# View Prefs of VM
qvm-prefs qube_vm

# Executing VM Commands through Dom0
qvm-run qube_vm whoami
qvm-run --pass-io qube_vm whoami
qvm-run  --user root --pass-io qube_vm whoami

# Create Standalone VM
qvm-create --standalone --template debian-12-xfce --label blue WORKSTATION

# Boot VM from ISO File
qvm-run --dispvm app-firefox /usr/bin/firefox
