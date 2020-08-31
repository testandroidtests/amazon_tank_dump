#!/system/bin/sh

# Enable kernel for debug.
setprop persist.sys.uart.klog.enable 1
echo 8 > /proc/sys/kernel/printk

# Disable suspend.
echo test > /sys/power/wake_lock
svc power stayon true

# Enable HDMI GPIO
#cd /sys/devices/virtual/misc/mtgpio/
#echo -wmode 24 0 > pin
#echo -wdir 24 1 > pin
#echo -wdout 24 1 > pin
#echo -wmode 139 1 > pin
#echo -wdir 139 0 > pin
#echo -wpen 139 0 > pin
#echo -wpsel 139 0 > pin
#echo -wdout 139 0 > pin

#echo -wmode 140 1 > pin
#echo -wdir 140 0 > pin
#echo -wpen 140 0 > pin
#echo -wpsel 140 0 > pin
#echo -wdout 140 0 > pin

#echo -wmode 141 1 > pin
#echo -wdir 141 0 > pin
#echo -wpen 141 0 > pin
#echo -wpsel 141 0 > pin
#echo -wdout 141 0 > pin

# Enable hdmi
sleep 3
/system/bin/mt8127_hdmi init 1
sleep 2
/system/bin/mt8127_hdmi res 0xb

