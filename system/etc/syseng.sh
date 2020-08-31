#!/system/bin/sh

#Error fatal
set -e

LOGNAME="syseng_board_status"
DELAY=593
TMP=/data/syseng
RUN_COUNT=1

# not a hard limit, but a suggestion to some of the collectors
MAXLINELENGTH=300

function clear ()
{
    ACCUM=""
}
function output ()
{
    if [ -n "$ACCUM" ] ; then
        echo "$LOGNAME:$1:$ACCUM:NR"
        ACCUM=""
    fi
}
function output_hi ()
{
    if [ -n "$ACCUM" ] ; then
        echo "$LOGNAME:$1:$ACCUM:HI"
        ACCUM=""
    fi
}
function output_overlong ()
{
    if [ ${#ACCUM} -gt $MAXLINELENGTH ] ; then
        output $1
    fi
}
function add_ct ()
{
    ACCUM="${ACCUM}${ACCUM:+,}$1=$2;CT;1"
}
function add_dv ()
{
    name="$1"
    shift
    ACCUM="${ACCUM}${ACCUM:+,}${name}=$@;DV;1"
}
function add_dv_guard ()
{
    IFS=" :,=;"
    name="$1"
    shift
    ARY=($@)
    IFS=" "
    add_dv "$name" "${ARY[@]}"
    unset IFS
}
function fixunits ()
{
    var="$1"
    value="$2"
    # cope with binary suffixes and decimal points. yay.
    case "$value" in
        *G)     value=${value/G/}
            mult=1073741824
            ;;
        *M)     value=${value/M/}
            mult=1048576
            ;;
        *K)     value=${value/K/}
            mult=1024
            ;;
        *)      mult=1
            ;;
    esac
    frac=${value##*.}
    if [ "$frac" != "$value" ] ; then
        count=${#frac}
        while let count-- ; do
            #ACOS_MOD_BEGIN (fix_expression)
            mult=$((mult/10))
            #ACOS_MOD_END
        done
        value=${value/./}
    fi
    let "$var=$value*$mult" 1
}

# return values in kilobytes, as we will really deal with gigabytes, and would overflow shell math
function fixunits_kb ()
{
    var="$1"
    value="$2"
    # cope with binary suffixes and decimal points. yay.
    case "$value" in
        *G)     value=${value/G/}
            mult=1048576
            ;;
        *M)     value=${value/M/}
            mult=1024
            ;;
        *K)     value=${value/K/}
            mult=1
            ;;
        *)      mult=1
            let value=value/1024 1
            ;;
    esac
    frac=${value##*.}
    if [ "$frac" != "$value" ] ; then
        count=${#frac}
        while let count-- ; do
            #ACOS_MOD_BEGIN (fix_expression)
            mult=$((mult/10))
            #ACOS_MOD_END
        done
        value=${value/./}
    fi
    let "$var=$value*$mult" 1
}

# Understand count of CPUs
CPU_LIST=""
for ENTRY in /sys/devices/system/cpu/cpu[0-9]* ; do
    TAG=${ENTRY#/sys/devices/system/cpu/}
    CPU_LIST="$CPU_LIST $TAG"
done

KSMD_NAME="ksmd"
KSMD_COMM="ksmd"
KSMD_PID=""
AVOD_NAME="com.amazon.avod"
AVOD_COMM="com.amazon.avod"
AVOD_PID=""
GNAV_NAME="com.amazon.tv.launcher:GlobalNavProcess"
GNAV_COMM="lobalNavProcess"
GNAV_PID=""
MEDSERVER_NAME="/system/bin/mediaserver"
MEDSERVER_COMM="mediaserver"
MEDSERVER_PID=""
SFLINGER_NAME="/system/bin/surfaceflinger"
SFLINGER_COMM="surfaceflinger"
SFLINGER_PID=""
DRMSERVER_NAME="/system/bin/drmserver"
DRMSERVER_COMM="drmserver"
DRMSERVER_PID=""

update_pids=true

function get_all_pids ()
{
    ps > $TMP/syseng-ps
    while read A PID B C D E F G PROC ; do
        COMM=""
        read A COMM C D E F G H I MINFLT J MAJFLT K UTIME STIME CUTIME CSTIME < /proc/$PID/stat || true

        if [ "$PROC" = "$KSMD_NAME" -a "$COMM" = "($KSMD_COMM)" ] ; then
            KSMD_PID="$PID"
        elif [ "$PROC" = "$AVOD_NAME" -a "$COMM" = "($AVOD_COMM)" ] ; then
            AVOD_PID="$PID"
        elif [ "$PROC" = "$GNAV_NAME" -a "$COMM" = "($GNAV_COMM)" ] ; then
            GNAV_PID="$PID"
        elif [ "$PROC" = "$MEDSERVER_NAME" -a "$COMM" = "($MEDSERVER_COMM)" ] ; then
            MEDSERVER_PID="$PID"
        elif [ "$PROC" = "$SFLINGER_NAME" -a "$COMM" = "($SFLINGER_COMM)" ] ; then
            SFLINGER_PID="$PID"
        elif [ "$PROC" = "$DRMSERVER_NAME" -a "$COMM" = "($DRMSERVER_COMM)" ] ; then
            DRMSERVER_PID="$PID"
        fi
    done < $TMP/syseng-ps
    rm -f $TMP/syseng-ps
    update_pids=false
}
function vmstat()
{
    # ACOS_MOD_BEGIN
    # vmstat was being truncated at 1023 characters. Split into vmstat into 3 groups to ensure all
    # data is submitted.
    clear
    count=0
    while read LINE ; do
        ary=($LINE)
        case "${ary[0]}" in
            nr_*)   add_ct ${ary[0]} ${ary[1]} ;;
        esac
    done < /proc/vmstat
    output vmstat1

    clear
    count=0
    while read LINE ; do
        ary=($LINE)
        case "${ary[0]}" in
            pg*)    add_ct ${ary[0]} ${ary[1]} ;;
            ps*)    add_ct ${ary[0]} ${ary[1]} ;;
        esac
    done < /proc/vmstat
    output vmstat2

    clear
    count=0
    while read LINE ; do
        ary=($LINE)
        case "${ary[0]}" in
            nr_*) ;;
            pg*) ;;
            ps*) ;;
            *)  add_ct ${ary[0]} ${ary[1]} ;;
        esac
    done < /proc/vmstat
    output vmstat3
}
function meminfo ()
{
    # ACOS_MOD_END
    clear
    #CmaA(active):      13004 kB
    count=0
    while read LINE ; do
        # Trim kB
        LINE=${LINE% kB}
        # Change left paren to underscore
        LINE=${LINE/\(/_}
        # Remove right paren
        LINE=${LINE/\)/}
        # Remove colon
        LINE=${LINE/:/}
        ary=($LINE)
        add_ct ${ary[0]} ${ary[1]}
        output_overlong meminfo
    done < /proc/meminfo
    output meminfo
}
function netdevstats ()
{
    #Inter-|   Receive                                                |  Transmit
    # face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    #     lo:       0       0    0    0    0     0          0         0        0       0    0    0    0     0       0          0

    list=(if recv_bytes recv_packets recv_errs recv_drop recv_fifo recv_frame recv_compressed recv_multicast xmit_bytes xmit_packets xmit_errs xmit_drop xmit_fifo xmit_colls xmit_carrier xmit_compressed)

    (
        clear
        #skip first two lines
        read LINE
        read LINE
        while read LINE ; do
            # remove colon
            LINE=${LINE/:/}
            ary=($LINE)
            if=${ary[0]}
            i=1
            if [ "$if" = "eth0" -o "$if" = "wlan0" ] ; then
                while [ $i -lt ${#ary[*]} ] ; do
                    #if [ "${ary[$i]}" != "0" ] ; then
                        add_ct "${list[$i]}_$if" ${ary[$i]}
                    #fi
                    i=$((i+1))
                done
            fi
        done
        output netdevstats
    ) < /proc/net/dev
}
function cpustats ()
{
    clear
    UPTIME="0"
    read UPTIME IDLETIME < /proc/uptime || true
    add_ct uptime $UPTIME
    output uptime

    #312000 13120
    #499999 69933
    #666666 85018
    #999999 221928
    clear
    while read FREQ TIME ; do
        add_ct time_${FREQ} $TIME
    done < /sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state || true
    output cpufreq

    clear
    for FILE in /sys/devices/system/cpu/cpu*/cpuidle/state*/time ; do
        if [ -e "$FILE" ] ; then
            read TIME < $FILE
            CPU=${FILE#*/cpu/cpu}
            CPU=${CPU%/cpuidle/*}
            STATE=${FILE#*/state}
            STATE=${STATE%/time}
            add_ct "time_cpu${CPU}_c${STATE}" ${TIME}
        fi
    done
    output cpuidle
}
function ksmstats ()
{
    #/sys/kernel/mm/ksm:
    #-r--r--r-- root     root         4096 2014-03-26 21:38 full_scans
    #-r--r--r-- root     root         4096 2014-03-26 21:38 pages_shared
    #-r--r--r-- root     root         4096 2014-03-26 21:38 pages_sharing
    #-rw-r--r-- root     root         4096 2014-03-26 21:38 pages_to_scan
    #-r--r--r-- root     root         4096 2014-03-26 21:38 pages_unshared
    #-r--r--r-- root     root         4096 2014-03-26 21:38 pages_volatile
    #-rw-r--r-- root     root         4096 2014-03-26 21:38 run
    #-rw-r--r-- root     root         4096 2014-03-26 21:38 sleep_millisecs
    if [ -d /sys/kernel/mm/ksm ] ; then
        clear
        for node in full_scans ; do
            read VALUE < /sys/kernel/mm/ksm/$node && add_ct $node $VALUE
        done
        for node in pages_shared pages_sharing pages_to_scan pages_unshared pages_volatile ; do
            read VALUE < /sys/kernel/mm/ksm/$node && add_ct $node $VALUE
        done

        # Read process time for ksmd
        COMM=""
        read A COMM C D E F G H I MINFLT J MAJFLT K UTIME STIME CUTIME CSTIME < /proc/$KSMD_PID/stat || true
        if [ "$COMM" = "($KSMD_COMM)" ] ; then
            add_ct ksmd_utime $UTIME
            add_ct ksmd_stime $STIME
        else
            # update pids, get usage next time around
            update_pids=true
        fi
        output ksmstats
    fi
}
function zramstats ()
{
    # untested, possibly:
    # /sys/block/zram0 # ls -l
    # [...]
    # -r--r--r-- root     root         4096 1970-01-02 00:01 compr_data_size
    # -r--r--r-- root     root         4096 1970-01-02 00:01 orig_data_size
    # -r--r--r-- root     root         4096 1970-01-02 00:01 zero_pages
    # [...]
    if [ -d /sys/block/zram0 ] ; then
        clear
        for node in num_reads num_writes discard compr_data_size orig_data_size zero_pages mem_used_total ; do
            read VALUE < /sys/block/zram0/$node && add_ct $node $VALUE
        done
        output zramstats
    fi
}
function dfstats ()
{
    clear
    df > $TMP/syseng-df
    while read FS SIZE USED FREE BLKSIZE ; do
        case "$FS" in
            /system|/data|/cache|/tmp)
                FS=${FS:1}
                fixunits_kb SIZE $SIZE
                fixunits_kb USED $USED
                fixunits_kb FREE $FREE
                add_ct "${FS}_sizekb" $SIZE
                add_ct "${FS}_usedkb" $USED
                add_ct "${FS}_freekb" $FREE
                ;;
        esac
    done < $TMP/syseng-df
    rm -f $TMP/syseng-df
    output df
}
function sicstats ()
{
    clear
    for dir in /data/data/*/cache/.dl ; do
        if [ -d "$dir" ] ; then
            count=0
            size=0
            # trim prefix and suffix
            DIR=${dir#/data/data/}
            DIR=${DIR%/cache/.dl}
            # replace dots with underlines
            IFS="."
            ary=($DIR)
            IFS="_"
            DIR="${ary[*]}"
            unset IFS

            ls -s "$dir" 2> /dev/null > $TMP/syseng-ls-sics
            while read SIZE NAME ; do
                if [ "$SIZE" = "total" ] ; then
                    continue
                fi
                let count=count+1
                let size=size+$SIZE
            done < $TMP/syseng-ls-sics
            rm -f $TMP/syseng-ls-sics

            add_ct ${DIR}_dlcount $count
            add_ct ${DIR}_dlkb $size
        fi
    done
    output sics
}
function procstats ()
{
    #/proc/stat:
    #cpu0 2824 1054 1448 23254 179 0 249 0 0 0
    #cpu1 2963 1057 1043 23784 248 0 0 0 0 0

    # Read /proc/stat to update figures; if a cpu is offlined, they wont update, which is alright.
    while read TAG USER_TICKS USER_LOWPRIO_TICKS SYSTEM_TICKS IDLE_TICKS REST ; do
        case "$TAG" in
        cpu[0-9]*)
            let "${TAG}_SET_TICKS=1" || true
            let "${TAG}_USER_TICKS=$USER_TICKS" || true
            let "${TAG}_USER_LOWPRIO_TICKS=$USER_LOWPRIO_TICKS" || true
            let "${TAG}_SYSTEM_TICKS=$SYSTEM_TICKS" || true
            let "${TAG}_IDLE_TICKS=$IDLE_TICKS" || true
            ;;
        esac
    done < /proc/stat
}
function cputickstats()
{
    clear
    for CPU in $CPU_LIST ; do
        if let "A=${CPU}_USER_TICKS" && let "B=${CPU}_USER_LOWPRIO_TICKS" && let "C=${CPU}_SYSTEM_TICKS" && let "D=${CPU}_IDLE_TICKS" && let "E=${CPU}_SET_TICKS" ; then
            add_ct ${CPU}_user $A
            add_ct ${CPU}_userlow $B
            add_ct ${CPU}_system $C
            add_ct ${CPU}_idle $D
        fi
    done
    output cputicks
}
function procstats2 ()
{
    clear
    # Read process time for avod
    COMM=""
    read A COMM C D E F G H I MINFLT J MAJFLT CMAJFLT UTIME STIME CUTIME CSTIME < /proc/$AVOD_PID/stat || true
    if [ "$COMM" = "($AVOD_COMM)" ] ; then
        add_ct avod_utime $UTIME
        add_ct avod_stime $STIME
        add_ct avod_majflt $MAJFLT
    else
        # update pid, get usage next time around
        update_pids=true
    fi

    # Read process time for GlobalNav subprocess
    COMM=""
    read A COMM C D E F G H I MINFLT J MAJFLT CMAJFLT UTIME STIME CUTIME CSTIME < /proc/$GNAV_PID/stat || true
    if [ "$COMM" = "($GNAV_COMM)" ] ; then
        add_ct gnav_utime $UTIME
        add_ct gnav_stime $STIME
        add_ct gnav_majflt $MAJFLT
    else
        # update pid, get usage next time around
        update_pids=true
    fi

    # Read process time for mediaserver
    COMM=""
    read A COMM C D E F G H I MINFLT J MAJFLT CMAJFLT UTIME STIME CUTIME CSTIME < /proc/$MEDSERVER_PID/stat || true
    if [ "$COMM" = "($MEDSERVER_COMM)" ] ; then
        add_ct mediaserver_utime $UTIME
        add_ct mediaserver_stime $STIME
        add_ct mediaserver_majflt $MAJFLT
    else
        # update pid, get usage next time around
        update_pids=true
    fi

    # Read process time for surfaceflinger
    COMM=""
    read A COMM C D E F G H I MINFLT J MAJFLT CMAJFLT UTIME STIME CUTIME CSTIME < /proc/$SFLINGER_PID/stat || true
    if [ "$COMM" = "($SFLINGER_COMM)" ] ; then
        add_ct surfaceflinger_utime $UTIME
        add_ct surfaceflinger_stime $STIME
        add_ct surfaceflinger_majflt $MAJFLT
    else
        # update pid, get usage next time around
        update_pids=true
    fi

    # Read process time for drmserver
    COMM=""
    read A COMM C D E F G H I MINFLT J MAJFLT CMAJFLT UTIME STIME CUTIME CSTIME < /proc/$DRMSERVER_PID/stat || true
    if [ "$COMM" = "($DRMSERVER_COMM)" ] ; then
        add_ct drmserver_utime $UTIME
        add_ct drmserver_stime $STIME
        add_ct drmserver_majflt $MAJFLT
    else
        # update pid, get usage next time around
        update_pids=true
    fi

    output procstats
}
TOT_TIME_LAST=0
TOT_TIME_CUR=0
TOT_TIME=0
function selfstats ()
{
    clear
    # Read process time for ourselves, and our children
    COMM=""
    read A COMM C D E F G H I MINFLT J MAJFLT K UTIME STIME CUTIME CSTIME < /proc/$$/stat || true
    if [ -n "$COMM" ] ; then
        clear

        let TOT_TIME_CUR=$UTIME+$STIME+$CUTIME+$CSTIME 1
        # time variables are cputime_t, which is unsigned long long.
        # the max value on Tank platform is 2^64-1 = 18446744073709551615
        if [ $TOT_TIME_CUR -gt $TOT_TIME_LAST ] ; then
            let TOT_TIME=$TOT_TIME_CUR-$TOT_TIME_LAST 1
        else
            MAX_TIME=18446744073709551615
            let TOT_TIME=$MAX_TIME-$TOT_TIME_LAST+$TOT_TIME_CUR 1
        fi
        TOT_TIME_LAST=TOT_TIME

        add_ct tottime $TOT_TIME
        add_ct utime $UTIME
        add_ct stime $STIME
        add_ct cutime $CUTIME
        add_ct cstime $CSTIME
        add_ct count $RUN_COUNT

        output self
    fi
}
function temperature ()
{
    clear
    for tzone in /sys/class/thermal/thermal_zone* ; do
        if [ -e "$tzone/type" ] ; then
            read NAME < "$tzone/type"
            read TEMP < "$tzone/temp"
            add_ct tmon_${NAME} $TEMP
        fi
    done
    output tempstat
}
function cooldingDeviceState ()
{
    clear
    for cdev in /sys/class/thermal/cooling_device* ; do
        if [ -e "$cdev/type" ] ; then
            read NAME < "$cdev/type"
            read STATE < "$cdev/cur_state"
            add_ct thermal_state_${NAME} $STATE
        fi
    done
    output cooling_device
}
function run ()
{
    temperature
    cooldingDeviceState

    let RUN_COUNT=RUN_COUNT+1 1
}
# Run the collection repeatedly, pushing all output through to the metrics log.
while true ; do
    sleep $DELAY
    run > $TMP/syseng-run
    while read LINE ; do
        log -t "metrics.$LOGNAME" $LINE
    done < $TMP/syseng-run
    rm -f $TMP/syseng-run
done
