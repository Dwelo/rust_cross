#!/bin/sh
set -eu

# In lieu of a proper way to configure containers to not start on default. The shit that is Z-Wave just oozes into all the crevices
if [ -n "${START_ZWARE}" ] && [ "${START_ZWARE}" != "0" ]; then
  echo "Z-Ware enabled, supressing boss. To disable, find your device and undefine START_ZWARE in the balena dashboard under the "DEVICE VARIABLES". Going to sleep: Zzzzzz....."
  sleep infinity
fi

mkdir -p /root/.local/share
ln -sf /data/boss/zware /root/.local/share/zware

mkdir -p /data/boss/zware
mkdir -p /logs/boss

echo "Waiting 10 seconds for Z/IP Gateway to be ready before starting"
sleep 10

echo "Starting boss"
CURRENT_PREFIX=$(ip a show dev eth0 | sed -n 's/^.*inet \([[:digit:]]\+\.[[:digit:]]\+\).*$/\1/p')
exec boss twilio zwave -g ${CURRENT_PREFIX}.0.32 | /usr/bin/tee -a /logs/boss/boss.log
