#!/bin/bash
set -x

cd /evl-emu
source /evl-emu/bin/activate
exec python3 /evl-emu/evl-emu.py --console --logfile=/var/log/env-emu/env-emu.log
