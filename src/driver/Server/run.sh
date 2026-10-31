#! /bin/sh

#echo "make sd card rw"
#mount -o rw,remount /opt/redpitaya

echo "kill nginx"
killall nginx
sleep 2

cd /opt/redpitaya/src/coincidence/Server


echo "cat disturber Image"
#cat ./coincidence.bit > /dev/xdevcfg

echo "start coincidence counter..."
./server &

#echo "mount"
#mount /dev/sda1 /opt/redpitaya/Festplatte

echo "make sd card ro"
mount -o ro,remount /opt/redpitaya

exit 0

