#!/system/bin/sh

FILE2CHECK="/data/hwval/adb_check.bin"
MD5CHECK="27ec1016c3db85fa8bb547ada6d3321e"
NONUSER_BUILD="test-keys"
build_tags=`getprop ro.build.tags`
PERS_SYS=`getprop persist.sys.usb.config`
SYS=`getprop sys.usb.config`
is_production=`getprop ro.boot.prod`

if [ x$(getprop ro.boot.unlocked_kernel) == 'xtrue' ]; then
	echo "Enabling ADB for unlocked devices" > /dev/kmsg
	setprop sys.usb.config mtp,adb
	exit
else
	echo "DEVICE IS LOCKED" > /dev/kmsg
fi

if [ -e ${FILE2CHECK} ]; then
	CHECKSUM=$(md5 ${FILE2CHECK})
	CHECKSUM=${CHECKSUM%% *}
	if [ "${CHECKSUM}" == "${MD5CHECK}" ]; then
		echo "persist.sys.usb.config "$PERS_SYS"" > /dev/kmsg
		echo "sys.usb.config "$SYS"" > /dev/kmsg
		echo "Enabling adb for first boot" > /dev/kmsg
		setprop sys.usb.config mtp,adb
		if [ $NONUSER_BUILD == $build_tags ]; then
			echo "Enabling adb for test-keys build" > /dev/kmsg
			setprop persist.sys.usb.config mtp,adb
		fi
	fi
	echo "Removing adb check file" > /dev/kmsg
	rm -rf ${FILE2CHECK}
else
	echo "adb check file not found" > /dev/kmsg
fi

