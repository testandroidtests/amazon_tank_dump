#!/system/bin/sh

LOGSRC="wifi"
LOGNAME="wifi_log_levels"
METRICSTAG="metrics.$LOGNAME"
LOGCATTAG="main.$LOGNAME"
DELAY=120
LOOPSTILMETRICS=29 # Should send to metrics buffer every hour
currentLoop=0
WL=/system/xbin/wl

if [ ! -x $WL ] ; then
	exit
fi

# Given a line containing a wl status mode line, record values we are interested in
#Mode: Managed   RSSI: -46 dBm   SNR: 0 dB       noise: -91 dBm  Flags: RSSI on-channel  Channel: 165

function wl_wlan_info ()
{
	RSSI=`$WL -i $WLAN_IFACE rssi`
	NOISE=`$WL -i $WLAN_IFACE noise`

	CHANNEL=`$WL -i $WLAN_IFACE chanspec`
	CHANNEL=${CHANNEL% *}

	if [ "$RSSI" -eq 0 ]; then
		CONN_STATUS="ConnStatusDisconnected"
	else
		CONN_STATUS="ConnStatusConnected"
	fi
}

function wl_p2p_info ()
{
	P2P_NOISE=`$WL -i $P2P_IFACE noise`
	P2P_CLIENT_LIST=$($WL -i $P2P_IFACE assoclist)

	if [ "$P2P_CLIENT_LIST" ] ; then
		index=0
		REST_OF_LIST=${P2P_CLIENT_LIST#*assoclist?}

		while [ "$REST_OF_LIST" ] ; do
			P2P_MAC_ADDR=${REST_OF_LIST%%?assoclist*}
			P2P_RSSI=$($WL -i $P2P_IFACE rssi $P2P_MAC_ADDR)

			if [ $P2P_RSSI -ne 0 ] ; then
				P2P_RSSI_LIST[$index]=$P2P_RSSI
				((index++))
				log -t $LOGCATTAG $LOGNAME": p2p_dev_address="$P2P_MAC_ADDR" p2p_rssi="$P2P_RSSI
			fi

			REST_OF_LIST=${REST_OF_LIST#*$P2P_MAC_ADDR}
			REST_OF_LIST=${REST_OF_LIST#*assoclist?}
		done
	fi
}

function log_connstatus_metrics
{
	logStr="$LOGSRC:$LOGNAME:$CONN_STATUS=1;CT;1;NR"
	log -t $METRICSTAG $logStr
}

function log_metrics_wifi_status
{
	if [ $CONN_STATUS != "ConnStatusConnected" ] ; then
		return
	fi
	status=`$WL -i $WLAN_IFACE status`

	# Chanspec is present in 11n/ac capabilities.
	bandwidth=`echo "$status" | grep Chanspec | grep -o -e [248]0MHz`
	if [ "$bandwidth" ] ; then
		logBwStr="$LOGSRC:$LOGNAME:ChannelBandwidth$bandwidth=1;CT;1:NR"
	else
		# Device is 11a/b/g which only has 20 MHz bandwidth
		logBwStr="$LOGSRC:$LOGNAME:ChannelBandwidth20MHz=1;CT;1:NR"
	fi
	log -t $METRICSTAG $logBwStr

	channel=${CHANNEL%/*}

	# wl status should have "VHT Capable:" or "HT Capable:" for 11n/ac
	ht=`echo "$status" | grep "HT Capable"`
	if [ "$ht" ] ; then
		# Some 2.4 GHz connections display VHT Capable. Check channel.
		if [[ "$ht" == "HT Capable:" ||
			$channel -lt 36 ]] ; then
			logStr="$LOGSRC:$LOGNAME:WifiMode11n=1;CT;1:NR"
			log -t $METRICSTAG $logStr
		else
			logStr="$LOGSRC:$LOGNAME:WifiMode11ac=1;CT;1:NR"
			log -t $METRICSTAG $logStr
		fi

		return
	fi

	# If all the supported rates have (b), assume 11b.
	rates=`echo "$status" | grep "Supported Rates"`
	if [ "${rates#*[0-9] }" == "$rates" ] ; then
		logStr="$LOGSRC:$LOGNAME:WifiMode11b=1;CT;1:NR"
		log -t $METRICSTAG $logStr
		return
	fi

	# If the above are not true, then it is g/a depending on channel
	if [ $channel -lt 36 ] ; then
		logStr="$LOGSRC:$LOGNAME:WifiMode11g=1;CT;1:NR"
		log -t $METRICSTAG $logStr
	else
		logStr="$LOGSRC:$LOGNAME:WifiMode11a=1;CT;1:NR"
		log -t $METRICSTAG $logStr
	fi
}

function log_metrics_rssi
{
	if [ "$RSSI" -eq 0 ]; then
		return 0
	fi
	logStr="$LOGSRC:$LOGNAME:RssiLevel$RSSI=1;CT;1:NR"
	log -t $METRICSTAG $logStr
}

function log_metrics_snr
{
	if [ "$RSSI" -eq 0 -o "$NOISE" -eq 0 ]; then
		return 0
	fi
	SNR=$(($RSSI - $NOISE))
	logStr="$LOGSRC:$LOGNAME:SnrLevel$SNR=1;CT;1:NR"
	log -t $METRICSTAG $logStr
}

function log_metrics_noise
{
	if [ "$NOISE" -eq 0 ]; then
		return 0
	fi
	logStr="$LOGSRC:$LOGNAME:NoiseLevel$NOISE=1;CT;1:NR"
	log -t $METRICSTAG $logStr
}

function log_metrics_p2p_rssi
{
	if [ "${#P2P_RSSI_LIST[@]}" -eq 0 ]; then
		return 0
	fi
	for p2pRssi in ${P2P_RSSI_LIST[@]}; do
		if [ $p2pRssi -eq 0 ] ; then
			continue
		fi

		logStr="$LOGSRC:$LOGNAME:P2PRssiLevel$p2pRssi=1;CT;1:NR"
		log -t $METRICSTAG $logStr
	done
}

function log_metrics_p2p_snr
{
	if [ "${#P2P_RSSI_LIST[@]}" -eq 0 -o "$P2P_NOISE" -eq 0 ]; then
		return 0
	fi
	for p2pRssi in ${P2P_RSSI_LIST[@]}; do
		if [ $p2pRssi -eq 0 ] ; then
			continue
		fi

		P2P_SNR=$(($p2pRssi - $P2P_NOISE))
		logStr="$LOGSRC:$LOGNAME:P2PSnrLevel$P2P_SNR=1;CT;1:NR"
		log -t $METRICSTAG $logStr
	done
}

function log_metrics_p2p_noise
{
	if [ "$P2P_NOISE" -eq 0 ]; then
		return 0
	fi
	logStr="$LOGSRC:$LOGNAME:P2PNoiseLevel$P2P_NOISE=1;CT;1:NR"
	log -t $METRICSTAG $logStr
}

function log_wifi_metrics
{
	log_metrics_rssi
	log_metrics_snr
	log_metrics_noise

	log_metrics_p2p_rssi
	log_metrics_p2p_snr
	log_metrics_p2p_noise

	log_connstatus_metrics
	log_metrics_wifi_status
}

function clear_stale_stats
{
	NOISE=0
	RSSI=0
	P2P_RSSI=0
	P2P_NOISE=0
	CHANNEL=0
	unset P2P_RSSI_LIST
	$WL reset_cnts
}

function log_logcat
{
	BTC27=`$WL btc_params 27`
	if [ "$WLAN_IFACE" ] ; then
		wl_wlan_info
	fi

	if [ "$P2P_IFACE" ] ; then
		wl_p2p_info
	fi

	logStr="$LOGNAME:rssi=$RSSI;noise=$NOISE;p2prssi=$P2P_RSSI;p2pnoise=$P2P_NOISE;channel=$CHANNEL;btcparam27=$BTC27;"

	COUNTERS=($($WL counters))
	i=0
	while [[ $i -lt $((${#COUNTERS[*]} - 1)) ]] ; do
		case ${COUNTERS[$i]} in txframe|txbyte|txretrans|txerror|rxframe|rxbyte|rxerror|txburst|txphyerror|rxbadplcp|rxcrsglitch|rxstrt|rxdfrmucastmbss|rxbadfcs)
			logStr=$logStr"${COUNTERS[$i]}=${COUNTERS[$i+1]};"
			;;
		esac
		((i++))
	done

	log -t $LOGCATTAG $logStr

	log_maxmin_signals
}

# Log the maximum and minimum values regarding signal quality
function log_maxmin_signals
{
	if [[ ! "$PREVIOUS_CHANNEL" ]] ; then
		PREVIOUS_CHANNEL=$CHANNEL
	elif [[ $PREVIOUS_CHANNEL != $CHANNEL ]] ; then
		PREVIOUS_CHANNEL=$CHANNEL
		MAX_RSSI=''
		MIN_RSSI=''
		MAX_NOISE=''
		MIN_NOISE=''
		MAX_P2P_RSSI=''
		MIN_P2P_RSSI=''
		MAX_P2P_NOISE=''
		MIN_P2P_NOISE=''
	fi

	if [[ ! "$MAX_RSSI" && ! "$MIN_RSSI" && ! "$RSSI" -eq 0 ]] ; then
		MAX_RSSI=$RSSI
		MIN_RSSI=$RSSI
	fi

	if [[ ! "$MAX_NOISE" && ! "$MIN_NOISE" && ! "$NOISE" -eq 0 ]] ; then
		MAX_NOISE=$NOISE
		MIN_NOISE=$NOISE
	fi

	if [[ ! "$MAX_P2P_RSSI" && ! "$MIN_P2P_RSSI" && ! "$P2P_RSSI" -eq 0 ]] ; then
		MAX_P2P_RSSI=$P2P_RSSI
		MIN_P2P_RSSI=$P2P_RSSI
	fi

	if [[ ! "$MAX_P2P_NOISE" && ! "$MIN_P2P_NOISE" && ! "$P2P_NOISE" -eq 0 ]] ; then
		MAX_P2P_NOISE=$P2P_NOISE
		MIN_P2P_NOISE=$P2P_NOISE
	fi

	if [ ! $RSSI -eq 0 ] ; then
		if [ $RSSI -gt $MAX_RSSI ] ; then
			MAX_RSSI=$RSSI
		fi

		if [ $RSSI -lt $MIN_RSSI ] ; then
			MIN_RSSI=$RSSI
		fi
	fi

	if [ ! $NOISE -eq 0 ] ; then
		if [ $NOISE -gt $MAX_NOISE ] ; then
			MAX_NOISE=$NOISE
		fi

		if [ $NOISE -lt $MIN_NOISE ] ; then
			MIN_NOISE=$NOISE
		fi
	fi

	if [ ! $P2P_RSSI -eq 0 ] ; then
		for p2pRssi in ${P2P_RSSI_LIST[@]}; do
			if [ $p2pRssi -eq 0 ] ; then
				continue
			fi

			if [ $p2pRssi -gt $MAX_P2P_RSSI ] ; then
				MAX_P2P_RSSI=$p2pRssi
			fi

			if [ $p2pRssi -lt $MIN_P2P_RSSI ] ; then
				MIN_P2P_RSSI=$p2pRssi
			fi
		done
	fi

	if [ ! $P2P_NOISE -eq 0 ] ; then
		if [ $P2P_NOISE -gt $MAX_P2P_NOISE ] ; then
			MAX_P2P_NOISE=$P2P_NOISE
		fi

		if [ $P2P_NOISE -lt $MIN_P2P_NOISE ] ; then
			MIN_P2P_NOISE=$P2P_NOISE
		fi
	fi

	logStr="$LOGNAME:max_rssi=$MAX_RSSI;min_rssi=$MIN_RSSI;max_noise=$MAX_NOISE;min_noise=$MIN_NOISE;"
	logStr=$logStr"max_p2prssi=$MAX_P2P_RSSI;min_p2prssi=$MIN_P2P_RSSI;max_p2pnoise=$MAX_P2P_NOISE;min_p2pnoise=$MIN_P2P_NOISE"
	log -t $LOGCATTAG $logStr
}

function run ()
{
	WLAN_IFACE=`getprop wifi.interface`
	P2P_IFACE=`getprop wlan.interface.p2p.group`
	log_logcat

	if [[ $currentLoop -eq $LOOPSTILMETRICS ]] ; then
		log_wifi_metrics
		currentLoop=0
	else
		((currentLoop++))
	fi

	clear_stale_stats
}

# Run the collection repeatedly, pushing all output through to the metrics log.
while true ; do
	run
	sleep $DELAY
done
