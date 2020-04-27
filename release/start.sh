#!/bin/sh
set -eu

mkdir -p /root/.local/share
ln -sf /data/boss/zware /root/.local/share/zware

mkdir -p /data/boss/zware
mkdir -p /logs/boss

echo "Waiting 10 seconds for Z/IP Gateway to be ready before starting"
sleep 10

echo "Starting boss"
CURRENT_PREFIX=$(ip a show dev eth0 | sed -n 's/^.*inet \([[:digit:]]\+\.[[:digit:]]\+\).*$/\1/p')
COMMANDER_NAME="${BOSS_COMMANDER_NAME:-mqtt}"
exec boss "${COMMANDER_NAME}" zwave -g ${CURRENT_PREFIX}.0.32 | /usr/bin/tee -a /logs/boss/boss.log
