#!/system/bin/sh

LOGNAME="ping_logger"
DELAY=2
MAX=2
TMP=/tmp #tmpfs, should not be permanent storage
NOPRIVACY=
WL=/system/xbin/wl
WPA_CLI=/system/bin/wpa_cli
NETSTAT=/system/bin/netstat
NETCFG=/system/bin/netcfg
PING=/system/bin/ping

# Ok, this is for debug purposes only
# amazon server are typically not pingable
# so preferably we should find a friendly
# ec2
EXTERNALPINGLOC=
EXTERNALPINGLOC2=

if [ ! -x $WL ] ; then
    exit
fi

function pinger ()
{
    if [ -z "$2" ] ; then
        return
    fi
    echo "pinging ... $1"
    if [ -n "$NOPRIVACY" ] ; then
        $PING -c 3 -i .5 $2
    else
        $PING -c 3 -i .5 $2 | grep -e "packets transmitted" -e "^rtt"
    fi
}

function run ()
{
    echo "Ping logging, cycle $COUNT of $MAX"
    LH=127.0.0.1
    WLAN=`getprop wifi.interface`
    GW=`getprop dhcp.$WLAN.gateway`
    DNS1=`getprop net.dns1`
    DNS2=`getprop net.dns2`
    DNS3=`getprop net.dns3`

    if [ -n "$NOPRIVACY" ] ; then
        echo "netstat:"
        $NETSTAT
        echo "netcfg:"
        $NETCFG
        echo "wpa_cli list_networks: "
        $WPA_CLI list_networks
    fi

    echo "btc_params 27: " `$WL btc_params 27`
    echo "counters: "
    $WL counters
    echo "status: "
    $WL -i $WLAN status | grep -v -e "^SSID:" -e "^BSSID:"
    echo "p2p noise: " `$WL noise`

    pinger localhost $LH
    pinger gateway $GW
    pinger dns1 $DNS1
    pinger dns2 $DNS2
    pinger dns3 $DNS3
    pinger external1 $EXTERNALPINGLOC
    pinger external2 $EXTERNALPINGLOC2
}


# Run the collection repeatedly, to a maximum number of iterations, pushing all output through to the main log.
COUNT=0
while [ $COUNT -lt $MAX ] ; do
    COUNT=$((COUNT+1))
    run | {
        while read LINE ; do
            log -t "main.$LOGNAME" "$LINE"
        done
    }
    sleep $DELAY
done
