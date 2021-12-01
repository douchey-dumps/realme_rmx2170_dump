#! /system/bin/sh

DATE=`date +%F-%H`
CURTIME=`date +%F-%H-%M-%S`

BASE_PATH=/sdcard
SDCARD_LOG_BASE_PATH=${BASE_PATH}/oppo_log

ROOT_TRIGGER_PATH=${SDCARD_LOG_BASE_PATH}/trigger
ANR_BINDER_PATH=/data/oppo_log/anr_binder_info
DATA_LOG_PATH=/data/oppo_log
CACHE_PATH=/cache/admin
config="$1"
topneocount=0

tf_config=`getprop persist.sys.log.tf`
is_tf_card=`ls /mnt/media_rw/ | wc -l`
tfcard_id=`ls /mnt/media_rw/`
isSepcial=`getprop SPECIAL_OPPO_CONFIG`
echo "is_tf_card : $is_tf_card"
echo "tf_config : ${tf_config}"
echo "tfcard_id : ${tfcard_id}"
echo "SPECIAL_OPPO_CONFIG : ${isSepcial}"
if [ "${tf_config}" = "true" ] && [ "$is_tf_card" != "0" ];then
    echo "have TF card"
    DATA_LOG_PATH="/mnt/media_rw/${tfcard_id}/oppo_log"
fi
echo "DATA_LOG_PATH : ${DATA_LOG_PATH}"


function lowram_device_setup()
{
    MemTotalStr=`cat /proc/meminfo | grep MemTotal`
    MemTotal=${MemTotalStr:16:8}

    if [ $MemTotal -lt 6291456 ]; then
        setprop dalvik.vm.heapminfree 512k
        setprop dalvik.vm.heapmaxfree 8m
        setprop dalvik.vm.heapstartsize 8m
    fi

    if [ $MemTotal -lt 4194304 ]; then
        setprop ro.vendor.qti.sys.fw.bservice_enable true
        setprop ro.vendor.qti.sys.fw.bservice_limit 5
        setprop ro.vendor.qti.sys.fw.bservice_age 5000
        setprop ro.config.oppo.low_ram true
    fi

    if [ $MemTotal -lt 3145728 ]; then
        setprop dalvik.vm.heapstartsize 4m
        setprop ro.config.max_starting_bg 3
    fi
}

#Haoran.Zhang@PSW.AD.BuildConfig.StandaloneUserdata.1143522, 2017/09/13, Add for set prop sys.build.display.full_id
#Yujie.Wei@PSW.AD.BuildConfig.2072108, 2019/06/06, Add for get md5 file for wlan mode

function set_new_prop()
{
   if [ $1 ] ; then
     hash_str="_$1";
   else
     hash_str=""
   fi
   setprop "sys.build.display.id" `getprop ro.build.display.id`"$hash_str"
   is_mtk=`getprop ro.mediatek.version.release`
   if [ $is_mtk ] ; then
   #mtk only
     setprop sys.mediatek.version.release `getprop ro.mediatek.version.release`"$hash_str"
   else
     setprop sys.build.display.full_id `getprop ro.build.display.full_id`"$hash_str"
   fi
   #add ro.product.subtype postfix
   subtype=$(getprop ro.product.subtype)
   props="sys.build.display.id sys.mediatek.version.release sys.build.display.full_id"
   if [ "$subtype" != "" ] ; then
    for prop in $props; do
     value=$(getprop $prop)
     if [ "" != "$value" ];then
        #new_value=$(echo $value | perl -ne 'm|([^_]+)(.*)| && \
        #  ('$subtype' ne substr($1,-length('$subtype'))) && printf "$1'$subtype'$2"' )
        fs=$(echo "$value" | sed 's|_| |')
        head=$(echo "$fs"|awk '{print $1}')
        other=$(echo "$fs"|awk '{print $2}')
        postfix=${head:$(expr ${#head} - ${#subtype}):${#subtype}}
        if [ "$subtype" != "$postfix" ]; then
           new_value="${head}${subtype}_${other}"
           #exchange ROM PRE position
           new_value=$(echo $new_value | sed -r "s/(ROM|PRE)${subtype}/${subtype}\1/")
           setprop $prop $new_value
        fi
     fi
    done
   fi
   #end
}

function userdatarefresh(){

   info_file="/data/engineermode/data_version"
   ftm_mode=`cat /sys/systeminfo/ftmmode`

   #if wlan mode ; then
   if [ x"${ftm_mode}" = x"5" ]; then
    if [ -s $info_file ] ;then
        data_ver=`cat $info_file | head -1 | xargs echo -n`
        set_new_prop $data_ver
    else
        set_new_prop "00000000"
    fi
        return 0
   fi

   #if [ "$(df /data | grep tmpfs)" ] ; then
   if [ ! `getprop vold.decrypt`  ] ; then
     if [ ! "$(df /data | grep tmpfs)" ] ; then
        mount /dev/block/bootdevice/by-name/userdata /data
     else
       return 0
     fi
   fi
   mkdir /data/engineermode
   #info_file is not empty
   if [ -s $info_file ] ;then
       data_ver=`cat $info_file | head -1 | xargs echo -n`
       set_new_prop $data_ver
   else
          if [ ! -f $info_file ] ;then
            if [ ! -f /data/engineermode/.sd.txt ]; then
              cp  /system/media/.sd.txt  /data/engineermode/.sd.txt
            fi
            cp /system/engineermode/*  /data/engineermode/
            #create an empty file
            rm $info_file
            touch $info_file
            chmod 0644 /data/engineermode/.sd.txt
            chmod 0644 /data/engineermode/persist*
          fi
       set_new_prop "00000000"
   fi
   #tmp patch for sendtest version
   if [ `getprop ro.build.fix_data_hash` ]; then
      set_new_prop ""
   fi
   #end
    #ifdef COLOROS_EDIT
    #Yaohong.Guo@ROM.Frameworks, 2018/11/19 : Add for OTA data upgrade
    chown system:system /data/engineermode/*
    if [ -f "/data/engineermode/.sd.txt" ]; then
        chown system:system /data/engineermode/.sd.txt
    fi
    if [ -d "/data/etc/appchannel" ]; then
        chown system:system /data/etc/appchannel/*
    fi
    #endif /* COLOROS_EDIT */
   chmod 0750 /data/engineermode
   chmod 0740 /data/engineermode/default_workspace_device*.xml
   chown system:launcher /data/engineermode
   chown system:launcher /data/engineermode/default_workspace_device*.xml
}
#end



function Preprocess(){
    mkdir -p ${SDCARD_LOG_BASE_PATH}
    mkdir -p ${ROOT_TRIGGER_PATH}
}

function logObserver() {
    autostop=`getprop persist.sys.autostoplog`
    if [ x"${autostop}" = x"1" ]; then
        boot_completed=`getprop sys.boot_completed`
        sleep 10
        while [ x${boot_completed} != x"1" ];do
            sleep 10
            boot_completed=`getprop sys.boot_completed`
        done

        space_full=false
            echo "start observer"
        while [ ${space_full} == false ];do
            echo "start observer in loop"
            sleep 60
            echo "start observer sleep end"
            full_date=`date +%F-%H-%M`
            FreeSize=`df /data | grep /data | $XKIT awk '{print $4}'`
            isM=`echo ${FreeSize} | $XKIT awk '{ print index($1,"M")}'`
            echo " free size = ${FreeSize} "
            if [ ${FreeSize} -ge 1524000 ]; then
                echo "${full_date} left space ${FreeSize} more than 1.5G"
            else
                leftsize=`echo ${FreeSize} | $XKIT awk '{printf("%d",$1)}'`
                if [ $leftsize -le 1000000 ];then
                    space_full=true
                    echo "${full_date} leftspace $FreeSize is less than 1000M,stop log" >> ${DATA_LOG_PATH}/log_history.txt
                    setprop sys.oppo.logkit.full true
                    # setprop persist.sys.assert.panic false
                    setprop ctl.stop logcatsdcard
                    setprop ctl.stop logcatradio
                    setprop ctl.stop logcatevent
                    setprop ctl.stop logcatkernel
                    setprop ctl.stop tcpdumplog
                    setprop ctl.stop fingerprintlog
                    setprop ctl.stop logfor5G
                    setprop ctl.stop fplogqess
                fi
            fi
        done
    fi
}

function backup_unboot_log(){
    i=1
    while [ true ];do
        if [ ! -d /cache/unboot_$i ];then
            is_folder_empty=`ls $CACHE_PATH/*`
            if [ "$is_folder_empty" = "" ];then
                echo "folder is empty"
            else
                echo "mv /cache/admin /cache/unboot_"
                mv /cache/admin /cache/unboot_$i
            fi
            break
        else
            i=`$XKIT expr $i + 1`
        fi
        if [ $i -gt 5 ];then
            break
        fi
    done
}

function initcache(){
    panicenable=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    boot_completed=`getprop sys.boot_completed`
    if [ x"${panicenable}" = x"true" ] || [ x"${camerapanic}" = x"true" ] && [ x"${boot_completed}" != x"1" ]; then
        if [ ! -d /dev/log ];then
            mkdir -p /dev/log
            chmod -R 755 /dev/log
        fi
        is_admin_empty=`ls $CACHE_PATH | wc -l`
        if [ "$is_admin_empty" != "0" ];then
            echo "backup_unboot_log"
            backup_unboot_log
        fi
        echo "mkdir /cache/admin"
        mkdir -p ${CACHE_PATH}
        mkdir -p ${CACHE_PATH}/apps
        mkdir -p ${CACHE_PATH}/kernel
        mkdir -p ${CACHE_PATH}/netlog
        mkdir -p ${CACHE_PATH}/fingerprint
        mkdir -p ${CACHE_PATH}/5G
        setprop sys.oppo.collectcache.start true
    fi
}

function logcatcache(){
    panicenable=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    argtrue='true'
    if [ "${panicenable}" = "${argtrue}" ] || [ x"${camerapanic}" = x"true" ]; then
    /system/bin/logcat -G 16M
    /system/bin/logcat -f ${CACHE_PATH}/apps/android_boot.txt -r10240 -n 5 -v threadtime
    fi
}
function radiocache(){
    radioenable=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    argtrue='true'
    if [ "${radioenable}" = "${argtrue}" ] || [ x"${camerapanic}" = x"true" ]; then
    /system/bin/logcat -b radio -f ${CACHE_PATH}/apps/radio_boot.txt -r4096 -n 3 -v threadtime
    fi
}
function eventcache(){
    panicenable=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    argtrue='true'
    if [ "${panicenable}" = "${argtrue}" ] || [ x"${camerapanic}" = x"true" ]; then
    /system/bin/logcat -b events -f ${CACHE_PATH}/apps/events_boot.txt -r4096 -n 10 -v threadtime
    fi
}
function kernelcache(){
  panicenable=`getprop persist.sys.assert.panic`
  camerapanic=`getprop persist.sys.assert.panic.camera`
  argtrue='true'
  if [ "${panicenable}" = "${argtrue}" ] || [ x"${camerapanic}" = x"true" ]; then
  dmesg > ${CACHE_PATH}/kernel/kinfo_boot.txt
  cat proc/boot_dmesg > ${CACHE_PATH}/kernel/uboot.txt
  /system/xbin/klogd -f ${CACHE_PATH}/kernel/kinfo_boot0.txt -n -x -l 7
  fi
}

#Linjie.Xu@PSW.AD.Power.PowerMonitor.1104067, 2018/01/17, Add for OppoPowerMonitor get dmesg at O
function kernelcacheforopm(){
  opmlogpath=`getprop sys.opm.logpath`
  dmesg > ${opmlogpath}dmesg.txt
  chown system:system ${opmlogpath}dmesg.txt
}
#Linjie.Xu@PSW.AD.Power.PowerMonitor.1104067, 2018/01/17, Add for OppoPowerMonitor get Sysinfo at O
function psforopm(){
  opmlogpath=`getprop sys.opm.logpath`
  ps -A -T > ${opmlogpath}psO.txt
  chown system:system ${opmlogpath}psO.txt
}
#Linjie.Xu@PSW.AD.Power.PowerMonitor.1104067, 2019/08/21, Add for OppoPowerMonitor get qrtr at Qcom
function qrtrlookupforopm() {
    echo "qrtrlookup begin"
    opmlogpath=`getprop sys.opm.logpath`
    if [ -d "/d/ipc_logging" ]; then
        echo ${opmlogpath}
        /vendor/bin/qrtr-lookup > ${opmlogpath}/qrtr-lookup_info.txt
        chown system:system ${opmlogpath}/qrtr-lookup_info.txt
    fi
    echo "qrtrlookup end"
}
function cpufreqforopm(){
  opmlogpath=`getprop sys.opm.logpath`
  cat /sys/devices/system/cpu/*/cpufreq/scaling_cur_freq > ${opmlogpath}cpufreq.txt
  chown system:system ${opmlogpath}cpufreq.txt
}
function smapsforhealth(){
  opmlogpath=`getprop sys.opm.logpath`
  pid=`getprop sys.opm.pid`
  cat /proc/${pid}/smaps > ${opmlogpath}smaps_${pid}.txt
  chown system:system ${opmlogpath}smaps_${pid}.txt
}
function dmaprocsforhealth(){
  opmlogpath=`getprop sys.opm.logpath`
  cat /sys/kernel/debug/ion/heaps/system > ${opmlogpath}dmaprocs.txt
  cat /sys/kernel/debug/dma_buf/dmaprocs >> ${opmlogpath}dmaprocs.txt
  chown system:system ${opmlogpath}dmaprocs.txt
}
function slabinfoforhealth(){
  opmlogpath=`getprop sys.opm.logpath`
  cat /proc/slabinfo > ${opmlogpath}slabinfo.txt
  cat /sys/kernel/debug/page_owner > ${opmlogpath}pageowner.txt
  chown system:system ${opmlogpath}slabinfo.txt
  chown system:system ${opmlogpath}pageowner.txt
}
function svelteforhealth(){
  sveltetracer=`getprop sys.opm.svelte_tracer`
  svelteops=`getprop sys.opm.svelte_ops`
  svelteargs=`getprop sys.opm.svelte_args`
  opmlogpath=`getprop sys.opm.logpath`
  /system/bin/svelte tracer -t ${sveltetracer} -o ${svelteops} -a ${svelteargs}
  sleep 12
  chown system:system ${opmlogpath}*svelte.txt
}
function meminfoforhealth(){
  opmlogpath=`getprop sys.opm.logpath`
  cat /proc/meminfo > ${opmlogpath}meminfo.txt
  chown system:system ${opmlogpath}meminfo.txt
}
function systraceforopm(){
    opmlogpath=`getprop sys.opm.logpath`
    CATEGORIES=`atrace --list_categories | $XKIT awk '{printf "%s ", $1}'`
    systrace_duration=`getprop sys.opm.systrace.duration`
    if [ "$systrace_duration" != "" ]
    then
        LOGTIME=`date +%F-%H-%M-%S`
        SYSTRACE_DIR=${opmlogpath}/systrace_${LOGTIME}
        mkdir -p ${SYSTRACE_DIR}
        ((sytrace_buffer=$systrace_duration*1536))
        atrace -z -b ${sytrace_buffer} -t ${systrace_duration} ${CATEGORIES} > ${SYSTRACE_DIR}/atrace_raw
        chown -R system:system ${SYSTRACE_DIR}
    fi
}
function tcpdumpcache(){
    tcpdmpenable=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    argtrue='true'
    if [ "${tcpdmpenable}" = "${argtrue}" ] || [ x"${camerapanic}" = x"true" ]; then
        tcpdump -i any -p -s 0 -W 2 -C 10 -w ${CACHE_PATH}/netlog/tcpdump_boot -Z root
    fi
}

function fingerprintcache(){
    platform=`getprop ro.board.platform`
    echo "platform ${platform}"
    state=`cat /proc/oppo_secure_common/secureSNBound`

    if [ ${state} != "0" ]
    then
        cat /sys/kernel/debug/tzdbg/log > ${CACHE_PATH}/fingerprint/fingerprint_boot.txt
    fi

}

function logfor5Gcache(){
    cat /sys/kernel/debug/ipc_logging/esoc-mdm/log_cont > ${CACHE_PATH}/5G/5G_boot.txt
}

function fplogcache(){
    platform=`getprop ro.board.platform`

    state=`cat /proc/oppo_secure_common/secureSNBound`

    if [ ${state} != "0" ]
    then
        cat /sys/kernel/debug/tzdbg/qsee_log > ${CACHE_PATH}/fingerprint/qsee_boot.txt
    fi

}

function PreprocessLog(){
    if [ ! -d /dev/log ];then
        mkdir -p /dev/log
        chmod -R 755 /dev/log
    fi
    echo "enter PreprocessLog"
    panicenable=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    argtrue='true'
    if [ "${panicenable}" = "${argtrue}" ] || [ x"${camerapanic}" = x"true" ]; then
        boot_completed=`getprop sys.boot_completed`
        decrypt_delay=0
        while [ x${boot_completed} != x"1" ];do
            sleep 1
            decrypt_delay=`expr $decrypt_delay + 1`
            boot_completed=`getprop sys.boot_completed`
        done

        echo "start mkdir"
        LOGTIME=`date +%F-%H-%M-%S`

        #add for TF card begin
        tf_config=`getprop persist.sys.log.tf`
        if [ "${tf_config}" = "true" ];then
            is_tf_card=`ls /mnt/media_rw/ | wc -l`
            tfcard_id=`ls /mnt/media_rw/`
            if [ "$is_tf_card" != "0" ];then
                DATA_LOG_PATH="/mnt/media_rw/${tfcard_id}/oppo_log"
            fi
            tf_delay=0
            while [ -z ${tfcard_id} ] && [ ${tf_delay} -lt 10 ];do
                sleep 1
                tf_delay=`expr $tf_delay + 1`
                tfcard_id=`ls /mnt/media_rw/`
            done
            if [ ${tf_delay} -lt 10 ]; then
                DATA_LOG_PATH="/mnt/media_rw/${tfcard_id}/oppo_log"
            fi
        fi
        echo "oppoLog path : ${DATA_LOG_PATH}"
        #add for TF card end

        ROOT_SDCARD_LOG_PATH=${DATA_LOG_PATH}/${LOGTIME}
        echo $ROOT_SDCARD_LOG_PATH
        ROOT_SDCARD_apps_LOG_PATH=${ROOT_SDCARD_LOG_PATH}/apps
        ROOT_SDCARD_kernel_LOG_PATH=${ROOT_SDCARD_LOG_PATH}/kernel
        ROOT_SDCARD_netlog_LOG_PATH=${ROOT_SDCARD_LOG_PATH}/netlog
        ROOT_SDCARD_FINGERPRINTERLOG_PATH=${ROOT_SDCARD_LOG_PATH}/fingerprint
        ROOT_SDCARD_5GLOG_PATH=${ROOT_SDCARD_LOG_PATH}/5G
        ASSERT_PATH=${ROOT_SDCARD_LOG_PATH}/oppo_assert
        TOMBSTONE_PATH=${ROOT_SDCARD_LOG_PATH}/tombstone
        ANR_PATH=${ROOT_SDCARD_LOG_PATH}/anr
        #Chunbo.Gao@PSW.AD.OppoDebug.LogKit.1968962, 2019/4/23, Add for qmi log
        QMI_PATH=${ROOT_SDCARD_LOG_PATH}/qmi
        mkdir -p  ${ROOT_SDCARD_LOG_PATH}
        mkdir -p  ${ROOT_SDCARD_apps_LOG_PATH}
        mkdir -p  ${ROOT_SDCARD_kernel_LOG_PATH}
        mkdir -p  ${ROOT_SDCARD_netlog_LOG_PATH}
        mkdir -p  ${ROOT_SDCARD_FINGERPRINTERLOG_PATH}
        mkdir -p  ${ROOT_SDCARD_5GLOG_PATH}
        mkdir -p  ${ASSERT_PATH}
        mkdir -p  ${TOMBSTONE_PATH}
        mkdir -p  ${ANR_PATH}
        #Chunbo.Gao@PSW.AD.OppoDebug.LogKit.1968962, 2019/4/23, Add for qmi log
        mkdir -p  ${QMI_PATH}
        mkdir -p  ${ANR_BINDER_PATH}
        chmod -R 777 ${ANR_BINDER_PATH}
        chown system:system ${ANR_BINDER_PATH}
        chmod -R 777 ${ROOT_SDCARD_LOG_PATH}
        echo ${LOGTIME} >> ${DATA_LOG_PATH}/log_history.txt
        echo ${LOGTIME} >> ${DATA_LOG_PATH}/transfer_list.txt
        #TODO:wenzhen android O
        #decrypt=`getprop com.oppo.decrypt`
        decrypt='false'
        if [ x"${decrypt}" != x"true" ]; then
            setprop ctl.stop logcatcache
            setprop ctl.stop radiocache
            setprop ctl.stop eventcache
            setprop ctl.stop kernelcache
            setprop ctl.stop fingerprintcache
            setprop ctl.stop logfor5Gcache
            setprop ctl.stop fplogcache
            setprop ctl.stop tcpdumpcache
            mv ${CACHE_PATH}/* ${ROOT_SDCARD_LOG_PATH}/
            mv /cache/unboot_* ${ROOT_SDCARD_LOG_PATH}/
            setprop com.oppo.decrypt true
        fi
        setprop persist.sys.com.oppo.debug.time ${LOGTIME}
    fi

    panicenable=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    argtrue='true'
    if [ "${panicenable}" = "${argtrue}" ] || [ x"${camerapanic}" = x"true" ]; then
        setprop sys.oppo.logkit.appslog ${ROOT_SDCARD_apps_LOG_PATH}
        setprop sys.oppo.logkit.kernellog ${ROOT_SDCARD_kernel_LOG_PATH}
        setprop sys.oppo.logkit.netlog ${ROOT_SDCARD_netlog_LOG_PATH}
        setprop sys.oppo.logkit.assertlog ${ASSERT_PATH}
        setprop sys.oppo.logkit.anrlog ${ANR_PATH}
        #Chunbo.Gao@PSW.AD.OppoDebug.LogKit.1968962, 2019/4/23, Add for qmi log
        setprop sys.oppo.logkit.qmilog ${QMI_PATH}
        setprop sys.oppo.logkit.tombstonelog ${TOMBSTONE_PATH}
        setprop sys.oppo.logkit.fingerprintlog ${ROOT_SDCARD_FINGERPRINTERLOG_PATH}
        setprop sys.oppo.collectlog.start true
    fi
}

function initLogPath(){
    FreeSize=`df /data | grep /data | $XKIT awk '{print $4}'`
    GSIZE=`echo | $XKIT awk '{printf("%d",2*1024*1024)}'`
if [ ${FreeSize} -ge ${GSIZE} ]; then
    androidSize=51200
    androidCount=`echo ${FreeSize} 30 50 ${androidSize} | $XKIT awk '{printf("%d",$1*$2/$3/$4)}'`
    if [ ${androidCount} -ge 180 ]; then
        androidCount=180
    fi
    radioSize=20480
    radioCount=`echo ${FreeSize} 1 50 ${radioSize} | $XKIT awk '{printf("%d",$1*$2/$3/$4)}'`
    if [ ${radioCount} -ge 25 ]; then
        radioCount=25
    fi
    eventSize=20480
    eventCount=`echo ${FreeSize} 1 50 ${eventSize} | $XKIT awk '{printf("%d",$1*$2/$3/$4)}'`
    if [ ${eventCount} -ge 25 ]; then
        eventCount=25
    fi
    tcpdumpSize=100
    tcpdumpSizeKb=100*1024
    tcpdumpCount=`echo ${FreeSize} 10 50 ${tcpdumpSizeKb} | $XKIT awk '{printf("%d",$1*$2/$3/$4)}'`
    if [ ${tcpdumpCount} -ge 50 ]; then
        tcpdumpCount=50
    fi
else
    androidSize=20480
    androidCount=`echo ${FreeSize} 30 50 ${androidSize} | $XKIT awk '{printf("%d",$1*$2*1024/$3/$4)}'`
    if [ ${androidCount} -ge 10 ]; then
        androidCount=10
    fi
    radioSize=10240
    radioCount=`echo ${FreeSize} 1 50 ${radioSize} | $XKIT awk '{printf("%d",$1*$2*1024/$3/$4)}'`
    if [ ${radioCount} -ge 4 ]; then
        radioCount=4
    fi
    eventSize=10240
    eventCount=`echo ${FreeSize} 1 50 ${eventSize} | $XKIT awk '{printf("%d",$1*$2*1024/$3/$4)}'`
    if [ ${eventCount} -ge 4 ]; then
        eventCount=4
    fi
    tcpdumpSize=50
    tcpdumpCount=`echo ${FreeSize} 10 50 ${tcpdumpSize} | $XKIT awk '{printf("%d",$1*$2/$3/$4)}'`
    if [ ${tcpdumpCount} -ge 2 ]; then
        tcpdumpCount=2
    fi
fi
    ROOT_SDCARD_apps_LOG_PATH=`getprop sys.oppo.logkit.appslog`
    ROOT_SDCARD_kernel_LOG_PATH=`getprop sys.oppo.logkit.kernellog`
    ROOT_SDCARD_netlog_LOG_PATH=`getprop sys.oppo.logkit.netlog`
    ASSERT_PATH=`getprop sys.oppo.logkit.assertlog`
    TOMBSTONE_PATH=`getprop sys.oppo.logkit.tombstonelog`
    ANR_PATH=`getprop sys.oppo.logkit.anrlog`
    #Chunbo.Gao@PSW.AD.OppoDebug.LogKit.1968962, 2019/4/23, Add for qmi log
    QMI_PATH=`getprop sys.oppo.logkit.qmilog`
    ROOT_SDCARD_FINGERPRINTERLOG_PATH=`getprop sys.oppo.logkit.fingerprintlog`
}

function PreprocessOther(){
    mkdir -p  $ROOT_TRIGGER_PATH/${CURTIME}
    GRAB_PATH=$ROOT_TRIGGER_PATH/${CURTIME}
}

function Logcat(){
    panicenable=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    argtrue='true'
    if [ "${panicenable}" = "${argtrue}" ] || [ x"${camerapanic}" = x"true" ]
    then
    /system/bin/logcat -f ${ROOT_SDCARD_apps_LOG_PATH}/android.txt -r${androidSize} -n ${androidCount}  -v threadtime  -A
    else
    setprop ctl.stop logcatsdcard
    fi
}
function LogcatRadio(){
    radioenable=`getprop persist.sys.assert.panic`
    argtrue='true'
    if [ "${radioenable}" = "${argtrue}" ]
    then
    /system/bin/logcat -b radio -f ${ROOT_SDCARD_apps_LOG_PATH}/radio.txt -r${radioSize} -n ${radioCount}  -v threadtime -A
    else
    setprop ctl.stop logcatradio
    fi
}
function LogcatEvent(){
    panicenable=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    argtrue='true'
    if [ "${panicenable}" = "${argtrue}" ] || [ x"${camerapanic}" = x"true" ]
    then
    /system/bin/logcat -b events -f ${ROOT_SDCARD_apps_LOG_PATH}/events.txt -r${eventSize} -n ${eventCount}  -v threadtime -A
    else
    setprop ctl.stop logcatevent
    fi
}
function LogcatKernel(){
    panicenable=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    argtrue='true'
    if [ "${panicenable}" = "${argtrue}" ] || [ x"${camerapanic}" = x"true" ]
    then
    cat proc/cmdline > ${ROOT_SDCARD_kernel_LOG_PATH}/cmdline.txt
    /system/xbin/klogd -f - -n -x -l 7 | $XKIT tee - ${ROOT_SDCARD_kernel_LOG_PATH}/kinfo0.txt | $XKIT awk 'NR%400==0'
    fi
}

#Qi.Zhang@TECH.BSP.Stability 2019/09/20, Add for uefi log
function LogcatUefi(){
    panicenable=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    argtrue='true'
    if [ "${panicenable}" = "${argtrue}" ] || [ x"${camerapanic}" = x"true" ];then
        mkdir -p  ${CACHE_PATH}/uefi
        /system/bin/extractCurrentUefiLog
    fi
}

function tcpdumpLog(){
    tcpdmpenable=`getprop persist.sys.assert.panic`
    argtrue='true'
    if [ "${tcpdmpenable}" = "${argtrue}" ]; then
        tcpdump -i any -p -s 0 -W ${tcpdumpCount} -C ${tcpdumpSize} -w ${ROOT_SDCARD_netlog_LOG_PATH}/tcpdump.pcap -Z root
    fi
}
function grabNetlog(){

    tcpdump -i any -p -s 0 -W 5 -C 10 -w /cache/admin/netlog/tcpdump.pcap -Z root

}

function LogcatFingerprint(){
    countfp=1
    platform=`getprop ro.board.platform`

    state=`cat /proc/oppo_secure_common/secureSNBound`

    echo "LogcatFingerprint state = ${state}"
    if [ ${state} != "0" ]
    then
    echo "LogcatFingerprint in loop"
        while true
        do
            cat /sys/kernel/debug/tzdbg/log > ${ROOT_SDCARD_FINGERPRINTERLOG_PATH}/fingerprint_log${countfp}.txt
            if [ ! -s ${ROOT_SDCARD_FINGERPRINTERLOG_PATH}/fingerprint_log${countfp}.txt ];then
            rm ${ROOT_SDCARD_FINGERPRINTERLOG_PATH}/fingerprint_log${countfp}.txt;
            fi
            ((countfp++))
            sleep 1
        done
    fi
}

function Logcat5G(){
    count5G=1
    echo "Logcat5G in loop"
        while true
        do
            cat /sys/kernel/debug/ipc_logging/esoc-mdm/log_cont > ${ROOT_SDCARD_5GLOG_PATH}/5G_log${count5G}.txt
            if [ ! -s ${ROOT_SDCARD_5GLOG_PATH}/5G_log${count5G}.txt ];then
            rm ${ROOT_SDCARD_5GLOG_PATH}/5G_log${count5G}.txt;
            fi
            ((count5G++))
            sleep 1
        done
}

function LogcatFingerprintQsee(){
    countqsee=1
    platform=`getprop ro.board.platform`
    state=`cat /proc/oppo_secure_common/secureSNBound`

    echo "LogcatFingerprintQsee state = ${state}"
    if [ ${state} != "0" ]
    then
        echo "LogcatFingerprintQsee in loop"
        while true
        do
            cat /sys/kernel/debug/tzdbg/qsee_log > ${ROOT_SDCARD_FINGERPRINTERLOG_PATH}/qsee_log${countqsee}.txt
            if [ ! -s ${ROOT_SDCARD_FINGERPRINTERLOG_PATH}/qsee_log${countqsee}.txt ];then
            rm ${ROOT_SDCARD_FINGERPRINTERLOG_PATH}/qsee_log${countqsee}.txt;
            fi
            ((countqsee++))
            sleep 1
        done
    fi
}

function screen_record(){
    ROOT_SDCARD_RECORD_LOG_PATH=${SDCARD_LOG_BASE_PATH}/screen_record
    mkdir -p  ${ROOT_SDCARD_RECORD_LOG_PATH}
    touch ${ROOT_SDCARD_RECORD_LOG_PATH}/.nomedia
    /system/bin/screenrecord  --time-limit 1800 --bit-rate 8000000 --size 1080x2340 --verbose  ${ROOT_SDCARD_RECORD_LOG_PATH}/screen_record.mp4
}

function screen_record_backup(){
    backupFile="/data/media/0/oppo_log/screen_record/screen_record_old.mp4"
    if [ -f "$backupFile" ]; then
         rm $backupFile
    fi

    curFile="/data/media/0/oppo_log/screen_record/screen_record.mp4"
    if [ -f "$curFile" ]; then
         mv $curFile $backupFile
    fi
}

function Dmesg(){
    mkdir -p  $ROOT_TRIGGER_PATH/${CURTIME}
    dmesg > $ROOT_TRIGGER_PATH/${CURTIME}/dmesg.txt;
}
function Dumpsys(){
    mkdir -p  $ROOT_TRIGGER_PATH/dumpsys
    dumpsys > $ROOT_TRIGGER_PATH/dumpsys/dumpsys_all_${CURTIME}.txt;
}
function Dumpstate(){
    mkdir -p  $ROOT_TRIGGER_PATH/${CURTIME}_dumpstate
    dumpstate > $ROOT_TRIGGER_PATH/${CURTIME}_dumpstate/dumpstate.txt
}
function Top(){
    mkdir -p  $ROOT_TRIGGER_PATH/${CURTIME}_top
    top -n 1 > $ROOT_TRIGGER_PATH/${CURTIME}_top/top.txt;
}
function Ps(){
    mkdir -p  $ROOT_TRIGGER_PATH/${CURTIME}_ps
    ps > $ROOT_TRIGGER_PATH/${CURTIME}_ps/ps.txt;
}

function Server(){
    mkdir -p  $ROOT_TRIGGER_PATH/${CURTIME}_servelist
    service list  > $ROOT_TRIGGER_PATH/${CURTIME}_servelist/serviceList.txt;
}

function DumpEnvironment(){
    rm  -rf /cache/environment
    umask 000
    mkdir -p /cache/environment
    chmod 777 /data/misc/gpu/gpusnapshot/*
    ls -l /data/misc/gpu/gpusnapshot/ > /cache/environment/snapshotlist.txt
    cp -rf /data/misc/gpu/gpusnapshot/* /cache/environment/
    chmod 777 /cache/environment/dump*
    rm -rf /data/misc/gpu/gpusnapshot/*
    #ps -A > /cache/environment/ps.txt &
    ps -AT > /cache/environment/ps_thread.txt &
    mount > /cache/environment/mount.txt &
    extra_log="/data/system/dropbox/extra_log"
    if [ -d  ${extra_log} ];
    then
        all_logs=`ls ${extra_log}`
        for i in ${all_logs};do
            echo ${i}
            cp /data/system/dropbox/extra_log/${i}  /cache/environment/extra_log_${i}
        done
        chmod 777 /cache/environment/extra_log*
    fi
    getprop > /cache/environment/prop.txt &
    dumpsys SurfaceFlinger --dispsync > /cache/environment/sf_dispsync.txt &
    dumpsys SurfaceFlinger > /cache/environment/sf.txt &
    /system/bin/dmesg > /cache/environment/dmesg.txt &
    /system/bin/logcat -d -v threadtime > /cache/environment/android.txt &
    /system/bin/logcat -b radio -d -v threadtime > /cache/environment/radio.txt &
    /system/bin/logcat -b events -d -v threadtime > /cache/environment/events.txt &
    i=`ps -A | grep system_server | $XKIT awk '{printf $2}'`
    ls /proc/$i/fd -al > /cache/environment/system_server_fd.txt &
    ps -A -T | grep $i > /cache/environment/system_server_thread.txt &
    cp -rf /data/system/packages.xml /cache/environment/packages.xml
    chmod +r /cache/environment/packages.xml
    cat /sys/kernel/debug/binder/state > /cache/environment/binder_info.txt &
    cat /proc/meminfo > /cache/environment/proc_meminfo.txt &
    cat /d/ion/heaps/system > /cache/environment/iom_system_heaps.txt &
    df -k > /cache/environment/df.txt &
    ls -l /data/anr > /cache/environment/anr_ls.txt &
    du -h -a /data/system/dropbox > /cache/environment/dropbox_du.txt &
    watchdogfile=`getprop persist.sys.oppo.watchdogtrace`
    #ifdef VENDOR_EDIT
    #Chunbo.Gao@PSW.AD.OppoDebug.LogKit.BugID, 2019/4/23, Add for ...
    cp -rf data/oppo_log/sf/backtrace/* /cache/environment/
    chmod 777 cache/environment/*
    #endif VENDOR_EDIT
    if [ x"$watchdogfile" != x"0" ] && [ x"$watchdogfile" != x"" ]
    then
        chmod 666 $watchdogfile
        cp -rf $watchdogfile /cache/environment/
        setprop persist.sys.oppo.watchdogtrace 0
    fi
    wait
    setprop sys.dumpenvironment.finished 1
    umask 077
}

function CleanAll(){
    rm -rf /cache/admin
    rm -rf /data/core/*
    # rm -rf /data/oppo_log/*
    oppo_log="/data/oppo_log"
    if [ -d  ${oppo_log} ];
    then
        all_logs=`ls ${oppo_log} |grep -v junk_logs`
        for i in ${all_logs};do
        echo ${i}
        if [ -d ${oppo_log}/${i} ] || [ -f ${oppo_log}/${i} ]
        then
        echo "rm -rf ===>"${i}
        rm -rf ${oppo_log}/${i}
        fi
        done
    fi

    #add for TF card begin
    is_tf_card=`ls /mnt/media_rw/ | wc -l`
    tfcard_id=`ls /mnt/media_rw/`
    isSepcial=`getprop SPECIAL_OPPO_CONFIG`
    tf_config=`getprop persist.sys.log.tf`
    if [ "${tf_config}" = "true" ] && [ "$is_tf_card" != "0" ];then
        DATA_LOG_PATH="/mnt/media_rw/${tfcard_id}/oppo_log"
    fi
    oppo_log="${DATA_LOG_PATH}"
    if [ -d  ${oppo_log} ];
    then
        all_logs=`ls ${oppo_log} |grep -v junk_logs`
        for i in ${all_logs};do
        echo ${i}
        #delete all folder or files in ${SDCARD_LOG_BASE_PATH},except these files and folders
        if [ -d ${oppo_log}/${i} ] || [ -f ${oppo_log}/${i} ] && [ ${i} != "diag_logs" ] && [ ${i} != "diag_pid" ] && [ ${i} != "btsnoop_hci" ]
        then
        echo "rm -rf ===>"${i}
        rm -rf ${oppo_log}/${i}
        fi
        done
    fi
    #add for TF card end

    oppo_log="${SDCARD_LOG_BASE_PATH}"
    if [ -d  ${oppo_log} ];
    then
        all_logs=`ls ${oppo_log} |grep -v junk_logs`
        for i in ${all_logs};do
        echo ${i}
        #delete all folder or files in ${SDCARD_LOG_BASE_PATH},except these files and folders
        if [ -d ${oppo_log}/${i} ] || [ -f ${oppo_log}/${i} ] && [ ${i} != "diag_logs" ] && [ ${i} != "diag_pid" ] && [ ${i} != "btsnoop_hci" ]
        then
        echo "rm -rf ===>"${i}
        rm -rf ${oppo_log}/${i}
        fi
        done
    fi
    rm /data/oppo_log/junk_logs/kernel/*
    rm /data/oppo_log/junk_logs/ftrace/*


    is_europe=`getprop ro.oppo.regionmark`
    if [ x"${is_europe}" != x"EUEX" ]; then
        rm ${SDCARD_LOG_BASE_PATH}/junk_logs/kernel/*
        rm ${SDCARD_LOG_BASE_PATH}/junk_logs/ftrace/*
    else
        rm /data/oppo/log/DCS/junk_logs_tmp/kernel/*
        rm /data/oppo/log/DCS/junk_logs_tmp/ftrace/*
    fi

    rm -rf /data/anr/*
    rm -rf /data/tombstones/*
    rm -rf /data/system/dropbox/*
    rm -rf data/vendor/oppo/log/*
    rm -rf /data/misc/bluetooth/logs/*
    setprop sys.clear.finished 1
}

function tranfer(){
    mkdir -p ${SDCARD_LOG_BASE_PATH}
    mkdir -p ${SDCARD_LOG_BASE_PATH}/compress_log
    chmod -R 777 /data/oppo_log/*
    cat /data/oppo_log/log_history.txt >> ${SDCARD_LOG_BASE_PATH}/log_history.txt
    mv /data/oppo_log/transfer_list.txt  ${SDCARD_LOG_BASE_PATH}/transfer_list.txt
    rm -rf /data/oppo_log/log_history.txt
    mkdir -p ${SDCARD_LOG_BASE_PATH}/dropbox
    cp -rf data/system/dropbox/* ${SDCARD_LOG_BASE_PATH}/dropbox/
    chmod  -R  /data/core/*
    mkdir -p ${SDCARD_LOG_BASE_PATH}/core
    mv /data/core/* /data/media/0/oppo_log/core
    # mv /data/oppo_log/* /data/media/0/oppo_log/
    oppo_log="/data/oppo_log"
    if [ -d  ${oppo_log} ];
    then
        all_logs=`ls ${oppo_log} |grep -v junk_logs`
        for i in ${all_logs};do
        echo ${i}
        if [ -d ${oppo_log}/${i} ] || [ -f ${oppo_log}/${i} ]
        then
        echo " mv ===>"${i}
        mv ${oppo_log}/${i} /data/media/0/oppo_log/
        fi
        done
    fi

    if [ -f "/sys/kernel/hypnus/log_state"] && [ -d "/data/oppo_log/junk_logs"]
    then
        mkdir -p ${SDCARD_LOG_BASE_PATH}/junk_logs/kernel
        mkdir -p ${SDCARD_LOG_BASE_PATH}/junk_logs/ftrace
        echo "has /sys/kernel/hypnus/log_state"
        cp /data/oppo_log/junk_logs/kernel/* ${SDCARD_LOG_BASE_PATH}/junk_logs/kernel
        cp /data/oppo_log/junk_logs/ftrace/* ${SDCARD_LOG_BASE_PATH}/junk_logs/ftrace
        kernel_state=1

        while [ $kernel_state -lt 6 ]
        do
            ((kernel_state++))
            echo $kernel_state
            state=`cat /sys/kernel/hypnus/log_state`
            echo " cat /sys/kernel/hypnus/log_state ${state} "
            if [ "${state}" == "0" ]
            then
            rm -rf data/oppo_log/junk_logs/kernel/*
            rm -rf data/oppo_log/junk_logs/ftrace/*
            break
            fi
            sleep 1
            echo " sleep 1"
        done
    fi

    mkdir -p ${SDCARD_LOG_BASE_PATH}/xlog
    mkdir -p ${SDCARD_LOG_BASE_PATH}/sub_xlog
    cp  /sdcard/tencent/MicroMsg/xlog/* ${SDCARD_LOG_BASE_PATH}/xlog/
    cp  /storage/emulated/999/tencent/MicroMsg/xlog/* ${SDCARD_LOG_BASE_PATH}/sub_xlog

    chcon -R u:object_r:media_rw_data_file:s0 /data/media/0/oppo_log/
    chown -R media_rw:media_rw /data/media/0/oppo_log/
    setprop sys.tranfer.finished 1

}

#Chunbo.Gao@PSW.AD.OppoDebug.LogKit.NA, 2019/6/26, Add for bugreport log
function dump_bugreport() {
    mkdir -p  $ROOT_TRIGGER_PATH/bugreport
    echo "bugreport start..."
    bugreport > $ROOT_TRIGGER_PATH/bugreport/bugreport_${CURTIME}.txt
	dmesg > $ROOT_TRIGGER_PATH/dmesg_${CURTIME}.txt
}

function tranfer2TfCard(){
    stoptime=`getprop sys.oppo.log.stoptime`;

    if [ "${tf_config}" = "true" ];then
        is_tf_card=`ls /mnt/media_rw/ | wc -l`
        tfcard_id=`ls /mnt/media_rw/`
        if [ "$is_tf_card" != "0" ];then
            newpath="/mnt/media_rw/${tfcard_id}/oppo_log_all/log@stop@${stoptime}"
            medianewpath="/mnt/media_rw/${tfcard_id}/oppo_log_all/log@stop@${stoptime}"
        fi
    fi

    echo "new path ${stoptime}"
    echo "new path ${newpath}"
    echo "new media path ${medianewpath}"
    mkdir -p ${newpath}
    chmod -R 777 /data/oppo_log/*
    chmod -R 777 ${DATA_LOG_PATH}/*
    cat ${DATA_LOG_PATH}/log_history.txt >> ${newpath}/log_history.txt
    mv ${DATA_LOG_PATH}/transfer_list.txt  ${newpath}/transfer_list.txt
    rm -rf ${DATA_LOG_PATH}/log_history.txt
    mkdir -p ${newpath}/dropbox
    cp -rf data/system/dropbox/* ${newpath}/dropbox/
    cp /data/system/critical_event.log ${newpath}/dropbox/
    rm -rf `find data/system/dropbox -type f`
    setprop sys.tranfer.finished mv:dropbox
    tar -cvf ${newpath}/log.tar data/oppo/log/*
    setprop sys.tranfer.finished mv:log
    chmod  -R 777  /data/core/*
    mkdir -p ${newpath}/core
    mv /data/core/* ${medianewpath}/core
    mv ${SDCARD_LOG_BASE_PATH}/pcm_dump ${newpath}/
    mv ${SDCARD_LOG_BASE_PATH}/camera_monkey_log ${newpath}/
    mkdir -p ${newpath}/btsnoop_hci
    cp -rf /data/misc/bluetooth/logs/ ${newpath}/btsnoop_hci/
    setprop sys.tranfer.finished cp:btsnoop_hci
    # before mv /data/oppo_log, wait for dumpmeminfo done
    count=0
    timeSub=`getprop persist.sys.com.oppo.debug.time`

    outputPathStop="${DATA_LOG_PATH}/${timeSub}/SI_stop/"
    touch ${SDCARD_LOG_BASE_PATH}/test
    echo ${outputPathStop} >> ${SDCARD_LOG_BASE_PATH}/test
    while [ $count -le 30 ] && [ ! -f ${outputPathStop}/wechat/finish_weixin ];do
        echo "hello" >> ${SDCARD_LOG_BASE_PATH}/test
        echo $outputPathStop >> ${SDCARD_LOG_BASE_PATH}/test
        echo $count >> ${SDCARD_LOG_BASE_PATH}/test
        count=$((count + 1))
        sleep 1
    done
    setprop sys.tranfer.finished count:finish_weixin
    rm -f ${SDCARD_LOG_BASE_PATH}/test
    # mv ${DATA_LOG_PATH}/* /data/media/0/oppo_log/
    oppo_log="${DATA_LOG_PATH}"
    if [ -d  ${oppo_log} ];
    then
        all_logs=`ls ${oppo_log} |grep -v junk_logs`
        for i in ${all_logs};do
        echo ${i}
        if [ -d ${oppo_log}/${i} ] || [ -f ${oppo_log}/${i} ]
        then
        echo " mv ===>"${i}
        mv ${oppo_log}/${i} ${medianewpath}/
        fi
        done
    fi
    setprop sys.tranfer.finished cp:medianewpath
    if [ -f "/sys/kernel/hypnus/log_state" ] && [ -d "/data/oppo_log/junk_logs" ]
    then
        mkdir -p ${newpath}/junk_logs/kernel
        mkdir -p ${newpath}/junk_logs/ftrace
        echo "has /sys/kernel/hypnus/log_state"
        cp /data/oppo_log/junk_logs/kernel/* ${newpath}/junk_logs/kernel
        cp /data/oppo_log/junk_logs/ftrace/* ${newpath}/junk_logs/ftrace
        kernel_state=1

        while [ $kernel_state -lt 6 ]
        do
            ((kernel_state++))
            echo $kernel_state
            state=`cat /sys/kernel/hypnus/log_state`
            echo " cat /sys/kernel/hypnus/log_state ${state} "
            if [ "${state}" == "0" ]
            then
            rm -rf data/oppo_log/junk_logs/kernel/*
            rm -rf data/oppo_log/junk_logs/ftrace/*
            break
            fi
            sleep 1
            echo " sleep 1"
        done
        setprop sys.tranfer.finished cp:junk_logs
    fi

    #Chunbo.Gao@PSW.AD.OppoLog.NA, 2020/01/17, Add for copy weixin xlog
    copyWeixinXlog

    mv /data/oppo/log/modem_log/config/ ${SDCARD_LOG_BASE_PATH}/diag_logs/
    mv ${SDCARD_LOG_BASE_PATH}/diag_logs ${newpath}/

    #Chunbo.Gao@PSW.AD.OppoDebug.LogKit.NA, 2019/6/21, Add for thermalrec log
    dumpsys batterystats --thermalrec
    thermalrec_dir="/data/system/thermal/dcs"
    thermalstats_file="/data/system/thermalstats.bin"
    mkdir -p ${newpath}/power/thermalrec/
    if [ -f ${thermalstats_file} ];then
        cp -rf /data/system/thermalstats.bin ${newpath}/power/thermalrec/
    fi
    if [ -d ${thermalrec_dir} ]; then
        echo "copy Thermalrec..."
        cp -rf /data/system/thermal/dcs/* ${newpath}/power/thermalrec/
    fi
    #Chunbo.Gao@PSW.AD.OppoDebug.LogKit.NA, 2019/7/24, Add for powermonitor log
    powermonitor_dir="/data/oppo/psw/powermonitor"
    if [ -d ${powermonitor_dir} ]; then
        echo "copy Powermonitor..."
        mkdir -p ${newpath}/power/powermonitor/
        cp -rf /data/oppo/psw/powermonitor/* ${newpath}/power/powermonitor/
    fi

    #Chunbo.Gao@PSW.AD.OppoDebug.LogKit.NA, 2019/6/21, Add for baidu ime log
    baidu_ime_dir="/sdcard/baidu/ime"
    if [ -d ${baidu_ime_dir} ]; then
        echo "copy BaiduIme..."
        cp -rf /sdcard/baidu/ime ${newpath}/
    fi
    setprop sys.tranfer.finished cp:xxx_dir

    mkdir -p ${newpath}/faceunlock
    mv /data/vendor_de/0/faceunlock/* ${newpath}/faceunlock
    mv ${SDCARD_LOG_BASE_PATH}/storage/ ${medianewpath}/
    mv ${SDCARD_LOG_BASE_PATH}/trigger ${medianewpath}/
    mkdir -p ${newpath}/fingerprint_pic
    mkdir -p ${newpath}/fingerprint_pic/persist_silead
    mkdir -p ${newpath}/fingerprint_pic/optical_fingerprint
    mkdir -p ${newpath}/fingerprint_pic/fingerprint
    mv /data/system/silead/* ${newpath}/fingerprint_pic
    cp -rf /persist/silead/* ${newpath}/fingerprint_pic/persist_silead
    mv /data/vendor/optical_fingerprint/* ${newpath}/fingerprint_pic/optical_fingerprint
    mv /data/vendor/fingerprint/* ${newpath}/fingerprint_pic/fingerprint
    mkdir -p ${medianewpath}/os/TraceLog/colorOS
    cp /storage/emulated/0/ColorOS/TraceLog/trace_*.csv ${medianewpath}/os/TraceLog/colorOS/
    cp /storage/emulated/0/Documents/TraceLog/trace_*.csv ${medianewpath}/os/TraceLog/
    mv ${SDCARD_LOG_BASE_PATH}/LayerDump/ ${newpath}/
    chcon -R u:object_r:media_rw_data_file:s0 /data/media/0/oppo_log/
    chown -R media_rw:media_rw /data/media/0/oppo_log/

    curFile=${SDCARD_LOG_BASE_PATH}/screen_record
    if [ -d "$curFile" ]; then
         mv $curFile ${newpath}/
    fi
    #mv /sdcard/.oppologkit/temp_log_config.xml ${newpath}/
    cp /data/oppo/log/temp_log_config.xml ${newpath}/
    mkdir -p ${newpath}/tombstones/
    cp /data/tombstones/tombstone* ${newpath}/tombstones/
    setprop sys.tranfer.finished cp:tombstone
    MAX_NUM=5
    is_release=`getprop ro.build.release_type`
    if [ x"${is_release}" != x"true" ]; then
        #ifdef VENDOR_EDIT
        #Zhiming.chen@PSW.AD.OppoLog.BugID 2724830, 2019/12/17,The log tool captures child user screenshots
        ALL_USER=`ls -t storage/emulated/`
        for m in $ALL_USER;
        do
            IDX=0
            screen_shot="/storage/emulated/$m/DCIM/Screenshots/"
            if [ -d "$screen_shot" ]; then
                mkdir -p ${newpath}/Screenshots/$m
                touch ${newpath}/Screenshots/$m/.nomedia
                ALL_FILE=`ls -t $screen_shot`
                for i in $ALL_FILE;
                do
                    echo "now we have file $i"
                    let IDX=$IDX+1;
                    echo ========file num is $IDX===========
                    if [ "$IDX" -lt $MAX_NUM ] ; then
                       echo  $i\!;
                       cp $screen_shot/$i ${newpath}/Screenshots/$m/
                    fi
                done
            fi
        done
        #endif /* VENDOR_EDIT */
    fi
    setprop sys.tranfer.finished cp:Screenshots
    pmlog=data/oppo/psw/powermonitor_backup/
    if [ -d "$pmlog" ]; then
        mkdir -p ${newpath}/powermonitor_backup
        cp -r data/oppo/psw/powermonitor_backup/* ${newpath}/powermonitor_backup/
    fi
    systrace=${SDCARD_LOG_BASE_PATH}/systrace
    if [ -d "$systrace" ]; then
        mv ${systrace} ${newpath}/
    fi
    #get proc/dellog
    cat proc/dellog > ${newpath}/proc_dellog.txt
    mkdir -p ${newpath}/vendor_logs/wifi
    cp -r data/vendor/wifi/logs/* ${newpath}/vendor_logs/wifi
    cp -r data/vendor/oppo/log/*  ${newpath}/vendor_logs/
    rm -rf data/vendor/wifi/logs/*
    rm -rf data/vendor/oppo/log/*
    setprop sys.tranfer.finished cp:wifi

    #===================os app start=================
    #Browser
    mkdir -p ${newpath}/os/Browser
    cp -rf sdcard/Coloros/Browser/.log/* ${newpath}/os/Browser/
    #Chunbo.Gao@PSW.AD.OppoDebug.LogKit.NA, 2019/7/24, Add for Wallet log
    mkdir -p ${newpath}/os/Wallet
    cp -rf /sdcard/ColorOS/Wallet/.dog/* ${newpath}/os/Wallet/
    #assistantscreen
    assistantscreenlog=/sdcard/Download/AppmonitorSDKLogs/com.coloros.assistantscreen
    if [ -d "$assistantscreenlog" ]; then
        mkdir -p ${newpath}/os/Assistantscreen
        cp -rf ${assistantscreenlog}/* ${newpath}/os/Assistantscreen/
    fi

    #ovoicemanager
    ovoicemanagerlog=/sdcard/Android/data/com.oppo.ovoicemanager/files
    if [ -d "$ovoicemanagerlog" ]; then
        mkdir -p ${newpath}/os/ovoicemanager
        cp -rf ${ovoicemanagerlog}/* ${newpath}/os/ovoicemanager/
    fi

    internalOVMSAudio=/data/data/com.oppo.ovoicemanager/files/ovmsAudio
    if [ -d "$internalOVMSAudio" ]; then
        mkdir -p ${newpath}/os/internalOVMSAudio
        cp -rf ${internalOVMSAudio}/* ${newpath}/os/internalOVMSAudio/
    fi

    OVMS_Aispeechlog=/sdcard/OVMS_Aispeech
    if [ -d "$OVMS_Aispeechlog" ]; then
        mkdir -p ${newpath}/os/OVMS_Aispeech
        cp -rf ${OVMS_Aispeechlog}/* ${newpath}/os/OVMS_Aispeech/
    fi

    OVMS_Recordinglog=/sdcard/OVMS_Recording
    if [ -d "$OVMS_Recordinglog" ]; then
        mkdir -p ${newpath}/os/OVMS_Recording
        cp -rf ${OVMS_Recordinglog}/* ${newpath}/os/OVMS_Recording/
    fi
    #===================os app end=================

    #===================dump log start=================
    # cp bluetooth ramdump
    bluetooth_ramdump=/data/vendor/ramdump/bluetooth
    if [ -d "$bluetooth_ramdump" ]; then
        mkdir -p ${newpath}/dumplog/bluetooth_ramdump
        chmod 666 -R data/vendor/ramdump/bluetooth/*
        cp -rf ${bluetooth_ramdump}/* ${newpath}/dumplog/bluetooth_ramdump/
    fi
    #cp /data/vendor/ssrdump
    ssrdump=/data/vendor/ssrdump
    if [ -d "$ssrdump" ]; then
        mkdir -p ${newpath}/dumplog/ssrdump
        chmod 666 -R data/vendor/ssrdump/*
        cp -rf ${ssrdump}/* ${newpath}/dumplog/ssrdump/
    fi
    #cp adsp dump
    adsp_dump=/data/vendor/mmdump/adsp
    adsp_dump_enable=`getprop persist.sys.adsp_dump.switch`
    if [ "$adsp_dump_enable" == "true" ] && [ -d "$adsp_dump" ]; then
        mkdir -p ${newpath}/dumplog/adsp_dump
        chmod 666 -R data/vendor/mmdump/adsp/*
        cp -rf ${adsp_dump}/* ${newpath}/dumplog/adsp_dump/
    fi
    #===================dump log end=================

    #kevin.li@ROM.Framework, 2019/11/5, add for hans freeze manager(for protection)
    hans_enable=`getprop persist.sys.enable.hans`
    if [ "$hans_enable" == "true" ]; then
         mkdir -p ${newpath}/hans/
         dumpsys activity hans history > ${newpath}/hans/hans_history.txt
    fi
    #kevin.li@ROM.Framework, 2019/12/2, add for hans cts property
    hans_enable=`getprop persist.vendor.enable.hans`
    if [ "$hans_enable" == "true" ]; then
         mkdir -p ${newpath}/hans/
         dumpsys activity hans history > ${newpath}/hans/hans_history.txt
    fi

    #chao.zhu@ROM.Framework, 2020/04/17, add for preload
    preload_enable=`getprop persist.vendor.enable.preload`
    if [ "$preload_enable" == "true" ]; then
        mkdir -p ${newpath}/preload/
        dumpsys activity preload > ${newpath}/preload/preload.txt
    fi

    #cp /data/system/users/0
    mkdir -p ${newpath}/user_0
    touch ${newpath}/user_0/.nomedia
    cp -rf data/system/users/0/* ${newpath}/user_0/
    setprop sys.tranfer.finished 1
}

#Chunbo.Gao@PSW.AD.OppoLog.NA, 2020/01/17, Add for copy weixin xlog
function copyWeixinXlog(){
    stoptime=`getprop sys.oppo.log.stoptime`;
    newpath="${SDCARD_LOG_BASE_PATH}/log@stop@${stoptime}"
    saveallxlog=`getprop sys.oppo.log.save_all_xlog`
    argtrue='true'
    XLOG_MAX_NUM=20
    XLOG_IDX=0
    XLOG_DIR="/data/data/com.tencent.mm/files/xlog"
    CRASH_DIR="/data/data/com.tencent.mm/files/crash"
    XLOG_ANDDIR="/sdcard/Android/data/com.tencent.mm/MicroMsg/xlog"
    CRASH_ANDDIR="/sdcard/Android/data/com.tencent.mm/MicroMsg/crash"
    mkdir -p ${newpath}/wechatlog
    if [ "${saveallxlog}" = "${argtrue}" ]; then
        mkdir -p ${newpath}/wechatlog/xlog
        if [ -d "${XLOG_DIR}" ]; then
            cp -rf ${XLOG_DIR}/*.xlog ${newpath}/wechatlog/xlog/
        fi
        if [ -d "${XLOG_ANDDIR}" ]; then
            cp -rf ${XLOG_ANDDIR}/*.xlog ${newpath}/wechatlog/xlog/
        fi
    else
        if [ -d "${XLOG_DIR}" ]; then
            mkdir -p ${newpath}/wechatlog/xlog
            ALL_FILE=`find ${XLOG_DIR} -iname '*.xlog' | xargs ls -t`
            for i in $ALL_FILE;
            do
                echo "now we have Xlog file $i"
                let XLOG_IDX=$XLOG_IDX+1;
                echo ========file num is $XLOG_IDX===========
                if [ "$XLOG_IDX" -lt $XLOG_MAX_NUM ] ; then
                    #echo  $i >> ${newpath}/xlog/.xlog.txt
                    cp $i ${newpath}/wechatlog/xlog/
                fi
            done
        fi
        if [ -d "${XLOG_ANDDIR}" ]; then
            mkdir -p ${newpath}/wechatlog/xlog
            ALL_FILE=`find ${XLOG_ANDDIR} -iname '*.xlog' | xargs ls -t`
            for i in $ALL_FILE;
            do
                echo "now we have Xlog file $i"
                let XLOG_IDX=$XLOG_IDX+1;
                echo ========file num is $XLOG_IDX===========
                if [ "$XLOG_IDX" -lt $XLOG_MAX_NUM ] ; then
                    #echo  $i >> ${newpath}/xlog/.xlog.txt
                    cp $i ${newpath}/wechatlog/xlog/
                fi
            done
        fi
    fi
    setprop sys.tranfer.finished cp:xlog
    mkdir -p ${newpath}/wechatlog/crash
    if [ -d "${CRASH_DIR}" ]; then
            cp -rf ${CRASH_DIR}/* ${newpath}/wechatlog/crash/
    fi
    if [ -d "${CRASH_ANDDIR}" ]; then
            cp -rf ${CRASH_ANDDIR}/* ${newpath}/wechatlog/crash/
    fi

    XLOG_IDX=0
    if [ "${saveallxlog}" = "${argtrue}" ]; then
        mkdir -p ${newpath}/sub_xlog
        cp -rf /storage/emulated/999/tencent/MicroMsg/xlog/* ${newpath}/sub_xlog
    else
        if [ -d "/storage/emulated/999/tencent/MicroMsg/xlog" ]; then
            mkdir -p ${newpath}/sub_xlog
            ALL_FILE=`ls -t /storage/emulated/999/tencent/MicroMsg/xlog`
            for i in $ALL_FILE;
            do
                echo "now we have subXlog file $i"
                let XLOG_IDX=$XLOG_IDX+1;
                echo ========file num is $XLOG_IDX===========
                if [ "$XLOG_IDX" -lt $XLOG_MAX_NUM ] ; then
                   echo  $i\!;
                    cp  /storage/emulated/999/tencent/MicroMsg/xlog/$i ${newpath}/sub_xlog
                fi
            done
        fi
    fi
    setprop sys.tranfer.finished cp:sub_xlog
}


# service user set to system,group sdcard_rw
function tranferUser(){
    stoptime=`getprop sys.oppo.log.stoptime`;
    userpath="${SDCARD_LOG_BASE_PATH}/log@stop@${stoptime}"

    echo "$(date +%F-%H:%M:%S) user:start...." >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
    mkdir -p ${userpath}/user_0
    touch ${userpath}/user_0/.nomedia
    cp -rf data/system/users/0/* ${userpath}/user_0/
    wait
    echo "$(date +%F-%H:%M:%S) user:done...." >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
}

function transferIoMonitor(){
    IOMONITOR_PATH=${newpath}/IoMonitor
    mkdir -p ${IOMONITOR_PATH}
    cat /proc/IoMonitor/daily > ${IOMONITOR_PATH}/IoMonitor_daily.txt
    cat /proc/IoMonitor/uid_io_show > ${IOMONITOR_PATH}/IoMonitor_uid_io_show.txt
}

function tranferDump(){

    # diag logs
    #mv /data/oppo/log/modem_log/config/ ${SDCARD_LOG_BASE_PATH}/diag_logs/
    mv ${SDCARD_LOG_BASE_PATH}/diag_logs ${newpath}/
    if [ -f data/vendor/oppo/log/device_log/config/Diag.cfg ]; then
        mkdir -p ${newpath}/diag_logs
        mv data/vendor/oppo/log/device_log/config/* ${newpath}/diag_logs
        mv data/vendor/oppo/log/device_log/diag_logs/* ${newpath}/diag_logs
    fi

    # cp bluetooth ramdump
    bluetooth_ramdump=/data/vendor/ramdump/bluetooth
    if [ -d "$bluetooth_ramdump" ]; then
        mkdir -p ${newpath}/dumplog/bluetooth_ramdump
        chmod 666 -R data/vendor/ramdump/bluetooth/*
        cp -rf ${bluetooth_ramdump}/* ${newpath}/dumplog/bluetooth_ramdump/
    fi
    #cp /data/vendor/ssrdump
    ssrdump=/data/vendor/ssrdump
    if [ -d "$ssrdump" ]; then
        mkdir -p ${newpath}/dumplog/ssrdump
        chmod 666 -R data/vendor/ssrdump/*
        cp -rf ${ssrdump}/* ${newpath}/dumplog/ssrdump/
    fi
    #cp adsp dump
    adsp_dump=/data/vendor/mmdump/adsp
    adsp_dump_enable=`getprop persist.sys.adsp_dump.switch`
    if [ "$adsp_dump_enable" == "true" ] && [ -d "$adsp_dump" ]; then
        mkdir -p ${newpath}/dumplog/adsp_dump
        chmod 666 -R data/vendor/mmdump/adsp/*
        cp -rf ${adsp_dump}/* ${newpath}/dumplog/adsp_dump/
    fi

    #wifi log
    tranferWifi
    echo "$(date +%F-%H:%M:%S) tranfer2SDCard:copy dump done" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
}

function tranferWifi(){
    #P wifi log
    mkdir -p ${newpath}/vendor_logs/wifi
    chmod 770 /data/vendor/wifi/logs/*
    cp -r /data/vendor/wifi/logs/* ${newpath}/vendor_logs/wifi
    rm -rf data/vendor/wifi/logs/*
}

function tranferScreenshots(){
    MAX_NUM=5
    is_release=`getprop ro.build.release_type`
    if [ x"${is_release}" != x"true" ]; then
        #ifdef VENDOR_EDIT
        #Zhiming.chen@PSW.AD.OppoLog.BugID 2724830, 2019/12/17,The log tool captures child user screenshots
        ALL_USER=`ls -t storage/emulated/`
        for m in $ALL_USER;
        do
            IDX=0
            screen_shot="/storage/emulated/$m/DCIM/Screenshots/"
            if [ -d "$screen_shot" ]; then
                mkdir -p ${newpath}/Screenshots/$m
                touch ${newpath}/Screenshots/$m/.nomedia
                ALL_FILE=`ls -t $screen_shot`
                for i in $ALL_FILE;
                do
                    echo "now we have file $i"
                    let IDX=$IDX+1;
                    echo ========file num is $IDX===========
                    if [ "$IDX" -lt $MAX_NUM ] ; then
                       echo  $i\!;
                       cp $screen_shot/$i ${newpath}/Screenshots/$m/
                    fi
                done
            fi
        done
        #endif /* VENDOR_EDIT */
    fi
    echo "$(date +%F-%H:%M:%S) tranfer2SDCard:copy screenshots done" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
}

function tranfeColorOS(){
    #TraceLog
    mkdir -p ${newpath}/os/TraceLog/colorOS
    cp /sdcard/ColorOS/TraceLog/trace_*.csv ${newpath}/os/TraceLog/colorOS/
    cp /sdcard/Documents/TraceLog/trace_*.csv ${newpath}/os/TraceLog/

    #Browser
    mkdir -p ${newpath}/os/Browser
    cp -rf sdcard/Coloros/Browser/.log/* ${newpath}/os/Browser/
    #Wallet log
    mkdir -p ${newpath}/os/Wallet
    cp -rf /sdcard/ColorOS/Wallet/.dog/* ${newpath}/os/Wallet/
    #assistantscreen
    assistantscreenlog=/sdcard/Download/AppmonitorSDKLogs/com.coloros.assistantscreen
    if [ -d "$assistantscreenlog" ]; then
        mkdir -p ${newpath}/os/Assistantscreen
        cp -rf ${assistantscreenlog}/* ${newpath}/os/Assistantscreen/
    fi

    #ovoicemanager
    ovoicemanagerlog=/sdcard/Android/data/com.oppo.ovoicemanager/files
    if [ -d "$ovoicemanagerlog" ]; then
        mkdir -p ${newpath}/os/ovoicemanager
        cp -rf ${ovoicemanagerlog}/* ${newpath}/os/ovoicemanager/
    fi

    internalOVMSAudio=/data/data/com.oppo.ovoicemanager/files/ovmsAudio
    if [ -d "$internalOVMSAudio" ]; then
        mkdir -p ${newpath}/os/internalOVMSAudio
        cp -rf ${internalOVMSAudio}/* ${newpath}/os/internalOVMSAudio/
    fi

    OVMS_Aispeechlog=/sdcard/OVMS_Aispeech
    if [ -d "$OVMS_Aispeechlog" ]; then
        mkdir -p ${newpath}/os/OVMS_Aispeech
        cp -rf ${OVMS_Aispeechlog}/* ${newpath}/os/OVMS_Aispeech/
    fi

    OVMS_Recordinglog=/sdcard/OVMS_Recording
    if [ -d "$OVMS_Recordinglog" ]; then
        mkdir -p ${newpath}/os/OVMS_Recording
        cp -rf ${OVMS_Recordinglog}/* ${newpath}/os/OVMS_Recording/
    fi

    #common path
    cp /sdcard/Documents/*/.dog/* ${newpath}/os/
    echo "$(date +%F-%H:%M:%S) tranfer2SDCard:copy colorOS done" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
}

function tranferFingerprint(){
    mkdir -p ${newpath}/faceunlock
    mv /data/vendor_de/0/faceunlock/* ${newpath}/faceunlock
    mkdir -p ${newpath}/fingerprint_pic
    mkdir -p ${newpath}/fingerprint_pic/persist_silead
    mkdir -p ${newpath}/fingerprint_pic/optical_fingerprint
    mkdir -p ${newpath}/fingerprint_pic/fingerprint
    mv /data/system/silead/* ${newpath}/fingerprint_pic
    cp -rf /persist/silead/* ${newpath}/fingerprint_pic/persist_silead
    mv /data/vendor/optical_fingerprint/* ${newpath}/fingerprint_pic/optical_fingerprint
    mv /data/vendor/fingerprint/* ${newpath}/fingerprint_pic/fingerprint
    echo "$(date +%F-%H:%M:%S) tranfer2SDCard:copy fingerprint done" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
}

function tranferThirdApp(){
    #Chunbo.Gao@PSW.AD.OppoDebug.LogKit.NA, 2019/6/21, Add for baidu ime log
    baidu_ime_dir="/sdcard/baidu/ime"
    if [ -d ${baidu_ime_dir} ]; then
        echo "copy BaiduIme..."
        cp -rf /sdcard/baidu/ime ${newpath}/
    fi

    #Chunbo.Gao@PSW.AD.OppoDebug.LogKit.NA, 2019/6/21, Add for tencent.ig
    tencent_pubgmhd_dir="/sdcard/Android/data/com.tencent.tmgp.pubgmhd/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Logs"
    if [ -d ${tencent_pubgmhd_dir} ]; then
        mkdir -p ${newpath}/os/Tencentlogs/pubgmhd
        echo "copy tencent.pubgmhd..."
        cp -rf ${tencent_pubgmhd_dir} ${newpath}/os/Tencentlogs/pubgmhd
    fi
    echo "$(date +%F-%H:%M:%S) tranfer2SDCard:copy third app done" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
}

function tranferPower(){
    #Chunbo.Gao@PSW.AD.OppoDebug.LogKit.NA, 2019/6/21, Add for thermalrec log
    dumpsys batterystats --thermalrec
    thermalrec_dir="/data/system/thermal/dcs"
    thermalstats_file="/data/system/thermalstats.bin"
    mkdir -p ${newpath}/power/thermalrec/
    if [ -f ${thermalstats_file} ];then
        chmod 770 /data/system/thermalstats.bin
		cp -rf /data/system/thermalstats.bin ${newpath}/power/thermalrec/
    fi
    if [ -d ${thermalrec_dir} ]; then
        echo "copy Thermalrec..."
		chmod 770 /data/system/thermal/ -R
        cp -rf ${thermalrec_dir}/* ${newpath}/power/thermalrec/
    fi

    #Chunbo.Gao@PSW.AD.OppoDebug.LogKit.NA, 2019/7/24, Add for powermonitor log
    powermonitor_dir="/data/oppo/psw/powermonitor"
    if [ -d ${powermonitor_dir} ]; then
        echo "copy Powermonitor..."
        mkdir -p ${newpath}/power/powermonitor/
		chmod 770 ${powermonitor_dir} -R
        cp -rf ${powermonitor_dir}/* ${newpath}/power/powermonitor/
    fi

    pmlog=data/oppo/psw/powermonitor_backup/
    if [ -d "$pmlog" ]; then
        mkdir -p ${newpath}/powermonitor_backup
        cp -r data/oppo/psw/powermonitor_backup/* ${newpath}/powermonitor_backup/
    fi
    echo "$(date +%F-%H:%M:%S) tranfer2SDCard:copy power done" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
}

function tranfer2SDCard(){
    stoptime=`getprop sys.oppo.log.stoptime`;
    echo "$(date +%F-%H:%M:%S) tranfer2SDCard:start...." >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
    newpath="${SDCARD_LOG_BASE_PATH}/log@stop@${stoptime}"
    echo "new path ${stoptime}"
    echo "new path ${newpath}"
    echo "$(date +%F-%H:%M:%S) tranfer2SDCard:${newpath}" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
    mkdir -p ${newpath}

    chmod -R 777 /data/oppo_log/*
    chmod -R 777 ${DATA_LOG_PATH}/*
    echo "$(date +%F-%H:%M:%S) tranfer2SDCard:${DATA_LOG_PATH}" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
    cat ${DATA_LOG_PATH}/log_history.txt >> ${newpath}/log_history.txt
    mv ${DATA_LOG_PATH}/transfer_list.txt  ${newpath}/transfer_list.txt
    rm -rf ${DATA_LOG_PATH}/log_history.txt

    mkdir -p ${newpath}/dropbox
    cp -rf data/system/dropbox/* ${newpath}/dropbox/
    cp /data/system/critical_event.log ${newpath}/dropbox/
    rm -rf `find data/system/dropbox -type f`
    setprop sys.tranfer.finished mv:dropbox

    echo "$(date +%F-%H:%M:%S) tranfer2SDCard:cp LOG start" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
    chmod 770 /data/oppo/log/ -R
    tar -czvf ${newpath}/LOG.dat.gz -C /data/oppo/log .
    echo "$(date +%F-%H:%M:%S) tranfer2SDCard:cp LOG done" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
    setprop sys.tranfer.finished mv:log

    chmod  -R 777  /data/core/*
    mkdir -p ${newpath}/core
    mv /data/core/* ${newpath}/core
    mv ${SDCARD_LOG_BASE_PATH}/pcm_dump ${newpath}/
    mv ${SDCARD_LOG_BASE_PATH}/camera_monkey_log ${newpath}/
    mkdir -p ${newpath}/btsnoop_hci
    cp -rf /data/misc/bluetooth/logs/ ${newpath}/btsnoop_hci/
    setprop sys.tranfer.finished cp:btsnoop_hci

    # before mv /data/oppo_log, wait for dumpmeminfo done
    count=0
    timeSub=`getprop persist.sys.com.oppo.debug.time`
    outputPathStop="${DATA_LOG_PATH}/${timeSub}/SI_stop/"
    while [ $count -le 30 ] && [ ! -f ${outputPathStop}/finish_system ];do
        echo "$(date +%F-%H:%M:%S) tranfer2SDCard:count=$count" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
        count=$((count + 1))
        sleep 1
    done
    setprop sys.tranfer.finished count:finish_system

    oppo_log="${DATA_LOG_PATH}"
    if [ -d  ${oppo_log} ];
    then
        echo "$(date +%F-%H:%M:%S) tranfer2SDCard:${oppo_log}" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
        all_logs=`ls ${oppo_log} |grep -v junk_logs`
        for i in ${all_logs};do
        echo ${i}
        if [ -d ${oppo_log}/${i} ] || [ -f ${oppo_log}/${i} ]
        then
        echo " cp ===>"${i}
        echo " cp ${oppo_log}/${i} ${newpath}/"
        echo "$(date +%F-%H:%M:%S) tranfer2SDCard:cp ${oppo_log}/${i} ${newpath}/" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
        cp -R  ${oppo_log}/${i} ${newpath}/
        rm -rf ${oppo_log}/${i}
        fi
        done
        echo "$(date +%F-%H:%M:%S) tranfer2SDCard:cp ${oppo_log} done" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
    fi
    setprop sys.tranfer.finished cp:oppo_log

    #user
    tranferUser

    #Chunbo.Gao@PSW.AD.OppoLog.NA, 2020/01/17, Add for copy weixin xlog
    copyWeixinXlog
    echo "$(date +%F-%H:%M:%S) tranfer2SDCard:copy wechat Xlog done" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info

    #copy thermalrec and powermonitor log
    tranferPower

    #copy third-app log
    tranferThirdApp
    #setprop sys.tranfer.finished cp:xxx_dir

    #Chunbo.Gao@PSW.AD.OppoDebug.LogKit.NA, 2019/09/03, Add for binder_info log
    binder_info_dir="${SDCARD_LOG_BASE_PATH}/binder_info"
    if [ -d ${binder_info_dir} ]; then
        echo "copy binder_info..."
        mv ${SDCARD_LOG_BASE_PATH}/binder_info ${newpath}/
    fi

    #Yujie.Long@PSW.AD.OppoLog.NA, 2020/02/21, Add for save recovery log
    mkdir -p ${newpath}/recovery_log
    cp -rf /cache/recovery/* ${newpath}/recovery_log/

    #copy fingerprint log
    tranferFingerprint

    mv ${SDCARD_LOG_BASE_PATH}/storage/ ${newpath}/
    mv ${SDCARD_LOG_BASE_PATH}/trigger ${newpath}/

    mv ${SDCARD_LOG_BASE_PATH}/LayerDump/ ${newpath}/
    chcon -R u:object_r:media_rw_data_file:s0 /data/media/0/oppo_log/
    chown -R media_rw:media_rw /data/media/0/oppo_log/

    #screen_record
    curFile=${SDCARD_LOG_BASE_PATH}/screen_record
    if [ -d "$curFile" ]; then
         mv $curFile ${newpath}/
    fi
    echo "$(date +%F-%H:%M:%S) tranfer2SDCard:copy screen_record done" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info

    cp /data/oppo/log/temp_log_config.xml ${newpath}/

    mkdir -p ${newpath}/tombstones/
    cp /data/tombstones/tombstone* ${newpath}/tombstones/
    setprop sys.tranfer.finished cp:tombstone

    #screen_record
    tranferScreenshots

    #systrace
    systrace=${SDCARD_LOG_BASE_PATH}/systrace
    if [ -d "$systrace" ]; then
        mv ${systrace} ${newpath}/
    fi

    #get proc/dellog
    cat proc/dellog > ${newpath}/proc_dellog.txt

    #os app
    tranfeColorOS

    #dump log
    tranferDump

    #IoMonitor
    transferIoMonitor
    setprop sys.tranfer.finished 1
    echo "$(date +%F-%H:%M:%S) tranfer2SDCard:done...." >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
}
##add for log kit 2 begin
function tranfer2(){
    echo "$(date +%F-%H:%M:%S) tranfer2:start...." >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info

    tf_config=`getprop persist.sys.log.tf`
    is_aging_test=`getprop SPECIAL_OPPO_CONFIG`
    is_low_memeory=`getprop ro.config.oppo.low_ram`
    systemSatus="SI_stop"

    getSystemStatus

    if [ x"${tf_config}" = x"true" ] && [ x"${is_low_memeory}" = x"true" ]; then
        is_tf_card=`ls /mnt/media_rw/ | wc -l`
        tfcard_id=`ls /mnt/media_rw/`
        if [ "$is_tf_card" != "0" ];then
            tranfer2TfCard
        else
            tranfer2SDCard
        fi
    else
        tranfer2SDCard
    fi
    echo "$(date +%F-%H:%M:%S) tranfer2:done...." >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
    mv ${SDCARD_LOG_BASE_PATH}/tranfer2.info ${newpath}/
}

function calculateLogSize(){
    LogSize1=0
    LogSize2=0
    LogSizeDiag=0
    if [ -d "${DATA_LOG_PATH}" ]; then
        LogSize1=`du -s -k ${DATA_LOG_PATH} | $XKIT awk '{print $1}'`
    fi

    if [ -d ${SDCARD_LOG_BASE_PATH}/diag_logs ]; then
        LogSize2=`du -s -k ${SDCARD_LOG_BASE_PATH}/diag_logs | $XKIT awk '{print $1}'`
    fi

    if [ -d data/vendor/oppo/log/device_log/diag_logs ]; then
        LogSizeDiag=`du -s -k data/vendor/oppo/log/device_log/diag_logs | $XKIT awk '{print $1}'`
    fi
    LogSize3=`expr $LogSize1 + $LogSize2 + $LogSizeDiag`
    echo "data : ${LogSize1}"
    echo "diag : ${LogSize2}"
    setprop sys.calcute.logsize ${LogSize3}
    setprop sys.calcute.finished 1
}

function calculateFolderSize() {
    folderSize=0
    folder=`getprop sys.oppo.log.folder`
    if [ -d "${folder}" ]; then
        folderSize=`du -s -k ${folder} | $XKIT awk '{print $1}'`
    fi
    echo "${folder} : ${folderSize}"
    setprop sys.oppo.log.foldersize ${folderSize}
}

function deleteFolder() {
    title=`getprop sys.oppo.log.deletepath.title`;
    logstoptime=`getprop sys.oppo.log.deletepath.stoptime`;
    newpath="${SDCARD_LOG_BASE_PATH}/${title}@stop@${logstoptime}";
    echo ${newpath}
    rm -rf ${newpath}
    setprop sys.clear.finished 1
}

function deleteOrigin() {
    stoptime=`getprop sys.oppo.log.stoptime`;
    newpath="${SDCARD_LOG_BASE_PATH}/log@stop@${stoptime}"
    rm -rf ${newpath}
    setprop sys.oppo.log.deleted 1
}

function initLogPath2() {
    FreeSize=`df /data | grep /data | $XKIT awk '{print $4}'`
    echo "df /data FreeSize is ${FreeSize}"
    GSIZE=`echo | $XKIT awk '{printf("%d",2*1024*1024)}'`
    echo "$(date +%F-%H:%M:%S) init:data FreeSize:${FreeSize} and GSIZE:${GSIZE}" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
    tmpMain=`getprop persist.sys.log.main`
    tmpRadio=`getprop persist.sys.log.radio`
    tmpEvent=`getprop persist.sys.log.event`
    tmpKernel=`getprop persist.sys.log.kernel`
    #ifndef VENDOR_EDIT
    #Xuebin.Zou@Rm.AD.Stability.aging.2731457, 2020/04/29, Add for delete tcpdump in aging test(<=64G) version
    #tmpTcpdump=`getprop persist.sys.log.tcpdump`
    #else
    DataSize=`df /data | grep /data | $XKIT awk '{print $2}'`
    if [ ${isSepcial} -eq 1 ] && [ ${DataSize} -le 63913136 ]; then
        tmpTcpdump=""
    else
        tmpTcpdump=`getprop persist.sys.log.tcpdump`
    fi
    #endif VENDOR_EDIT
    echo "getprop persist.sys.log.main ${tmpMain}"
    echo "getprop persist.sys.log.radio ${tmpRadio}"
    echo "getprop persist.sys.log.event ${tmpEvent}"
    echo "getprop persist.sys.log.kernel ${tmpKernel}"
    echo "getprop persist.sys.log.tcpdump ${tmpTcpdump}"
    if [ ${FreeSize} -ge ${GSIZE} ]; then
        if [ "${tmpMain}" != "" ]; then
            #get the config size main
            tmpAndroidSize=`set -f;array=(${tmpMain//|/ });echo "${array[0]}"`
            tmpAdnroidCount=`set -f;array=(${tmpMain//|/ });echo "${array[1]}"`
            androidSize=`echo ${tmpAndroidSize} | $XKIT awk '{printf("%d",$1*1024)}'`
            androidCount=`echo ${FreeSize} 30 50 ${androidSize} | $XKIT awk '{printf("%d",$1*$2/$3/$4)}'`
            echo "tmpAndroidSize=${tmpAndroidSize}; tmpAdnroidCount=${tmpAdnroidCount} androidSize=${androidSize} androidCount=${androidCount}"
            if [ ${androidCount} -ge ${tmpAdnroidCount} ]; then
                androidCount=${tmpAdnroidCount}
            fi
            echo "last androidCount=${androidCount}"
        fi

        if [ "${tmpRadio}" != "" ]; then
            #get the config size radio
            tmpRadioSize=`set -f;array=(${tmpRadio//|/ });echo "${array[0]}"`
            tmpRadioCount=`set -f;array=(${tmpRadio//|/ });echo "${array[1]}"`
            radioSize=`echo ${tmpRadioSize} | $XKIT awk '{printf("%d",$1*1024)}'`
            radioCount=`echo ${FreeSize} 1 50 ${radioSize} | $XKIT awk '{printf("%d",$1*$2/$3/$4)}'`
            echo "tmpRadioSize=${tmpRadioSize}; tmpRadioCount=${tmpRadioCount} radioSize=${radioSize} radioCount=${radioCount}"
            if [ ${radioCount} -ge ${tmpRadioCount} ]; then
                radioCount=${tmpRadioCount}
            fi
            echo "last radioCount=${radioCount}"
        fi

        if [ "${tmpEvent}" != "" ]; then
            #get the config size event
            tmpEventSize=`set -f;array=(${tmpEvent//|/ });echo "${array[0]}"`
            tmpEventCount=`set -f;array=(${tmpEvent//|/ });echo "${array[1]}"`
            eventSize=`echo ${tmpEventSize} | $XKIT awk '{printf("%d",$1*1024)}'`
            eventCount=`echo ${FreeSize} 1 50 ${eventSize} | $XKIT awk '{printf("%d",$1*$2/$3/$4)}'`
            echo "tmpEventSize=${tmpEventSize}; tmpEventCount=${tmpEventCount} eventSize=${eventSize} eventCount=${eventCount}"
            if [ ${eventCount} -ge ${tmpEventCount} ]; then
                eventCount=${tmpEventCount}
            fi
            echo "last eventCount=${eventCount}"
        fi

        if [ "${tmpTcpdump}" != "" ]; then
            tmpTcpdumpSize=`set -f;array=(${tmpTcpdump//|/ });echo "${array[0]}"`
            tmpTcpdumpCount=`set -f;array=(${tmpTcpdump//|/ });echo "${array[1]}"`
            tcpdumpSize=`echo ${tmpTcpdumpSize} | $XKIT awk '{printf("%d",$1*1024)}'`
            tcpdumpCount=`echo ${FreeSize} 10 50 ${tcpdumpSize} | $XKIT awk '{printf("%d",$1*$2/$3/$4)}'`
            echo "tmpTcpdumpSize=${tmpTcpdumpCount}; tmpEventCount=${tmpEventCount} tcpdumpSize=${tcpdumpSize} tcpdumpCount=${tcpdumpCount}"
            ##tcpdump use MB in the order
            tcpdumpSize=${tmpTcpdumpSize}
            if [ ${tcpdumpCount} -ge ${tmpTcpdumpCount} ]; then
                tcpdumpCount=${tmpTcpdumpCount}
            fi
            echo "last tcpdumpCount=${tcpdumpCount}"
        else
            echo "tmpTcpdump is empty"
        fi
    else
        echo "free size is less than 2G"
        androidSize=20480
        androidCount=`echo ${FreeSize} 30 50 ${androidSize} | $XKIT awk '{printf("%d",$1*$2*1024/$3/$4)}'`
        if [ ${androidCount} -ge 10 ]; then
            androidCount=10
        fi
        radioSize=10240
        radioCount=`echo ${FreeSize} 1 50 ${radioSize} | $XKIT awk '{printf("%d",$1*$2*1024/$3/$4)}'`
        if [ ${radioCount} -ge 4 ]; then
            radioCount=4
        fi
        eventSize=10240
        eventCount=`echo ${FreeSize} 1 50 ${eventSize} | $XKIT awk '{printf("%d",$1*$2*1024/$3/$4)}'`
        if [ ${eventCount} -ge 4 ]; then
            eventCount=4
        fi
        tcpdumpSize=50
        tcpdumpCount=`echo ${FreeSize} 10 50 ${tcpdumpSize} | $XKIT awk '{printf("%d",$1*$2/$3/$4)}'`
        if [ ${tcpdumpCount} -ge 2 ]; then
            tcpdumpCount=2
        fi
    fi
    ROOT_SDCARD_apps_LOG_PATH=`getprop sys.oppo.logkit.appslog`
    ROOT_SDCARD_kernel_LOG_PATH=`getprop sys.oppo.logkit.kernellog`
    ROOT_SDCARD_netlog_LOG_PATH=`getprop sys.oppo.logkit.netlog`
    ASSERT_PATH=`getprop sys.oppo.logkit.assertlog`
    TOMBSTONE_PATH=`getprop sys.oppo.logkit.tombstonelog`
    ANR_PATH=`getprop sys.oppo.logkit.anrlog`
    #Chunbo.Gao@PSW.AD.OppoDebug.LogKit.1968962, 2019/4/23, Add for qmi log
    QMI_PATH=`getprop sys.oppo.logkit.qmilog`
    ROOT_SDCARD_FINGERPRINTERLOG_PATH=`getprop sys.oppo.logkit.fingerprintlog`
}

function Logcat2(){
    panicenable=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    argtrue='true'
    echo "logcat2 panicenable=${panicenable} tmpMain=${tmpMain}"
    echo "logcat2 androidSize=${androidSize} androidCount=${androidCount}"
    echo "logcat 2 ${ROOT_SDCARD_apps_LOG_PATH}"
    if [ "${panicenable}" = "${argtrue}" ] || [ x"${camerapanic}" = x"true" ] && [ "${tmpMain}" != "" ]
    then
        logdsize=`getprop persist.logd.size`
        echo "get logdsize ${logdsize}"
        if [ "${logdsize}" = "" ]
        then
            if [ "${panicenable}" = "${argtrue}" ]
            then
                echo "normal panic"
                /system/bin/logcat -G 5M
            fi
        fi
        /system/bin/logcat -f ${ROOT_SDCARD_apps_LOG_PATH}/android.txt -r${androidSize} -n ${androidCount}  -v threadtime -A
    else
        setprop ctl.stop logcatsdcard
    fi
}

function LogcatRadio2(){
    radioenable=`getprop persist.sys.assert.panic`
    argtrue='true'
    echo "LogcatRadio2 radioenable=${radioenable} tmpRadio=${tmpRadio}"
    echo "LogcatRadio2 radioSize=${radioSize} radioSize=${radioSize}"
    if [ "${radioenable}" = "${argtrue}" ] && [ "${tmpRadio}" != "" ]
    then
    /system/bin/logcat -b radio -f ${ROOT_SDCARD_apps_LOG_PATH}/radio.txt -r${radioSize} -n ${radioCount}  -v threadtime -A
    else
    setprop ctl.stop logcatradio
    fi
}
function LogcatEvent2(){
    panicenable=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    argtrue='true'
    echo "LogcatEvent2 panicenable=${panicenable} tmpEvent=${tmpEvent}"
    echo "LogcatEvent2 eventSize=${eventSize} eventCount=${eventCount}"
    if [ "${panicenable}" = "${argtrue}" ] || [ x"${camerapanic}" = x"true" ] && [ "${tmpEvent}" != "" ]
    then
    /system/bin/logcat -b events -f ${ROOT_SDCARD_apps_LOG_PATH}/events.txt -r${eventSize} -n ${eventCount}  -v threadtime -A
    else
    setprop ctl.stop logcatevent
    fi
}
function LogcatKernel2(){
    panicenable=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    argtrue='true'
    echo "LogcatKernel2 panicenable=${panicenable} tmpKernel=${tmpKernel}"
    if [ "${panicenable}" = "${argtrue}" ] || [ x"${camerapanic}" = x"true" ] && [ "${tmpKernel}" != "" ]
    then
    #TODO:wenzhen android O
    #cat proc/cmdline > ${ROOT_SDCARD_kernel_LOG_PATH}/cmdline.txt
    /system/xbin/klogd -f - -n -x -l 7 | $XKIT tee - ${ROOT_SDCARD_kernel_LOG_PATH}/kinfo0.txt | $XKIT awk 'NR%400==0'
    fi
}
function tcpdumpLog2(){
    tcpdmpenable=`getprop persist.sys.assert.panic`
    argtrue='true'
    echo "tcpdumpLog2 tcpdmpenable=${tcpdmpenable} tmpTcpdump=${tmpTcpdump}"
    echo "tcpdumpLog2 tcpdumpSize=${tcpdumpSize} tcpdumpCount=${tcpdumpCount}"
    if [ "${tcpdmpenable}" = "${argtrue}" ] && [ "${tmpTcpdump}" != "" ]
    then
        tcpdump -i any -p -s 0 -W ${tcpdumpCount} -C ${tcpdumpSize} -w ${ROOT_SDCARD_netlog_LOG_PATH}/tcpdump -Z root
    fi
}

#ifdef OPLUS_DEBUG_SSLOG_CATCH
#//Wankang.Zhang@TECH.MDM.POWER 2020/04/02,add for catch ss log
function logcatModemTmp(){
    echo "logcatModemTmp start"
    outputPath="${DATA_LOG_PATH}/sslog"
    if [ ! -d "${outputPath}" ]; then
        mkdir -p ${outputPath}
    fi
    while [ -d "$outputPath" ]
    do
        ss -ntp -o state established >> ${outputPath}/sslog.txt
        sleep 15s #Sleep 15 seconds
    done
}
#endif

##add for log kit 2 end
function clearCurrentLog(){
    filelist=`cat ${SDCARD_LOG_BASE_PATH}/transfer_list.txt | $XKIT awk '{print $1}'`
    for i in $filelist;do
    echo "${i}"
        rm -rf ${SDCARD_LOG_BASE_PATH}/$i
    done
    rm -rf ${SDCARD_LOG_BASE_PATH}/screenshot
    rm -rf ${SDCARD_LOG_BASE_PATH}/diag_logs/*_*
    rm -rf ${SDCARD_LOG_BASE_PATH}/transfer_list.txt
    rm -rf ${SDCARD_LOG_BASE_PATH}/description.txt
    rm -rf ${SDCARD_LOG_BASE_PATH}/xlog
    rm -rf ${SDCARD_LOG_BASE_PATH}/powerlog
    rm -rf ${SDCARD_LOG_BASE_PATH}/systrace
    rm -rf data/vendor/oppo/log/device_log/diag_logs/*
}

function moveScreenRecord(){
    fileName=`getprop sys.screenrecord.name`
    zip=.zip
    mp4=.mp4
    mv -f "/data/media/0/oppo_log/${fileName}${zip}" "/data/media/0/oppo_log/compress_log/${fileName}${zip}"
    mv -f "/data/media/0/oppo_log/screen_record/screen_record.mp4" "/data/media/0/oppo_log/compress_log/${fileName}${mp4}"
}

function clearDataOppoLog(){
    rm -rf /data/oppo_log/*
    rm -rf ${DATA_LOG_PATH}/*
    # rm -rf ${SDCARD_LOG_BASE_PATH}/diag_logs/*_*
    setprop sys.clear.finished 1
}

function tranferTombstone() {
    srcpath=`getprop sys.tombstone.file`
    subPath=`getprop persist.sys.com.oppo.debug.time`
    TOMBSTONE_TIME=`date +%F-%H-%M-%S`
    cp ${srcpath} ${DATA_LOG_PATH}/${subPath}/tombstone/tomb_${TOMBSTONE_TIME}
}

function tranferAnr() {
    srcpath=`getprop sys.anr.srcfile`
    subPath=`getprop persist.sys.com.oppo.debug.time`
    destfile=`getprop sys.anr.destfile`

    cp ${srcpath} ${DATA_LOG_PATH}/${subPath}/anr/${destfile}
}

#Chunbo.Gao@PSW.AD.OppoLog.2514795, 2019/11/12, Add for copy binder_info
function copybinderinfo() {
    CURTIME=`date +%F-%H-%M-%S`
    echo ${CURTIME}
    cat /sys/kernel/debug/binder/state > ${ANR_BINDER_PATH}/binder_info_${CURTIME}.txt &
}

#Wuchao.Huang@ROM.Framework.EAP, 2019/11/19, Add for copy binder_info
function copyEapBinderInfo() {
    destBinderInfoPath=`getprop sys.eap.binderinfo.path`
    echo ${destBinderInfoPath}
    cat /sys/kernel/debug/binder/state > ${destBinderInfoPath} &
}

function cppstore() {
    panicenable=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    argtrue='true'
    srcpstore=`ls /sys/fs/pstore`
    subPath=`getprop persist.sys.com.oppo.debug.time`

    if [ "${panicenable}" = "${argtrue}" ] || [ x"${camerapanic}" = x"true" ]; then

        if [ "${srcpstore}" != "" ]; then
        cp -r /sys/fs/pstore ${DATA_LOG_PATH}/${subPath}/pstore
        fi
    fi
}
#ifdef VENDOR_EDIT
#Junhao.Liang@PSW.AD.OppoDebug.Feedback.1500936, 2018/07/31, Add for panic delete pstore/dmesg-ramoops-0 file
function rmpstore(){
    rm -rf /sys/fs/pstore/dmesg-ramoops-0
    setprop sys.oppo.rmpstore 0
}
#endif
function enabletcpdump(){
        mount -o rw,remount,barrier=1 /system
        chmod 6755 /system/bin/tcpdump
        mount -o ro,remount,barrier=1 /system
}

#ifdef VENDOR_EDIT
#Yugang.Bao@PSW.AD.OppoDebug.Feedback.1500936, 2018/07/31, Add for panic delete pstore/dmesg-ramoops-0 file
function cpoppousage() {
   mkdir -p /data/oppo/log/oppousagedump
   chown -R system:system /data/oppo/log/oppousagedump
   cp -R /mnt/vendor/opporeserve/media/log/usage/cache /data/oppo/log/oppousagedump
   cp -R /mnt/vendor/opporeserve/media/log/usage/persist /data/oppo/log/oppousagedump
   chmod -R 777 /data/oppo/log/oppousagedump
   setprop persist.sys.cpoppousage 0
}

#ifdef VENDOR_EDIT
#Deliang.Peng@PSW.MultiMedia.Display.Service.Log, 2017/3/31,add for dump sf back trace
function sfdump() {
    LOGTIME=`date +%F-%H-%M-%S`
    SWTPID=`getprop debug.swt.pid`
    JUNKLOGSFBACKPATH=/data/oppo_log/sf/${LOGTIME}
    mkdir -p ${JUNKLOGSFBACKPATH}
    cat proc/stat > ${JUNKLOGSFBACKPATH}/proc_stat.txt &
    cat proc/${SWTPID}/stat > ${JUNKLOGSFBACKPATH}/swt_stat.txt &
    cat proc/${SWTPID}/stack > ${JUNKLOGSFBACKPATH}/swt_proc_stack.txt &
    cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq > ${JUNKLOGSFBACKPATH}/cpu_freq_0_.txt &
    cat /sys/devices/system/cpu/cpu1/cpufreq/cpuinfo_cur_freq > ${JUNKLOGSFBACKPATH}/cpu_freq_1.txt &
    cat /sys/devices/system/cpu/cpu2/cpufreq/cpuinfo_cur_freq > ${JUNKLOGSFBACKPATH}/cpu_freq_2.txt &
    cat /sys/devices/system/cpu/cpu3/cpufreq/cpuinfo_cur_freq > ${JUNKLOGSFBACKPATH}/cpu_freq_3.txt &
    cat /sys/devices/system/cpu/cpu4/cpufreq/cpuinfo_cur_freq > ${JUNKLOGSFBACKPATH}/cpu_freq_4.txt &
    cat /sys/devices/system/cpu/cpu5/cpufreq/cpuinfo_cur_freq > ${JUNKLOGSFBACKPATH}/cpu_freq_5.txt &
    cat /sys/devices/system/cpu/cpu6/cpufreq/cpuinfo_cur_freq > ${JUNKLOGSFBACKPATH}/cpu_freq_6.txt &
    cat /sys/devices/system/cpu/cpu7/cpufreq/cpuinfo_cur_freq > ${JUNKLOGSFBACKPATH}/cpu_freq_7.txt &
    cat /sys/devices/system/cpu/cpu0/online > ${JUNKLOGSFBACKPATH}/cpu_online_0_.txt &
    cat /sys/devices/system/cpu/cpu1/online > ${JUNKLOGSFBACKPATH}/cpu_online_1_.txt &
    cat /sys/devices/system/cpu/cpu2/online > ${JUNKLOGSFBACKPATH}/cpu_online_2_.txt &
    cat /sys/devices/system/cpu/cpu3/online > ${JUNKLOGSFBACKPATH}/cpu_online_3_.txt &
    cat /sys/devices/system/cpu/cpu4/online > ${JUNKLOGSFBACKPATH}/cpu_online_4_.txt &
    cat /sys/devices/system/cpu/cpu5/online > ${JUNKLOGSFBACKPATH}/cpu_online_5_.txt &
    cat /sys/devices/system/cpu/cpu6/online > ${JUNKLOGSFBACKPATH}/cpu_online_6_.txt &
    cat /sys/devices/system/cpu/cpu7/online > ${JUNKLOGSFBACKPATH}/cpu_online_7_.txt &
    cat /sys/class/kgsl/kgsl-3d0/gpuclk > ${JUNKLOGSFBACKPATH}/gpuclk.txt &
    ps -t > ${JUNKLOGSFBACKPATH}/ps.txt
    top -n 1 -m 5 > ${JUNKLOGSFBACKPATH}/top.txt  &
    cp -R /data/sf ${JUNKLOGSFBACKPATH}/user_backtrace
    rm -rf /data/sf/*
}

function sfsystrace(){
    systrace_duration=`10`
    LOGTIME=`date +%F-%H-%M-%S`
    JUNKLOGSSFSYSPATH=/data/oppo_log/sf/trace/${LOGTIME}
    mkdir -p ${JUNKLOGSSFSYSPATH}
    CATEGORIES=`atrace --list_categories | $XKIT awk '{printf "%s ", $1}'`
    echo ${CATEGORIES} > ${JUNKLOGSSFSYSPATH}/categories.txt
    atrace -z -b 4096 -t ${systrace_duration} ${CATEGORIES} > ${JUNKLOGSSFSYSPATH}/atrace_raw
    /system/bin/ps -T -A  > ${SYSTRACE_DIR}/ps.txt
    /system/bin/printf "%s\n" /proc/[0-9]*/task/[0-9]* > ${SYSTRACE_DIR}/task.txt
}

#endif

#ifdef VENDOR_EDIT
#Yanzhen.Feng@Swdp.Android.OppoDebug.LayerDump, 2015/12/09, Add for SurfaceFlinger Layer dump
function layerdump(){
    mkdir -p ${SDCARD_LOG_BASE_PATH}/LayerDump
    LOGTIME=`date +%F-%H-%M-%S`
    ROOT_SDCARD_LAYERDUMP_PATH=${SDCARD_LOG_BASE_PATH}/LayerDump/LayerDump_${LOGTIME}
    cp -R /data/oppo/log/layerdump ${ROOT_SDCARD_LAYERDUMP_PATH}
    rm -rf /data/oppo/log/layerdump
    cp -R /data/log ${ROOT_SDCARD_LAYERDUMP_PATH}
    rm -rf /data/log
}
#endif /* VENDOR_EDIT */
#ifdef VENDOR_EDIT
#Yanzhen.Feng@Swdp.Android.OppoDebug, 2017/03/20, Add for systrace on phone
function cont_systrace(){
    mkdir -p ${SDCARD_LOG_BASE_PATH}/systrace
    #ifdef VENDOR_EDIT
    #liuyun@Swdp.Android.OppoDebug, 2018/12/05, Add for ignore irqoff and preemptoff events for systrace on phone
    CATEGORIES=`atrace --list_categories | $XKIT awk '!/irqoff/>/preemptoff/>/pdx/>/bionic/{printf "%s ", $1}'`
    #songyinzhong async mode
    systrace_duration=`getprop debug.oppo.systrace.duration`
    #async mode buffer do not need too large
    ((sytrace_buffer=$systrace_duration*896))
    systrace_async_mode=`getprop debug.oppo.systrace.async`
    #async stop
    systrace_status=`getprop debug.oppo.cont_systrace`
    if [ "$systrace_status" == "false" ] && [ "$systrace_async_mode" == "true" ]; then
        LOGTIME=`date +%F-%H-%M-%S`
        SYSTRACE_DIR=${SDCARD_LOG_BASE_PATH}/systrace/systrace_${LOGTIME}
        mkdir -p ${SYSTRACE_DIR}
        echo begin save ${LOGTIME}
        setprop debug.oppo.systrace.asyncsaving true
        atrace --async_stop -z -c -o ${SYSTRACE_DIR}/atrace_raw
        /system/bin/ps -AT -o USER,TID,PID,PPID,VSIZE,RSS,WCHAN,ADDR,CMD > ${SYSTRACE_DIR}/ps.txt
        /system/bin/printf "%s\n" /proc/[0-9]*/task/[0-9]* > ${SYSTRACE_DIR}/task.txt
        echo 'async stop done ' ${SYSTRACE_DIR}
        LOGTIME2=`date +%F-%H-%M-%S`
        echo save done ${LOGTIME2}
        echo 0 > /d/tracing/events/sde/enable
        echo 0 > /d/tracing/events/sde/tracing_mark_write/enable
        echo 0 > /d/tracing/events/thermal/enable
        echo 0 > /d/tracing/events/sched/sched_isolate/enable
        setprop debug.oppo.systrace.asyncsaving false
        return
        fi
    #async dump for screenshot
    systrace_dump=`getprop debug.oppo.systrace.dump`
    systrace_saving=`getprop debug.oppo.systrace.asyncsaving`
    if [ "$systrace_status" == "true" ] && [ "$systrace_async_mode" == "true" ] && [ "$systrace_dump" == "true" ]; then
        if [ "$systrace_saving" == "true" ]; then
            echo already saving systrace ,ignore
            return
        fi
        LOGTIME=`date +%F-%H-%M-%S`
        SYSTRACE_DIR=${SDCARD_LOG_BASE_PATH}/systrace/systrace_${LOGTIME}
        mkdir -p ${SYSTRACE_DIR}
        echo begin save ${LOGTIME}
        setprop debug.oppo.systrace.asyncsaving true
        atrace --async_dump -z -c -o ${SYSTRACE_DIR}/atrace_raw
        /system/bin/ps -AT -o USER,TID,PID,PPID,VSIZE,RSS,WCHAN,ADDR,CMD > ${SYSTRACE_DIR}/ps.txt
        /system/bin/printf "%s\n" /proc/[0-9]*/task/[0-9]* > ${SYSTRACE_DIR}/task.txt
        echo 'async stop done ' ${SYSTRACE_DIR}
        LOGTIME2=`date +%F-%H-%M-%S`
        echo dump done ${LOGTIME2}
        setprop debug.oppo.systrace.asyncsaving false
        setprop debug.oppo.systrace.dump false
        return
    fi
    #async start
    if [ "$systrace_status" == "true" ] && [ "$systrace_async_mode" == "true" ]; then
        echo 1 > /d/tracing/events/sde/enable
        echo 1 > /d/tracing/events/sde/tracing_mark_write/enable
        echo 1 > /d/tracing/events/thermal/enable
        echo 1 > /d/tracing/events/sched/sched_isolate/enable
        #property max len is 91, and prop should with space in tags1 and tags2
        categories_set1=`getprop debug.oppo.systrace.tags1`
        categories_set2=`getprop debug.oppo.systrace.tags2`
        if [ "$categories_set1" != "" ] || [ "$categories_set2" != "" ]; then
            CATEGORIES="$categories_set1""$categories_set2"
        fi
        echo ${CATEGORIES}
        atrace --async_start -c -b ${sytrace_buffer} ${CATEGORIES}
        echo 'async start done '
        return
    fi


    #endif /* VENDOR_EDIT */
    echo ${CATEGORIES} > ${SDCARD_LOG_BASE_PATH}/systrace/categories.txt
    while true
    do
        systrace_duration=`getprop debug.oppo.systrace.duration`
        if [ "$systrace_duration" != "" ]
        then
            echo 1 > /d/tracing/events/sde/enable
            echo 1 > /d/tracing/events/sde/tracing_mark_write/enable
            echo 1 > /d/tracing/events/thermal/enable
            echo 1 > /d/tracing/events/sched/sched_isolate/enable
            LOGTIME=`date +%F-%H-%M-%S`
            SYSTRACE_DIR=${SDCARD_LOG_BASE_PATH}/systrace/systrace_${LOGTIME}
            mkdir -p ${SYSTRACE_DIR}
            ((sytrace_buffer=$systrace_duration*1536))
            atrace -z -b ${sytrace_buffer} -t ${systrace_duration} ${CATEGORIES} > ${SYSTRACE_DIR}/atrace_raw
            /system/bin/ps -AT -o USER,TID,PID,PPID,VSIZE,RSS,WCHAN,ADDR,CMD > ${SYSTRACE_DIR}/ps.txt
            /system/bin/printf "%s\n" /proc/[0-9]*/task/[0-9]* > ${SYSTRACE_DIR}/task.txt
            systrace_status=`getprop debug.oppo.cont_systrace`
            if [ "$systrace_status" == "false" ]; then
                break
            fi
            echo 0 > /d/tracing/events/sde/enable
            echo 0 > /d/tracing/events/sde/tracing_mark_write/enable
            echo 0 > /d/tracing/events/thermal/enable
            echo 0 > /d/tracing/events/sched/sched_isolate/enable
        fi
    done
}
#endif /* VENDOR_EDIT */

#ifdef VENDOR_EDIT
#fangpan@Swdp.shanghai, 2017/06/05, Add for systrace snapshot mode
function systrace_trigger_start(){
    setprop debug.oppo.snaptrace true
    mkdir -p ${SDCARD_LOG_BASE_PATH}/systrace
    CATEGORIES=`atrace --list_categories | $XKIT awk '{printf "%s ", $1}'`
    echo ${CATEGORIES} > ${SDCARD_LOG_BASE_PATH}/systrace/categories.txt
    atrace -b 4096 --async_start ${CATEGORIES}
}
function systrace_trigger_stop(){
    atrace --async_stop
    setprop debug.oppo.snaptrace false
}
function systrace_snapshot(){
    LOGTIME=`date +%F-%H-%M-%S`
    SYSTRACE=${SDCARD_LOG_BASE_PATH}/systrace/systrace_${LOGTIME}.log
    echo 1 > /d/tracing/snapshot
    cat /d/tracing/snapshot > ${SYSTRACE}
}
#endif /* VENDOR_EDIT */

function junklogcat() {
    # echo 1 > sdcard/0.txt
    is_europe=`getprop ro.oppo.regionmark`
    if [ x"${is_europe}" != x"EUEX" ]; then
        JUNKLOGPATH=${SDCARD_LOG_BASE_PATH}/junk_logs
    else
        JUNKLOGPATH=/data/oppo/log/DCS/junk_logs_tmp
    fi
    mkdir -p ${JUNKLOGPATH}
    # echo 1 > sdcard/1.txt
    # echo 1 > ${JUNKLOGPATH}/1.txt
    system/bin/logcat -f ${JUNKLOGPATH}/junklogcat.txt -v threadtime *:V
}
function junkdmesg() {
    is_europe=`getprop ro.oppo.regionmark`
    if [ x"${is_europe}" != x"EUEX" ]; then
        JUNKLOGPATH=${SDCARD_LOG_BASE_PATH}/junk_logs
    else
        JUNKLOGPATH=/data/oppo/log/DCS/junk_logs_tmp
    fi
    mkdir -p ${JUNKLOGPATH}
    system/bin/dmesg > ${JUNKLOGPATH}/junkdmesg.txt
}
function junksystrace_start() {
    is_europe=`getprop ro.oppo.regionmark`
    if [ x"${is_europe}" != x"EUEX" ]; then
        JUNKLOGPATH=${SDCARD_LOG_BASE_PATH}/junk_logs
    else
        JUNKLOGPATH=/data/oppo/log/DCS/junk_logs_tmp
    fi
    mkdir -p ${JUNKLOGPATH}
    # echo s_start > sdcard/s_start1.txt
    #setup
    setprop debug.atrace.tags.enableflags 0x86E
    # stop;start
    adb shell "echo 16384 > /sys/kernel/debug/tracing/buffer_size_kb"

    echo nop > /sys/kernel/debug/tracing/current_tracer
    echo 'sched_switch sched_wakeup sched_wakeup_new sched_migrate_task binder workqueue irq cpu_frequency mtk_events' > /sys/kernel/debug/tracing/set_event
#just in case tracing_enabled is disabled by user or other debugging tool
    echo 1 > /sys/kernel/debug/tracing/tracing_enabled >nul 2>&1
    echo 0 > /sys/kernel/debug/tracing/tracing_on
#erase previous recorded trace
    echo > /sys/kernel/debug/tracing/trace
    echo press any key to start capturing...
    echo 1 > /sys/kernel/debug/tracing/tracing_on
    echo "Start recordng ftrace data"
    echo s_start > sdcard/s_start2.txt
}
function junksystrace_stop() {
    is_europe=`getprop ro.oppo.regionmark`
    if [ x"${is_europe}" != x"EUEX" ]; then
        JUNKLOGPATH=${SDCARD_LOG_BASE_PATH}/junk_logs
    else
        JUNKLOGPATH=/data/oppo/log/DCS/junk_logs_tmp
    fi
    mkdir -p ${JUNKLOGPATH}
    echo s_stop > sdcard/s_stop.txt
    echo 0 > /sys/kernel/debug/tracing/tracing_on
    echo "Recording stopped..."
    cp /sys/kernel/debug/tracing/trace ${JUNKLOGPATH}/junksystrace
    echo 1 > /sys/kernel/debug/tracing/tracing_on

}

#ifdef VENDOR_EDIT
#Zhihao.Li@MultiMedia.AudioServer.FrameWork, 2016/10/19, Add for clean pcm dump file.
function cleanpcmdump() {
    rm -rf ${SDCARD_LOG_BASE_PATH}/pcm_dump/*
}
#endif /* VENDOR_EDIT */

#ifdef VENDOR_EDIT
#Jianping.Zheng@Swdp.Android.Stability.Crash, 2016/08/09, Add for logd memory leak workaround
function check_logd_memleak() {
    logd_mem=`ps  | grep -i /system/bin/logd | $XKIT awk '{print $5}'`
    #echo "logd_mem:"$logd_mem
    if [ "$logd_mem" != "" ]; then
        upper_limit=300000;
        if [ $logd_mem -gt $upper_limit ]; then
            #echo "logd_mem great than $upper_limit, restart logd"
            setprop persist.sys.assert.panic false
            setprop ctl.stop logcatsdcard
            setprop ctl.stop logcatradio
            setprop ctl.stop logcatevent
            setprop ctl.stop logcatkernel
            setprop ctl.stop tcpdumplog
            setprop ctl.stop fingerprintlog
            setprop ctl.stop logfor5G
            setprop ctl.stop fplogqess
            sleep 2
            setprop ctl.restart logd
            sleep 2
            setprop persist.sys.assert.panic true
        fi
    fi
}
#endif /* VENDOR_EDIT */

function gettpinfo() {
    tplogflag=`getprop persist.sys.oppodebug.tpcatcher`
    # tplogflag=511
    # echo "$tplogflag"
    if [ "$tplogflag" == "" ]
    then
        echo "tplogflag == error"
    else

        echo "tplogflag == $tplogflag"
        # tplogflag=`echo $tplogflag | $XKIT awk '{print lshift($0, 1)}'`
        tpstate=0
        tpstate=`echo $tplogflag | $XKIT awk '{print and($1, 1)}'`
        echo "switch tpstate = $tpstate"
        if [ $tpstate == "0" ]
        then
            echo "switch tpstate off"
        else
            echo "switch tpstate on"
            ROOT_SDCARD_kernel_LOG_PATH=`getprop sys.oppo.logkit.kernellog`
            kernellogpath=${ROOT_SDCARD_kernel_LOG_PATH}/tp_debug_info
            subcur=`date +%F-%H-%M-%S`
            subpath=$kernellogpath/$subcur.txt
            mkdir -p $kernellogpath
            # mFlagMainRegister = 1 << 1
            subflag=`echo | $XKIT awk '{print lshift(1, 1)}'`
            echo "1 << 1 subflag = $subflag"
            tpstate=`echo $tplogflag $subflag, | $XKIT awk '{print and($1, $2)}'`
            if [ $tpstate == "0" ]
            then
                echo "switch tpstate off mFlagMainRegister = 1 << 1 $tpstate"
            else
                echo "switch tpstate on mFlagMainRegister = 1 << 1 $tpstate"
                echo /proc/touchpanel/debug_info/main_register  >> $subpath
                cat /proc/touchpanel/debug_info/main_register  >> $subpath
            fi
            # mFlagSelfDelta = 1 << 2;
            subflag=`echo | $XKIT awk '{print lshift(1, 2)}'`
            echo " 1<<2 subflag = $subflag"
            tpstate=`echo $tplogflag $subflag, | $XKIT awk '{print and($1, $2)}'`
            if [ $tpstate == "0" ]
            then
                echo "switch tpstate off mFlagMainRegister = 1 << 2 $tpstate"
            else
                echo "switch tpstate on mFlagMainRegister = 1 << 2 $tpstate"
                echo /proc/touchpanel/debug_info/self_delta  >> $subpath
                cat /proc/touchpanel/debug_info/self_delta  >> $subpath
            fi
            # mFlagDetal = 1 << 3;
            subflag=`echo | $XKIT awk '{print lshift(1, 3)}'`
            echo "1 << 3 subflag = $subflag"
            tpstate=`echo $tplogflag $subflag, | $XKIT awk '{print and($1, $2)}'`
            if [ $tpstate == "0" ]
            then
                echo "switch tpstate off mFlagMainRegister = 1 << 3 $tpstate"
            else
                echo "switch tpstate on mFlagMainRegister = 1 << 3 $tpstate"
                echo /proc/touchpanel/debug_info/delta  >> $subpath
                cat /proc/touchpanel/debug_info/delta  >> $subpath
            fi
            # mFlatSelfRaw = 1 << 4;
            subflag=`echo | $XKIT awk '{print lshift(1, 4)}'`
            echo "1 << 4 subflag = $subflag"
            tpstate=`echo $tplogflag $subflag, | $XKIT awk '{print and($1, $2)}'`
            if [ $tpstate == "0" ]
            then
                echo "switch tpstate off mFlagMainRegister = 1 << 4 $tpstate"
            else
                echo "switch tpstate on mFlagMainRegister = 1 << 4 $tpstate"
                echo /proc/touchpanel/debug_info/self_raw  >> $subpath
                cat /proc/touchpanel/debug_info/self_raw  >> $subpath
            fi
            # mFlagBaseLine = 1 << 5;
            subflag=`echo | $XKIT awk '{print lshift(1, 5)}'`
            echo "1 << 5 subflag = $subflag"
            tpstate=`echo $tplogflag $subflag, | $XKIT awk '{print and($1, $2)}'`
            if [ $tpstate == "0" ]
            then
                echo "switch tpstate off mFlagMainRegister = 1 << 5 $tpstate"
            else
                echo "switch tpstate on mFlagMainRegister = 1 << 5 $tpstate"
                echo /proc/touchpanel/debug_info/baseline  >> $subpath
                cat /proc/touchpanel/debug_info/baseline  >> $subpath
            fi
            # mFlagDataLimit = 1 << 6;
            subflag=`echo | $XKIT awk '{print lshift(1, 6)}'`
            echo "1 << 6 subflag = $subflag"
            tpstate=`echo $tplogflag $subflag, | $XKIT awk '{print and($1, $2)}'`
            if [ $tpstate == "0" ]
            then
                echo "switch tpstate off mFlagMainRegister = 1 << 6 $tpstate"
            else
                echo "switch tpstate on mFlagMainRegister = 1 << 6 $tpstate"
                echo /proc/touchpanel/debug_info/data_limit  >> $subpath
                cat /proc/touchpanel/debug_info/data_limit  >> $subpath
            fi
            # mFlagReserve = 1 << 7;
            subflag=`echo | $XKIT awk '{print lshift(1, 7)}'`
            echo "1 << 7 subflag = $subflag"
            tpstate=`echo $tplogflag $subflag, | $XKIT awk '{print and($1, $2)}'`
            if [ $tpstate == "0" ]
            then
                echo "switch tpstate off mFlagMainRegister = 1 << 7 $tpstate"
            else
                echo "switch tpstate on mFlagMainRegister = 1 << 7 $tpstate"
                echo /proc/touchpanel/debug_info/reserve  >> $subpath
                cat /proc/touchpanel/debug_info/reserve  >> $subpath
            fi
            # mFlagTpinfo = 1 << 8;
            subflag=`echo | $XKIT awk '{print lshift(1, 8)}'`
            echo "1 << 8 subflag = $subflag"
            tpstate=`echo $tplogflag $subflag, | $XKIT awk '{print and($1, $2)}'`
            if [ $tpstate == "0" ]
            then
                echo "switch tpstate off mFlagMainRegister = 1 << 8 $tpstate"
            else
                echo "switch tpstate on mFlagMainRegister = 1 << 8 $tpstate"
            fi

            echo $tplogflag " end else"
        fi
    fi

}
function inittpdebug(){
    panicstate=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    tplogflag=`getprop persist.sys.oppodebug.tpcatcher`
    if [ "$tplogflag" != "" ]
    then
        echo "inittpdebug not empty panicstate = $panicstate tplogflag = $tplogflag"
        if [ "$panicstate" == "true" ] || [ x"${camerapanic}" = x"true" ]
        then
            tplogflag=`echo $tplogflag , | $XKIT awk '{print or($1, 1)}'`
        else
            tplogflag=`echo $tplogflag , | $XKIT awk '{print and($1, 510)}'`
        fi
        setprop persist.sys.oppodebug.tpcatcher $tplogflag
    fi
}
function settplevel(){
    tplevel=`getprop persist.sys.oppodebug.tplevel`
    if [ "$tplevel" == "0" ]
    then
        echo 0 > /proc/touchpanel/debug_level
    elif [ "$tplevel" == "1" ]
    then
        echo 1 > /proc/touchpanel/debug_level
    elif [ "$tplevel" == "2" ]
    then
        echo 2 > /proc/touchpanel/debug_level
    fi
}
#ifdef VENDOR_EDIT
#Canjie.Zheng@Swdp.Android.OppoDebug.LogKit,2017/01/21,add for ftm
function logcatftm(){
    /system/bin/logcat  -f /mnt/vendor/persist/ftm_admin/apps/android.txt -r1024 -n 6  -v threadtime *:V
}

function klogdftm(){
    /system/xbin/klogd -f /mnt/vendor/persist/ftm_admin/kernel/kinfox.txt -n -x -l 8
}
#Canjie.Zheng@Swdp.Android.OppoDebug.LogKit,2017/03/09, add for Sensor.logger
function resetlogpath(){
    setprop sys.oppo.logkit.appslog ""
    setprop sys.oppo.logkit.kernellog ""
    setprop sys.oppo.logkit.netlog ""
    setprop sys.oppo.logkit.assertlog ""
    setprop sys.oppo.logkit.anrlog ""
    setprop sys.oppo.logkit.tombstonelog ""
    setprop sys.oppo.logkit.fingerprintlog ""
}

function pwkdumpon(){
    platform=`getprop ro.board.platform`
    echo "platform ${platform}"

    echo "sdm660 845 670 710"
    echo 0x843 > /d/regmap/spmi0-00/address
    echo 0x80 > /d/regmap/spmi0-00/data
    echo 0x842 > /d/regmap/spmi0-00/address
    echo 0x01 > /d/regmap/spmi0-00/data
    echo 0x840 > /d/regmap/spmi0-00/address
    echo 0x0F > /d/regmap/spmi0-00/data
    echo 0x841 > /d/regmap/spmi0-00/address
    echo 0x07 > /d/regmap/spmi0-00/data

}

function pwkdumpoff(){
    platform=`getprop ro.board.platform`
    echo "platform ${platform}"
    echo "sdm660 845 670 710"
    echo 0x843 > /d/regmap/spmi0-00/address
    echo 0x00 > /d/regmap/spmi0-00/data
    echo 0x842 > /d/regmap/spmi0-00/address
    echo 0x07 > /d/regmap/spmi0-00/data

}

function dumpon(){
    platform=`getprop ro.board.platform`

    echo full > /sys/kernel/dload/dload_mode
    echo 0 > /sys/kernel/dload/emmc_dload
#ifdef VENDOR_EDIT
#Haitao.Zhou@BSP.Kernel.Stability, 2017/06/27, add for mini dump and full dump swicth
#Ziqing.Guo@BSP.Kernel.Stability, 2018/01/13, add for mini dump and full dump swicth
#yanghao@BSP.Kernel.Stability, 2019/11/22, add root version meet apdp mimi caused part ramdump can't parse
    full_update=`getprop persist.root.fulldump.update`
    boot_completed=`getprop sys.boot_completed`
    if [ x${boot_completed} == x"1" ] || [ x"${full_update}" == x"1" ]; then
        dd if=/vendor/firmware/dpAP_full.mbn of=/dev/block/bootdevice/by-name/apdp
        sync
    fi
    if [ x"${full_update}" == x"1" ]; then
        setprop persist.root.fulldump.update 0
    fi
#ifdef VENDOR_EDIT
#Chunbo.Gao@PSW.AD.OppoDebug.LogKit.1974273, 2019/4/22, Add for dumpon
    dump_log_dir="/sys/bus/msm_subsys/devices"

    modem_crash_not_reboot_to_dump=`getprop persist.sys.modem.crash.noreboot`
    adsp_crash_not_reboot_to_dump=`getprop persist.sys.adsp.crash.noreboot`
    wlan_crash_not_reboot_to_dump=`getprop persist.sys.wlan.crash.noreboot`
    cdsp_crash_not_reboot_to_dump=`getprop persist.sys.cdsp.crash.noreboot`
    slpi_crash_not_reboot_to_dump=`getprop persist.sys.slpi.crash.noreboot`
    ap_crash_only=`getprop persist.sys.ap.crash.only`

    if [ -d ${dump_log_dir} ]; then
        ALL_FILE=`ls -t ${dump_log_dir}`
        for i in $ALL_FILE;
        do
            echo ${i}
            if [ -d ${dump_log_dir}/${i} ]; then
                echo ${dump_log_dir}/${i}/restart_level
                chmod 0666 ${dump_log_dir}/${i}/restart_level
                subsys_name=`cat /sys/bus/msm_subsys/devices/${i}/name`
                if [ "${ap_crash_only}" = "true" ] ; then
                    echo related > ${dump_log_dir}/${i}/restart_level
                else
                    if [ "${subsys_name}" = "modem" ] && [ "${modem_crash_not_reboot_to_dump}" = "true" ] ; then
                        echo related > ${dump_log_dir}/${i}/restart_level
                    elif [ "${subsys_name}" = "adsp" ] && [ "${adsp_crash_not_reboot_to_dump}" = "true" ] ; then
                        echo related > ${dump_log_dir}/${i}/restart_level
                    elif [ "${subsys_name}" = "wlan" ] && [ "${wlan_crash_not_reboot_to_dump}" = "true" ] ; then
                        echo related > ${dump_log_dir}/${i}/restart_level
                    elif [ "${subsys_name}" = "cdsp" ] && [ "${cdsp_crash_not_reboot_to_dump}" = "true" ] ; then
                        echo related > ${dump_log_dir}/${i}/restart_level
                    elif [ "${subsys_name}" = "slpi" ] && [ "${slpi_crash_not_reboot_to_dump}" = "true" ] ; then
                        echo related > ${dump_log_dir}/${i}/restart_level
                    else
                        echo system > ${dump_log_dir}/${i}/restart_level
                    fi
                fi
            fi
        done
    fi
#endif /*VENDOR_EDIT*/

# Laixin@PSW.CN.WiFi.Basic.1069763, add for enable dump for wifi switch issue
    setprop sys.wifi.full.dump.finish true
#end
}

function dumpoff(){
    platform=`getprop ro.board.platform`


    echo mini > /sys/kernel/dload/dload_mode
    echo 1 > /sys/kernel/dload/emmc_dload
#ifdef VENDOR_EDIT
#Haitao.Zhou@BSP.Kernel.Stability, 2017/06/27, add for mini dump and full dump swicth
#Ziqing.Guo@BSP.Kernel.Stability, 2018/01/13, add for mini dump and full dump swicth
    boot_completed=`getprop sys.boot_completed`
    if [ x${boot_completed} == x"1" ]; then
        dd if=/vendor/firmware/dpAP_mini.mbn of=/dev/block/bootdevice/by-name/apdp
        sync
    fi

#ifdef VENDOR_EDIT
#Chunbo.Gao@PSW.AD.OppoDebug.LogKit.1974273, 2019/4/22, Add for dumpoff
    dump_log_dir="/sys/bus/msm_subsys/devices"
    if [ -d ${dump_log_dir} ]; then
        ALL_FILE=`ls -t ${dump_log_dir}`
        for i in $ALL_FILE;
        do
            echo ${i}
            if [ -d ${dump_log_dir}/${i} ]; then
               echo ${dump_log_dir}/${i}/restart_level
               echo related > ${dump_log_dir}/${i}/restart_level
            fi
        done
    fi
#endif /*VENDOR_EDIT*/

}

#Chunbo.Gao@PSW.AD.OppoDebug.LogKit.1968962, 2019/4/23, Add for qmi log
function qmilogon() {
    echo "qmilogon begin"
    qmilog_switch=`getprop persist.sys.qmilog.switch`
    echo ${qmilog_switch}
    if [ "$qmilog_switch" == "true" ]; then
        setprop ctl.start qrtrlookup
        setprop ctl.start adspglink
        setprop ctl.start modemglink
        setprop ctl.start cdspglink
        setprop ctl.start modemqrtr
        setprop ctl.start sensorqrtr
        setprop ctl.start npuqrtr
        setprop ctl.start slpiqrtr
        setprop ctl.start slpiglink
        setprop ctl.start logcatModemTmp
    fi
    echo "qmilogon end"
}

function qmilogoff() {
    echo "qmilogoff begin"
    qmilog_switch=`getprop persist.sys.qmilog.switch`
    echo ${qmilog_switch}
    if [ "$qmilog_switch" == "true" ]; then
        setprop ctl.stop qrtrlookup
        setprop ctl.stop adspglink
        setprop ctl.stop modemglink
        setprop ctl.stop cdspglink
        setprop ctl.stop modemqrtr
        setprop ctl.stop sensorqrtr
        setprop ctl.stop npuqrtr
        setprop ctl.stop slpiqrtr
        setprop ctl.stop slpiglink
        setprop ctl.stop logcatModemTmp
    fi
    echo "qmilogoff end"
}

function qrtrlookup() {
    echo "qrtrlookup begin"
    if [ -d "/d/ipc_logging" ]; then
        #QMI_PATH=`getprop sys.oppo.logkit.qmilog`
        path=`getprop sys.oppo.logkit.qmilog`
        echo ${path}
        /vendor/bin/qrtr-lookup > ${path}/qrtr-lookup_info.txt
    fi
    echo "qrtrlookup end"
}

function adspglink() {
    echo "adspglink begin"
    if [ -d "/d/ipc_logging" ]; then
        path=`getprop sys.oppo.logkit.qmilog`
        cat /d/ipc_logging/adsp/log_cont > ${path}/adsp_glink.log
        cat /d/ipc_logging/diag/log_cont > ${path}/diag_ipc_glink.log &
    fi
}

function modemglink() {
    echo "modemglink begin"
    if [ -d "/d/ipc_logging" ]; then
        path=`getprop sys.oppo.logkit.qmilog`
        cat /d/ipc_logging/modem/log_cont > ${path}/modem_glink.log
    fi
}

function cdspglink() {
    echo "cdspglink begin"
    if [ -d "/d/ipc_logging" ]; then
        path=`getprop sys.oppo.logkit.qmilog`
        cat /d/ipc_logging/cdsp/log_cont > ${path}/cdsp_glink.log
    fi
}
function modemqrtr() {
    echo "modemqrtr begin"
    if [ -d "/d/ipc_logging" ]; then
        path=`getprop sys.oppo.logkit.qmilog`
        cat /d/ipc_logging/qrtr_0/log_cont > ${path}/modem_qrtr.log
    fi
}

function sensorqrtr() {
    echo "sensorqrtr begin"
    if [ -d "/d/ipc_logging" ]; then
        path=`getprop sys.oppo.logkit.qmilog`
        cat /d/ipc_logging/qrtr_5/log_cont > ${path}/sensor_qrtr.log
    fi
}

function npuqrtr() {
    echo "NPUqrtr begin"
    if [ -d "/d/ipc_logging" ]; then
        path=`getprop sys.oppo.logkit.qmilog`
        cat /d/ipc_logging/qrtr_10/log_cont > ${path}/NPU_qrtr.log
    fi
}

function slpiqrtr() {
    echo "slpiqrtr begin"
    if [ -d "/d/ipc_logging" ]; then
        path=`getprop sys.oppo.logkit.qmilog`
        cat /d/ipc_logging/qrtr_9/log_cont > ${path}/slpi_qrtr.log
    fi
}

function slpiglink() {
    echo "slpiglink begin"
    if [ -d "/d/ipc_logging" ]; then
        path=`getprop sys.oppo.logkit.qmilog`
        cat /d/ipc_logging/slpi/log_cont > ${path}/slpi_glink.log
    fi
}
#endif  /* VENDOR_EDIT */

function test(){
    panicenable=`getprop persist.sys.assert.panic`
    mkdir -p /data/test_log_kit
    touch /data/oppo_log/test_log_kit/debug.txt
    echo ${panicenable} > /data/oppo_log/test_log_kit/debug.txt
    /system/bin/logcat -f /data/oppo_log/android_winston.txt -r102400 -n 100  -v threadtime -A
}

function rmminidump(){
    rm -rf /data/system/dropbox/minidump.bin
}

function readdump(){
    echo "begin readdump"

    system/bin/minidumpreader
    echo "dump end"

}
function packupminidump() {

    timestamp=`getprop sys.oppo.minidump.ts`
    echo time ${timestamp}
    uuid=`getprop sys.oppo.minidumpuuid`
    otaversion=`getprop ro.build.version.ota`
    minidumppath="/data/oppo/log/DCS/de/minidump"
    #tag@hash@ota@datatime
    packupname=${minidumppath}/SYSTEM_LAST_KMSG@${uuid}@${otaversion}@${timestamp}
    echo name ${packupname}
    #read device info begin
    #"/proc/oppoVersion/serialID",
    #"/proc/devinfo/ddr",
    #"/proc/devinfo/emmc",
    #"proc/devinfo/emmc_version"};
    model=`getprop ro.product.model`
    version=`getprop ro.build.version.ota`
    echo "model:${model}" > /data/oppo/log/DCS/minidump/device.info
    echo "version:${version}" >> /data/oppo/log/DCS/minidump/device.info
    echo "/proc/oppoVersion/serialID" >> /data/oppo/log/DCS/minidump/device.info
    cat /proc/oppoVersion/serialID >> /data/oppo/log/DCS/minidump/device.info
    echo "\n/proc/devinfo/ddr" >> /data/oppo/log/DCS/minidump/device.info
    cat /proc/devinfo/ddr >> /data/oppo/log/DCS/minidump/device.info
    echo "/proc/devinfo/emmc" >> /data/oppo/log/DCS/minidump/device.info
    cat /proc/devinfo/emmc >> /data/oppo/log/DCS/minidump/device.info
    echo "/proc/devinfo/emmc_version" >> /data/oppo/log/DCS/minidump/device.info
    cat /proc/devinfo/emmc_version >> /data/oppo/log/DCS/minidump/device.info
    echo "/proc/devinfo/ufs" >> /data/oppo/log/DCS/minidump/device.info
    cat /proc/devinfo/ufs >> /data/oppo/log/DCS/minidump/device.info
    echo "/proc/devinfo/ufs_version" >> /data/oppo/log/DCS/minidump/device.info
    cat /proc/devinfo/ufs_version >> /data/oppo/log/DCS/minidump/device.info
    echo "/proc/oppoVersion/ocp" >> /data/oppo/log/DCS/minidump/device.info
    cat /proc/oppoVersion/ocp >> /data/oppo/log/DCS/minidump/device.info
    cp /data/system/packages.xml /data/oppo/log/DCS/minidump/packages.xml
    echo "tar -czvf ${packupname} -C /data/oppo/log/DCS/minidump ." >> /data/oppo/log/DCS/minidump/device.info
    $XKIT tar -czvf ${packupname}.dat.gz.tmp -C /data/oppo/log/DCS/minidump .
    echo "chown system:system ${packupname}*" >> /data/oppo/log/DCS/minidump/device.info
    chown system:system ${packupname}*
    echo "mv ${packupname}.dat.gz.tmp ${packupname}.dat.gz" >> /data/oppo/log/DCS/minidump/device.info
    mv ${packupname}.dat.gz.tmp ${packupname}.dat.gz
    chown system:system ${packupname}*
    echo "-rf /data/oppo/log/DCS/minidump"
    rm -rf /data/oppo/log/DCS/minidump
    #setprop sys.oppo.phoenix.handle_error ERROR_REBOOT_FROM_KE_SUCCESS
    try_copy_minidump_to_opporeserve "${packupname}.dat.gz"
}

#Fangfang.Hui@TECH.AD.Stability, 2019/08/13, Add for the quality feedback dcs config
function backupMinidump() {
    tag=`getprop sys.backup.minidump.tag`
    if [ x"$tag" = x"" ]; then
        echo "backup.minidump.tag is null, do nothing"
        return
    fi
    minidumppath="/data/oppo/log/DCS/de/minidump"
    miniDumpFile=$minidumppath/$(ls -t ${minidumppath} | head -1)
    if [ x"$miniDumpFile" = x"" ]; then
        echo "minidump.file is null, do nothing"
        return
    fi
    result=$(echo $miniDumpFile | grep "${tag}")
    if [ x"$result" = x"" ]; then
        echo "tag mismatch, do not backup"
        return
    else
        try_copy_minidump_to_opporeserve $miniDumpFile
        setprop sys.backup.minidump.tag ""
    fi
}

function try_copy_minidump_to_opporeserve() {
    OPPORESERVE_MINIDUMP_BACKUP_PATH="/mnt/vendor/opporeserve/media/log/minidump"
    OPPORESERVE2_MOUNT_POINT="/mnt/vendor/opporeserve"

    if [ ! -d ${OPPORESERVE_MINIDUMP_BACKUP_PATH} ]; then
        mkdir ${OPPORESERVE_MINIDUMP_BACKUP_PATH}
    fi
    chmod -R 0770 ${OPPORESERVE_MINIDUMP_BACKUP_PATH}
    chown -R system ${OPPORESERVE_MINIDUMP_BACKUP_PATH}
    chgrp -R system ${OPPORESERVE_MINIDUMP_BACKUP_PATH}
    NewLogPath=$1
    if [ ! -f $NewLogPath ] ;then
        echo "Can not access ${NewLogPath}, the file may not exists "
        return
    fi
    TmpLogSize=`du -s -k ${NewLogPath} | $XKIT awk '{print $1}'`
    curBakCount=`ls ${OPPORESERVE_MINIDUMP_BACKUP_PATH} | wc -l`
    echo "curBakCount = $curBakCount"
    while [ ${curBakCount} -gt 5 ]   #can only save 5 backup minidump logs at most
    do
        rm -rf ${OPPORESERVE_MINIDUMP_BACKUP_PATH}/$(ls -t ${OPPORESERVE_MINIDUMP_BACKUP_PATH} | tail -1)
        curBakCount=`ls ${OPPORESERVE_MINIDUMP_BACKUP_PATH} | wc -l`
        echo "delete one file curBakCount = $curBakCount"
    done
    FreeSize=$(df -k | grep "${OPPORESERVE2_MOUNT_POINT}" | sed 's/[ ][ ]*/,/g' | cut -d "," -f4)
    TotalSize=$(df -k | grep "${OPPORESERVE2_MOUNT_POINT}" | sed 's/[ ][ ]*/,/g' | cut -d "," -f2)
    ReserveSize=`expr $TotalSize / 5`
    NeedSize=`expr $TmpLogSize + $ReserveSize`
    echo "NeedSize = $NeedSize, ReserveSize = $ReserveSize, FreeSize = $FreeSize"
    while [ ${FreeSize} -le ${NeedSize} ]
    do
        curBakCount=`ls ${OPPORESERVE_MINIDUMP_BACKUP_PATH} | wc -l`
        if [ $curBakCount -gt 1 ]; then #leave at most on log file
            rm -rf ${OPPORESERVE_MINIDUMP_BACKUP_PATH}/$(ls -t ${OPPORESERVE_MINIDUMP_BACKUP_PATH} | tail -1)
            echo "${OPPORESERVE2_MOUNT_POINT} left space ${FreeSize} not enough for minidump, delete one de minidump"
            FreeSize=$(df -k | grep "${OPPORESERVE2_MOUNT_POINT}" | sed 's/[ ][ ]*/,/g' | cut -d "," -f4)
            continue
        fi
        echo "${OPPORESERVE2_MOUNT_POINT} left space ${FreeSize} not enough for minidump, nothing to delete"
        return 0
    done
    #space is enough, now copy
    cp $NewLogPath $OPPORESERVE_MINIDUMP_BACKUP_PATH
    chmod -R 0770 ${OPPORESERVE_MINIDUMP_BACKUP_PATH}
    chown -R system ${OPPORESERVE_MINIDUMP_BACKUP_PATH}
    chgrp -R system ${OPPORESERVE_MINIDUMP_BACKUP_PATH}
}

function junk_log_monitor(){
    is_europe=`getprop ro.oppo.regionmark`
    if [ x"${is_europe}" != x"EUEX" ]; then
        DIR=${SDCARD_LOG_BASE_PATH}/junk_logs/DCS
    else
        DIR=/data/oppo/log/DCS/de/junk_logs
    fi
    MAX_NUM=10
    IDX=0
    if [ -d "$DIR" ]; then
        ALL_FILE=`ls -t $DIR`
        for i in $ALL_FILE;
        do
            echo "now we have file $i"
            let IDX=$IDX+1;
            echo ========file num is $IDX===========
            if [ "$IDX" -gt $MAX_NUM ] ; then
               echo rm file $i\!;
            rm -rf $DIR/$i
            fi
        done
    fi
}

#endif VENDOR_EDIT

#Jianping.Zheng@PSW.Android.Stability.Crash,2017/06/12,add for record d status thread stack
function record_d_threads_stack() {
    record_path=$1
    echo "\ndate->" `date` >> ${record_path}
    ignore_threads="kworker/u16:1|mdss_dsi_event|mmc-cmdqd/0|msm-core:sampli|kworker/10:0|mdss_fb0"
    d_status_tids=`ps -t | grep " D " | grep -iEv "$ignore_threads" | $XKIT awk '{print $2}'`;
    if [ x"${d_status_tids}" != x"" ]
    then
        sleep 5
        d_status_tids_again=`ps -t | grep " D " | grep -iEv "$ignore_threads" | $XKIT awk '{print $2}'`;
        for tid in ${d_status_tids}
        do
            for tid_2 in ${d_status_tids_again}
            do
                if [ x"${tid}" == x"${tid_2}" ]
                then
                    thread_stat=`cat /proc/${tid}/stat | grep " D "`
                    if [ x"${thread_stat}" != x"" ]
                    then
                        echo "tid:"${tid} "comm:"`cat /proc/${tid}/comm` "cmdline:"`cat /proc/${tid}/cmdline`  >> ${record_path}
                        echo "stack:" >> ${record_path}
                        cat /proc/${tid}/stack >> ${record_path}
                    fi
                    break
                fi
            done
        done
    fi
}

#Jianping.Zheng@Swdp.Android.Stability.Crash,2017/04/04,add for record performance
function perf_record() {
    check_interval=`getprop persist.sys.oppo.perfinteval`
    if [ x"${check_interval}" = x"" ]; then
        check_interval=60
    fi
    perf_record_path=${DATA_LOG_PATH}/perf_record_logs
    while [ true ];do
        if [ ! -d ${perf_record_path} ];then
            mkdir -p ${perf_record_path}
        fi

        echo "\ndate->" `date` >> ${perf_record_path}/cpu.txt
        cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq >> ${perf_record_path}/cpu.txt

        echo "\ndate->" `date` >> ${perf_record_path}/mem.txt
        cat /proc/meminfo >> ${perf_record_path}/mem.txt

        echo "\ndate->" `date` >> ${perf_record_path}/buddyinfo.txt
        cat /proc/buddyinfo >> ${perf_record_path}/buddyinfo.txt

        echo "\ndate->" `date` >> ${perf_record_path}/top.txt
        top -n 1 >> ${perf_record_path}/top.txt

        #record_d_threads_stack "${perf_record_path}/d_status.txt"

        if [ $topneocount -le 10 ]; then
            topneo=`top -n 1 | grep neo | awk '{print $9}' | head -n 1 | awk -F . '{print $1}'`;
            if [ $topneo -gt 90 ]; then
                neopid=`ps -A | grep neo | awk '{print $2}'`;
                echo "\ndate->" `date` >> ${perf_record_path}/neo_debuggerd.txt
                debuggerd $neopid >> ${perf_record_path}/neo_debuggerd.txt;
                let topneocount+=1
            fi
        fi

        sleep "$check_interval"
    done
}

#ifdef VENDOR_EDIT
#Qianyou.Chen@PSW.Android.OppoDebug.LogKit,2017/04/12, Add for wifi packet log
function prepacketlog(){
    panicstate=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    packetlogstate=`getprop persist.sys.wifipacketlog.state`
    packetlogbuffsize=`getprop persist.sys.wifipktlog.buffsize`
    timeout=0

    if [ "${panicstate}" = "true" ] || [ x"${camerapanic}" = x"true" ] && [ "${packetlogstate}" = "true" ];then
        echo Disable it before we set the size...
        iwpriv wlan0 pktlog 0
        while [ $? -ne "0" ];do
            echo wait util the file system is built.
            sleep 2
            if [ $timeout -gt 30 ];then
                echo less than the numbers  we want...
                echo can not finish prepacketlog... > ${DATA_LOG_PATH}/pktlog_error.txt
                iwpriv wlan0 pktlog 0 >> ${DATA_LOG_PATH}/pktlog_error.txt
                exit
            fi
            let timeout+=1;
            iwpriv wlan0 pktlog 0
        done
        if [ "${packetlogbuffsize}" = "1" ];then
            echo Set the pktlog buffer size to 100MB...
            pktlogconf -s 100000000 -a cld
        else
            echo Set the pktlog buffer size to 20MB...
            pktlogconf -s 20000000 -a cld
            setprop persist.sys.wifipktlog.buffersize 0
        fi

        echo Enable the pktlog...
        iwpriv wlan0 pktlog 1
    fi
}
function wifipktlogtransf(){
    LOGTIME=`getprop persist.sys.com.oppo.debug.time`
    ROOT_SDCARD_LOG_PATH=${DATA_LOG_PATH}/${LOGTIME}
    packetlogstate=`getprop persist.sys.wifipacketlog.state`

    boot_completed=`getprop sys.boot_completed`
    while [ x${boot_completed} != x"1" ];do
        echo sleep 5s...
        sleep 5
        boot_completed=`getprop sys.boot_completed`
    done

    iwpriv wlan0 pktlog 0
    while [ $? -ne "0" ];do
        echo wait util the file system is built.
        sleep 2
        if [ $timeout -gt 30 ];then
            echo less than the numbers  we want...
            echo can not finish prepacketlog... > ${DATA_LOG_PATH}/pktlog_error.txt
            iwpriv wlan0 pktlog 0 >> ${DATA_LOG_PATH}/pktlog_error.txt
            exit
        fi
        let timeout+=1;
        iwpriv wlan0 pktlog 0
    done
    if [ "${packetlogstate}" = "true" ];then
        echo transfer start...
        if [ ! -d ${ROOT_SDCARD_LOG_PATH}/wlan_logs ];then
            mkdir -p ${ROOT_SDCARD_LOG_PATH}/wlan_logs
        fi
        #Xuefeng.Peng@PSW.AD.Storage.1578642, 2018/09/30, Add for avoid wlan_logs can not be removed by filemanager
        chmod -R 777 ${ROOT_SDCARD_LOG_PATH}/wlan_logs

        cat /proc/ath_pktlog/cld > ${ROOT_SDCARD_LOG_PATH}/wlan_logs/pktlog.dat
        iwpriv wlan0 pktlog 4
        echo transfer end...
    fi

    pktlogconf -s 10000000 -a cld
    iwpriv wlan0 pktlog 1
}

function pktcheck(){
    pktlogenable=`cat /persist/WCNSS_qcom_cfg.ini | grep gEnablePacketLog`
    savedenable=`getprop persist.sys.wifipktlog.enable`
    boot_completed=`getprop sys.boot_completed`

    echo avoid checking too early before WCNSS_qcom_cfg.ini is prepared...
    while [ x${boot_completed} != x"1" ];do
        echo sleep 5s...
        sleep 5
        boot_completed=`getprop sys.boot_completed`
    done

    echo wifipktlogfunccheck starts...
    if [ -z ${savedenable} ];then
        if [ "${pktlogenable#*=}" = "1" ];then
            echo set persist.sys.wifipktlog.enable true...
            setprop persist.sys.wifipktlog.enable true
        else
            echo set persist.sys.wifipktlog.enable false...
            setprop persist.sys.wifipktlog.enable false
            setprop persist.sys.wifipacketlog.state false
        fi
    fi
}

#Qianyou.Chen@PSW.Android.OppoDebug.LogKit.0000000, 2019/06/05, Add for modifying cpt list.
function copyCptTmpListToDest() {
    OPPO_LOG_COMPATIBILITY_TMP_FILE="/data/oppo/log/oppo_cpt_list.xml"
    OPPO_LOG_COMPATIBILITY_DEST_DIR="/data/format_unclear/compatibility"
    if [ ! -d ${OPPO_LOG_COMPATIBILITY_DEST_DIR} ];then
        mkdir -p ${OPPO_LOG_COMPATIBILITY_DEST_DIR}
        chmod 777 -R ${OPPO_LOG_COMPATIBILITY_DEST_DIR}
        chown system:system ${OPPO_LOG_COMPATIBILITY_DEST_DIR}
    fi

    cp -f ${OPPO_LOG_COMPATIBILITY_TMP_FILE} $OPPO_LOG_COMPATIBILITY_DEST_DIR/oppo_cpt_list.xml

    chown system:system -R $OPPO_LOG_COMPATIBILITY_DEST_DIR
    chmod 644 $OPPO_LOG_COMPATIBILITY_DEST_DIR/oppo_cpt_list.xml

    #echo "copy done!"
}
#endif VENDOR_EDIT

#Jianping.Zheng@PSW.Android..Stability.Crash, 2017/06/20, Add for collect futexwait block log
function collect_futexwait_log() {
    collect_path=/data/system/dropbox/extra_log
    if [ ! -d ${collect_path} ]
    then
        mkdir -p ${collect_path}
        chmod 700 ${collect_path}
        chown system:system ${collect_path}
    fi

    #time
    echo `date` > ${collect_path}/futexwait.time.txt

    #ps -t info
    ps -A -T > $collect_path/ps.txt

    #D status to dmesg
    echo w > /proc/sysrq-trigger

    #systemserver trace
    system_server_pid=`ps -A |grep system_server | $XKIT awk '{print $2}'`
    kill -3 ${system_server_pid}
    sleep 10
    cp /data/anr/traces.txt $collect_path/

    #systemserver native backtrace
    debuggerd -b ${system_server_pid} > $collect_path/systemserver.backtrace.txt
}

#Jianping.Zheng@PSW.Android.Stability.Crash,2017/05/08,add for systemserver futex_wait block check
function checkfutexwait_wrap() {
    if [ -f /system/bin/checkfutexwait ]; then
        setprop ctl.start checkfutexwait_bin
    else
        while [ true ];do
            is_futexwait_started=`getprop init.svc.checkfutexwait`
            if [ x"${is_futexwait_started}" != x"running" ]; then
                setprop ctl.start checkfutexwait
            fi
            sleep 180
        done
    fi
}

function do_check_systemserver_futexwait_block() {
    exception_max=`getprop persist.sys.futexblock.max`
    if [ x"${exception_max}" = x"" ]; then
        exception_max=60
    fi

    system_server_pid=`ps -A |grep system_server | $XKIT awk '{print $2}'`
    if [ x"${system_server_pid}" != x"" ]; then
        exception_count=0
        while [ $exception_count -lt $exception_max ] ;do
            systemserver_stack_status=`ps -A | grep system_server | $XKIT awk '{print $6}'`
            if [ x"${systemserver_stack_status}" != x"futex_wait_queue_me" ]; then
                break
            fi

            inputreader_stack_status=`ps -A -T | grep InputReader  | $XKIT awk '{print $7}'`
            if [ x"${inputreader_stack_status}" == x"futex_wait_queue_me" ]; then
                exception_count=`expr $exception_count + 1`
                if [ x"${exception_count}" = x"${exception_max}" ]; then
                    echo "Systemserver,FutexwaitBlocked-"`date` > "/proc/sys/kernel/hung_task_oppo_kill"
                    setprop sys.oppo.futexwaitblocked "`date`"
                    collect_futexwait_log
                    kill -9 $system_server_pid
                    sleep 60
                    break
                fi
                sleep 1
            else
                break
            fi
        done
    fi
}
#end, add for systemserver futex_wait block check

function getSystemStatus() {
    echo "$(date +%F-%H:%M:%S) dumpSystem:start...." >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
    boot_completed=`getprop sys.boot_completed`
    if [ x${boot_completed} == x"1" ]
    then
        timeSub=`getprop persist.sys.com.oppo.debug.time`
        outputPath="${DATA_LOG_PATH}/${timeSub}/SI_stop"

        echo "$(date +%F-%H:%M:%S) dumpSystem:${outputPath}" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
        mkdir -p ${outputPath}
        rm -f ${outputPath}/finish_system
        dumpsys -t 15 meminfo > ${outputPath}/dumpsys_mem.txt &
        setprop sys.tranfer.finished mv:meminfo
        if [ ! -d "${outputPath}" ];then
            mkdir -p ${outputPath}
        else
            #setprop ctl.start dump_sysinfo
            dumpWechatInfo
            sleep 1
        fi
        echo "$(date +%F-%H:%M:%S) dumpSystem:ps,top" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
        ps -A -l -T -O RSS,VSZ,USER > ${outputPath}/ps.txt
        top -n 1 -s 10 > ${outputPath}/top.txt
        cat /proc/meminfo > ${outputPath}/proc_meminfo.txt
        cat /proc/interrupts > ${outputPath}/interrupts.txt
        cat /sys/kernel/debug/wakeup_sources > ${outputPath}/wakeup_sources.log
        echo "$(date +%F-%H:%M:%S) dumpSystem:getprop" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
        getprop > ${outputPath}/prop.txt
        echo "$(date +%F-%H:%M:%S) dumpSystem:df" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
        df > ${outputPath}/df.txt
        echo "$(date +%F-%H:%M:%S) dumpSystem:lpdump" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
        lpdump > ${outputPath}/lpdump.txt
        echo "$(date +%F-%H:%M:%S) dumpSystem:mount" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
        mount > ${outputPath}/mount.txt
        setprop sys.tranfer.finished mv:mount
        echo "$(date +%F-%H:%M:%S) dumpSystem:cat" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
        cat data/system/packages.xml  > ${outputPath}/packages.txt
        cat data/system/appops.xml  > ${outputPath}/appops.xml
        echo "$(date +%F-%H:%M:%S) dumpSystem:dumpsys appops" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
        dumpsys appops > ${outputPath}/dumpsys_appops.xml
        /vendor/bin/qrtr-lookup > ${outputPath}/qrtr-lookup.txt
        cat /proc/zoneinfo > ${outputPath}/zoneinfo.txt
        cat /proc/slabinfo > ${outputPath}/slabinfo.txt
        cp -rf /sys/kernel/debug/ion ${outputPath}/
        cp -rf /sys/kernel/debug/dma_buf ${outputPath}/

        echo "$(date +%F-%H:%M:%S) dumpSystem:user" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
        dumpsys user > ${outputPath}/dumpsys_user.txt
        dumpsys power > ${outputPath}/dumpsys_power.txt
        dumpsys alarm > ${outputPath}/dumpsys_alarm.txt
        dumpsys batterystats > ${outputPath}/dumpsys_batterystats.txt
        dumpsys batterystats -c > ${outputPath}/dumpsys_battersystats_for_bh.txt
        setprop sys.tranfer.finished mv:batterystats
        dumpsys location > ${outputPath}/dumpsys_location.txt
        dumpsys accessibility > ${outputPath}/dumpsys_accessibility.txt
        dumpsys sensorservice > ${outputPath}/dumpsys_sensorservice.txt
        dumpsys battery > ${outputPath}/dumpsys_battery.txt

        ##kevin.li@ROM.Framework, 2019/11/5, add for hans freeze manager(for protection)
        hans_enable=`getprop persist.sys.enable.hans`
        if [ "$hans_enable" == "true" ]; then
            dumpsys activity hans history > ${outputPath}/dumpsys_hans_history.txt
        fi
        #kevin.li@ROM.Framework, 2019/12/2, add for hans cts property
        hans_enable=`getprop persist.vendor.enable.hans`
        if [ "$hans_enable" == "true" ]; then
            dumpsys activity hans history > ${outputPath}/dumpsys_hans_history.txt
        fi
        #chao.zhu@ROM.Framework, 2020/04/17, add for preload
        preload_enable=`getprop persist.vendor.enable.preload`
        if [ "$preload_enable" == "true" ]; then
            dumpsys activity preload > ${outputPath}/dumpsys_preload.txt
        fi

        wait
        getMemoryMap;

        touch ${outputPath}/finish_system
        echo "$(date +%F-%H:%M:%S) dumpSystem:done...." >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
    fi
}
#ifdef VENDOR_EDIT
#Zhiming.chen@PSW.AD.OppoLog.BugID 2724830, 2020/01/04,
function getMemoryMap() {
    echo "$(date +%F-%H:%M:%S) dumpSystem:memory map start...." >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
    LI=0
    LMI=4
    LMM=0
    MEMORY=921600
    PROCESS_MEMORY=819200
    RESIDUE_MEMORY=`cat proc/meminfo | grep MemAvailable | tr -cd "[0-9]"`
    if [ $RESIDUE_MEMORY -lt $MEMORY ] ; then
        while read -r line
        do
            if [ $LI -gt $LMM -a $LI -lt $LMI ] ; then
                let LI=$LI+1;
                echo $line
                PROMEM=`echo $line | grep -o '.*K' | tr -cd "[0-9]"`
                echo $PROMEM
                PID=`echo $line | grep -o '(.*)' | tr -cd "[0-9]"`
                echo $PID
                if [ $PROMEM -gt $PROCESS_MEMORY ] ; then
                    cat proc/$PID/smaps > ${outputPath}/pid$PID-smaps.txt
                    dumpsys meminfo $PID > ${outputPath}/pid$PID-dumpsysmen.txt
                fi
                if [ $LI -eq $LMI ] ; then
                    break
                fi
            fi
            if [ "$line"x = "Total PSS by process:"x ] ; then
                echo $line
                let LI=$LI+1;
            fi
        done < ${outputPath}/dumpsys_mem.txt
    fi
    echo "$(date +%F-%H:%M:%S) dumpSystem:memory map done...." >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
}
#endif /* VENDOR_EDIT */

function dumpWechatInfo() {
    echo "$(date +%F-%H:%M:%S) dumpWechatInfo:start...." >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
    timeSub=`getprop persist.sys.com.oppo.debug.time`
    wechatPath="${DATA_LOG_PATH}/${timeSub}/SI_stop/wechat"
    echo "$(date +%F-%H:%M:%S) dumpWechatInfo:${wechatPath}"
    echo "$(date +%F-%H:%M:%S) dumpWechatInfo:${wechatPath}" >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
    mkdir -p ${wechatPath}

    rm -rf ${wechatPath}/finish_weixin
    dumpsys meminfo --package system > ${wechatPath}/system_meminfo.txt
    dumpsys meminfo --package com.tencent.mm > ${wechatPath}/weixin_meminfo.txt
    CURTIME=`date +%F-%H-%M-%S`
    ps -A | grep "tencent.mm" > ${wechatPath}/weixin_${CURTIME}_ps.txt
    wechat_exdevice=`pgrep -f com.tencent.mm`
    if  [ ! -n "$wechat_exdevice" ] ;then
        touch ${wechatPath}/finish_weixin
    else
        echo "$wechat_exdevice" | while read line
        do
        cat /proc/${line}/smaps > ${wechatPath}/weixin_${line}.txt
        done
    fi
    setprop sys.tranfer.finished mv:wechat
    dumpsys package > ${wechatPath}/dumpsys_package.txt
    touch ${wechatPath}/finish_weixin

    echo "$(date +%F-%H:%M:%S) dumpWechatInfo:done...." >> ${SDCARD_LOG_BASE_PATH}/tranfer2.info
}

function DumpWechatMeminfo() {
    CURTIME=`date +%F-%H-%M-%S`
    outputPath="${SDCARD_LOG_BASE_PATH}/trigger/wechat_${CURTIME}"
    mkdir -p ${outputPath}
    rm -f ${outputPath}/finish_weixin
    touch ${SDCARD_LOG_BASE_PATH}/test
    echo "===============" >> ${SDCARD_LOG_BASE_PATH}/test
    echo ${outputPath} >> ${SDCARD_LOG_BASE_PATH}/test
    dumpsys meminfo --package system > ${outputPath}/system_meminfo.txt
    dumpsys meminfo --package com.tencent.mm > ${outputPath}/weixin_meminfo.txt
    CURTIME=`date +%F-%H-%M-%S`
    ps -A | grep "tencent.mm" > ${outputPath}/weixin_${CURTIME}_ps.txt
    wechat_exdevice=`pgrep -f com.tencent.mm`
    echo "$wechat_exdevice" >> ${SDCARD_LOG_BASE_PATH}/test
    if  [ ! -n "$wechat_exdevice" ] ;then
        touch ${outputPath}/finish_weixin
    else
        echo "$wechat_exdevice" | while read line
        do
        cat /proc/${line}/smaps > ${outputPath}/weixin_${line}.txt
        done
    fi
    dumpsys package > ${outputPath}/dumpsysy_package.txt
    touch ${outputPath}/finish_weixin
    echo "DumpMeminfo done" >> ${SDCARD_LOG_BASE_PATH}/test
    rm -f ${SDCARD_LOG_BASE_PATH}/test
}

function DumpStorage() {
    rm -rf ${SDCARD_LOG_BASE_PATH}/storage
    mkdir -p ${SDCARD_LOG_BASE_PATH}/storage
    mount > ${SDCARD_LOG_BASE_PATH}/storage/mount.txt
    dumpsys devicestoragemonitor > ${SDCARD_LOG_BASE_PATH}/storage/dumpsys_devicestoragemonitor.txt
    dumpsys mount > ${SDCARD_LOG_BASE_PATH}/storage/dumpsys_mount.txt
    dumpsys diskstats > ${SDCARD_LOG_BASE_PATH}/storage/dumpsys_diskstats.txt
    du -H /data > ${SDCARD_LOG_BASE_PATH}/storage/diskUsage.txt
    echo "DumpStorage done"
}
#Fei.Mo@PSW.BSP.Sensor, 2017/09/05 ,Add for power monitor top info
function thermalTop(){
   top -m 3 -n 1 > /data/system/dropbox/thermalmonitor/top
   chown system:system /data/system/dropbox/thermalmonitor/top
}
#end, Add for power monitor top info

#Canjie.Zheng@PSW.AD.OppoDebug.LogKit.1078692, 2017/11/20, Add for iotop
function getiotop() {
    panicenable=`getprop persist.sys.assert.panic`
    camerapanic=`getprop persist.sys.assert.panic.camera`
    if [ x"${panicenable}" = x"true" ] || [ x"${camerapanic}" = x"true" ]; then
        APPS_LOG_PATH=`getprop sys.oppo.logkit.appslog`
        iotop=${APPS_LOG_PATH}/iotop.txt
        timestamp=`date +"%m-%d %H:%M:%S"\(timestamp\)`
        echo ${timestamp} >> ${iotop}
        iotop -m 5 -n 5 -P >> ${iotop}
    fi
}

#Fangfang.Hui@PSW.TECH.AD.OppoDebug.LogKit.1078692, 2019/03/07, Add for mount mnt/vendor/opporeserve/stamp to data/oppo/log/stamp
#Xufeifei@Network.Data.Diagtools,2020/7/3, Add to touch DATA_STAMP_DATA_BASE_FILE to chmod it
function remount_opporeserve2_stamp_to_data()
{
    DATA_STAMP_MOUNT_POINT="/data/oppo/log/stamp"
    OPPORESERVE_STAMP_MOUNT_POINT="/mnt/vendor/opporeserve/media/log/stamp"
    OPPORESERVE_STAMP_DATABASE_FILE="/mnt/vendor/opporeserve/media/log/stamp/stamp.db"
    if [ ! -d ${DATA_STAMP_MOUNT_POINT} ]; then
        mkdir ${DATA_STAMP_MOUNT_POINT}
    fi
    chmod -R 0777 ${DATA_STAMP_MOUNT_POINT}
    chown -R system ${DATA_STAMP_MOUNT_POINT}
    chgrp -R system ${DATA_STAMP_MOUNT_POINT}
    if [ ! -d ${OPPORESERVE_STAMP_MOUNT_POINT} ]; then
        mkdir ${OPPORESERVE_STAMP_MOUNT_POINT}
    fi
    touch ${OPPORESERVE_STAMP_DATABASE_FILE}
    chmod -R 0777 ${OPPORESERVE_STAMP_MOUNT_POINT}
    chown -R system ${OPPORESERVE_STAMP_MOUNT_POINT}
    chgrp -R system ${OPPORESERVE_STAMP_MOUNT_POINT}
    mount ${OPPORESERVE_STAMP_MOUNT_POINT} ${DATA_STAMP_MOUNT_POINT}
    restorecon -RF ${DATA_STAMP_MOUNT_POINT}
}
# Kun.Hu@TECH.BSP.Stability.Phoenix, 2019/4/17, fix the core domain limits to search hang_oppo dirent
function remount_opporeserve2()
{
    HANGOPPO_DIR_REMOUNT_POINT="/data/oppo/log/opporeserve/media/log/hang_oppo"
    if [ ! -d ${HANGOPPO_DIR_REMOUNT_POINT} ]; then
        mkdir -p ${HANGOPPO_DIR_REMOUNT_POINT}
    fi
    chmod -R 0770 /data/oppo/log/opporeserve
    chgrp -R system /data/oppo/log/opporeserve
    chown -R system /data/oppo/log/opporeserve
    mount /mnt/vendor/opporeserve/media/log/hang_oppo ${HANGOPPO_DIR_REMOUNT_POINT}
}


# wenjie.liu@CN.NFC.Basic.Hardware, 2019/4/24, fix the core domain limits to search /mnt/vendor/opporeserve/connectivity
function remount_opporeserve2_felica_to_data()
{
devinfo=`cat /proc/oppoVersion/prjVersion`
if [ "$devinfo" == "18383" ]; then
    #felicalock felica.cfg
    DATAOPPORESERVE_CONNECTIVITY_FELICA_REMOUNT_POINT="/data/oppo/log/opporeserve/connectivity/felicalock"
    DATAOPPORESERVE_CONNECTIVITY_REMOUNT_POINT="/data/oppo/log/opporeserve/connectivity"
    OPPORESERVE_CONNECTIVITY_FELICA_REMOUNT_POINT="/mnt/vendor/opporeserve/connectivity"

    if [ ! -d ${DATAOPPORESERVE_CONNECTIVITY_REMOUNT_POINT} ]; then
        mkdir -p ${DATAOPPORESERVE_CONNECTIVITY_REMOUNT_POINT}
    fi
    mount ${OPPORESERVE_CONNECTIVITY_FELICA_REMOUNT_POINT}  ${DATAOPPORESERVE_CONNECTIVITY_REMOUNT_POINT}
    #create felica.cfg
    if [ ! -f "/data/oppo/log/opporeserve/connectivity/felicalock/felica.cfg" ]; then
        cp  /vendor/etc/felica.cfg  /data/oppo/log/opporeserve/connectivity/felicalock/felica.cfg
        if  [ ! -f "/data/oppo/log/opporeserve/connectivity/init.cfg" ]; then
            echo boot_done > /data/oppo/log/opporeserve/connectivity/init.cfg
        fi
    fi
    #chown
    chmod -R 0777 /data/oppo/log/opporeserve
    chown nfc:nfc /data/oppo/log/opporeserve/connectivity/felicalock/felica.cfg

    #setprop remount = true
    setprop persist.sys.nfc.felica.remount true
    #nfclock/
    DATAOPPORESERVE_MEDIA_NFCLOCK_REMOUNT_POINT="/data/oppo/log/opporeserve/media/nfclock"
    OPPORESERVE_MEDIA_NFCLOCK_REMOUNT_POINT="/mnt/vendor/opporeserve/media/nfclock"
    if [ ! -d ${DATAOPPORESERVE_MEDIA_NFCLOCK_REMOUNT_POINT} ]; then
        mkdir -p ${DATAOPPORESERVE_MEDIA_NFCLOCK_REMOUNT_POINT}
        #change permission
    fi
    chmod -R 0770 ${DATAOPPORESERVE_MEDIA_NFCLOCK_REMOUNT_POINT}
    chown -R system:system ${DATAOPPORESERVE_MEDIA_NFCLOCK_REMOUNT_POINT}
    mount ${OPPORESERVE_MEDIA_NFCLOCK_REMOUNT_POINT} ${DATAOPPORESERVE_MEDIA_NFCLOCK_REMOUNT_POINT}
fi
}

#Liang.Zhang@TECH.Storage.Stability.OPPO_SHUTDOWN_DETECT, 2019/04/28, Add for shutdown detect
function remount_opporeserve2_shutdown()
{
    OPPORESERVE2_REMOUNT_POINT="/data/oppo/log/opporeserve/media/log/shutdown"
    if [ ! -d ${OPPORESERVE2_REMOUNT_POINT} ]; then
        mkdir ${OPPORESERVE2_REMOUNT_POINT}
    fi
    chmod 0770 /data/oppo/log/opporeserve
    chgrp system /data/oppo/log/opporeserve
    chown system /data/oppo/log/opporeserve
    mount /mnt/vendor/opporeserve/media/log/shutdown ${OPPORESERVE2_REMOUNT_POINT}
}

#Weitao.Chen@PSW.AD.Stability.Crash.1295294, 2018/03/01, Add for trying to recover from sysetm hang
function recover_hang()
{
 #recover_hang_path="/data/system/dropbox/recover_hang"
 #persist.sys.oppo.scanstage is true recovery_hang service is started
 #sleep 40s for scan system to finish
 sleep 40
 scan_system_status=`getprop persist.sys.oppo.scanstage`
 if [ x"${scan_system_status}" == x"true" ]; then
    #after 20s, scan system has not finished, use debuggerd to catch system_server native trace
    system_server_pid=`ps -A | grep system_server | $XKIT awk '{print $2}'`
    debuggerd -b ${system_server_pid} > /data/system/dropbox/recover_hang_${system_server_pid}_$(date +%F-%H-%M-%S)_40;
 fi
 #sleep 60s for scan data to finish
 sleep 60
 if [ x"${scan_system_status}" == x"1" ]; then
    system_server_pid=`ps -A | grep system_server | $XKIT awk '{print $2}'`
    #use debuggerd to catch system_server native trace
    debuggerd -b ${system_server_pid} > /data/system/dropbox/recover_hang_${system_server_pid}_$(date +%F-%H-%M-%S)_60;
 fi
 boot_completed=`getprop sys.oppo.boot_completed`
 if [ x${boot_completed} != x"1" ]; then
    system_server_pid=`ps -A | grep system_server | $XKIT awk '{print $2}'`
    #use debuggerd to catch system_server native trace
    debuggerd -b ${system_server_pid} > /dev/null;
 fi
}

function delcustomlog() {
    echo "delcustomlog begin"
    rm -rf /data/oppo_log/customer
    echo "delcustomlog end"
}

function customdmesg() {
    echo "customdmesg begin"
    chmod 777 -R data/oppo_log/
    echo "customdmesg end"
}

function customdiaglog() {
    echo "customdiaglog begin"
    mv data/vendor/oppo/log/device_log/diag_logs /data/oppo_log/customer
    chmod 777 -R /data/oppo_log/customer
    restorecon -RF /data/oppo_log/customer
    echo "customdiaglog end"
}

function cleanramdump() {
    echo "cleanramdump begin"
    rm -rf /data/ramdump/*
    echo "cleanramdump end"
}

function mvrecoverylog() {
    echo "mvrecoverylog begin"
    mkdir -p ${SDCARD_LOG_BASE_PATH}/recovery_log
    mv /cache/recovery/* ${SDCARD_LOG_BASE_PATH}/recovery_log
    echo "mvrecoverylog end"
}

function writenoop() {
    echo "writenoop begin"
    echo noop > /sys/block/dm-0/queue/scheduler
    echo noop > /sys/block/sda/queue/scheduler
    echo "writenoop end"
}

function writecfq() {
    echo "writecfq begin"
    echo cfq > /sys/block/dm-0/queue/scheduler
    echo cfq > /sys/block/sda/queue/scheduler
    echo "writecfq end"
}

function save_latest_log() {
    echo "save_latest_log begin"
    LATEST_APPS_LOG_PATH=`getprop sys.oppo.logkit.appslog`
    LATEST_LOG_MAX_NUM=7
    LATEST_LOG_IDX=0
    if [ -d ${LATEST_APPS_LOG_PATH} ]; then
        LOGTIME=`date +%F-%H-%M-%S`
        CAMERA_LOG_DIR=${SDCARD_LOG_BASE_PATH}/camera_monkey_log/log_${LOGTIME}
        mkdir -p ${CAMERA_LOG_DIR}
        ALL_FILE=`ls -t ${LATEST_APPS_LOG_PATH}`
        for i in $ALL_FILE;
        do
            echo "now we have latest log file $i"
            let LATEST_LOG_IDX=$LATEST_LOG_IDX+1;
            echo ========file num is $LATEST_LOG_IDX===========
            if [ "$LATEST_LOG_IDX" -lt $LATEST_LOG_MAX_NUM ] ; then
               echo  $i\!;
               cp  ${LATEST_APPS_LOG_PATH}/$i ${CAMERA_LOG_DIR}/
            fi
        done
    fi
    LATEST_KENEL_LOG_PATH=`getprop sys.oppo.logkit.kernellog`
    LATEST_KENEL_LOG_MAX_NUM=7
    LATEST_KENEL_LOG_IDX=0
    if [ -d ${LATEST_KENEL_LOG_PATH} ]; then
        LOGTIME=`date +%F-%H-%M-%S`
        CAMERA_LOG_DIR_KENELLOG_DIR=${SDCARD_LOG_BASE_PATH}/camera_monkey_log/kenel_log_${LOGTIME}
        mkdir -p ${CAMERA_LOG_DIR_KENELLOG_DIR}
        ALL_FILE=`ls -t ${LATEST_KENEL_LOG_PATH}`
        for i in $ALL_FILE;
        do
            echo "now we have latest kenel log file $i"
            let LATEST_KENEL_LOG_IDX=$LATEST_KENEL_LOG_IDX+1;
            echo ========kenel log file num is $LATEST_KENEL_LOG_IDX===========
            if [ "$LATEST_KENEL_LOG_IDX" -lt $LATEST_KENEL_LOG_MAX_NUM ] ; then
               echo  $i\!;
               cp  ${LATEST_KENEL_LOG_PATH}/$i ${CAMERA_LOG_DIR_KENELLOG_DIR}/
            fi
        done
    fi
    echo "save_latest_log end"
}

function logcusmain() {
    echo "logcusmain begin"
    path=/data/oppo_log/customer/apps
    mkdir -p ${path}
    /system/bin/logcat  -f ${path}/android.txt -r10240 -v threadtime *:V
    echo "logcusmain end"
}

function logcusevent() {
    echo "logcusevent begin"
    path=/data/oppo_log/customer/apps
    mkdir -p ${path}
    /system/bin/logcat -b events -f ${path}/event.txt -r10240 -v threadtime *:V
    echo "logcusevent end"
}

function logcusradio() {
    echo "logcusradio begin"
    path=/data/oppo_log/customer/apps
    mkdir -p ${path}
    /system/bin/logcat -b radio -f ${path}/radio.txt -r10240 -v threadtime *:V
    echo "logcusradio end"
}

function logcuskernel() {
    echo "logcuskernel begin"
    path=/data/oppo_log/customer/kernel
    mkdir -p ${path}
    dmesg > /data/oppo_log/customer/kernel/dmesg.txt
    /system/xbin/klogd -f - -n -x -l 7 | $XKIT tee - ${path}/kinfo0.txt | $XKIT awk 'NR%400==0'
    echo "logcuskernel end"
}

function logcustcp() {
    echo "logcustcp begin"
    path=/data/oppo_log/customer/tcpdump
    mkdir -p ${path}
    tcpdump -i any -p -s 0 -W 1 -C 50 -w ${path}/tcpdump.pcap  -Z root
    echo "logcustcp end"
}

function logcuswifi() {
    echo "logcuswifi begin"
    path=/data/oppo_log/customer/buffered_wlan_logs
    mkdir -p ${path}
    #pid=`ps -A | grep cnss_diag | tr -s ' ' | cut -d ' ' -f 2`
    pid=`getprop vendor.oppo.wifi.cnss_diag_pid`
    if [ "$pid" != "" ]
    then
        kill -SIGUSR1 $pid
    fi
    cat /proc/ath_pktlog/cld > ${path}/pktlog.dat
    sleep 2
    cp /data/vendor/wifi/buffered_wlan_logs/* ${path}
    rm /data/vendor/wifi/buffered_wlan_logs/*
    setprop sys.oppo.log.customer.wifi true
    echo "logcuswifi end"
}
function logcusqmistart() {
    echo "logcusqmistart begin"
    echo 0x2 > /sys/module/ipc_router_core/parameters/debug_mask
    #add for SM8150 platform
    if [ -d "/d/ipc_logging" ]; then
        path=/data/oppo_log/customer/ipc_log
        mkdir -p ${path}
        cat /d/ipc_logging/adsp/log > ${path}/adsp_glink.txt
        cat /d/ipc_logging/modem/log > ${path}/modem_glink.txt
        cat /d/ipc_logging/cdsp/log > ${path}/cdsp_glink.txt
        cat /d/ipc_logging/qrtr_0/log > ${path}/modem_qrtr.txt
        cat /d/ipc_logging/qrtr_5/log > ${path}/sensor_qrtr.txt
        cat /d/ipc_logging/qrtr_10/log > ${path}/NPU_qrtr.txt
        /vendor/bin/qrtr-lookup > ${path}/qrtr-lookup_start.txt
    fi
    echo "logcusqmistart end"
}
function logcusqmistop() {
    echo "logcusqmistop begin"
    echo 0x0 > /sys/module/ipc_router_core/parameters/debug_mask
    path=/data/oppo_log/customer/ipc_log
    mkdir -p ${path}
    /vendor/bin/qrtr-lookup > ${path}/qrtr-lookup_stop.txt
    echo "logcusqmistop end"
}
function chmodmodemconfig() {
    echo "chmodmodemconfig begin"
    chmod 777 -R data/oppo/log/modem_log/config/
    mkdir -p data/vendor/oppo/log/device_log/config
    cp -r data/oppo/log/modem_log/config/* data/vendor/oppo/log/device_log/config
    chmod 777 -R data/vendor/oppo
    echo "chmodmodemconfig end"
}

function setdebugoff() {
    is_camera =`getprop persist.sys.assert.panic.camera`
    if [ x"${is_camera}" = x"true" ]; then
        setprop persist.sys.assert.panic.camera false
    else
        setprop persist.sys.assert.panic false
    fi
}

#Jian.Wang@PSW.CN.WiFi.Basic.Log.1162003, 2018/7/02, Add for dynamic collect wifi mini dump
function enablewifidump(){
    echo dynamic_feature_mask 0x01 > /d/icnss/fw_debug
    echo 0x01 > /sys/module/icnss/parameters/dynamic_feature_mask
}

function disablewifidump(){
    echo dynamic_feature_mask 0x11 > /d/icnss/fw_debug
    echo 0x11 > /sys/module/icnss/parameters/dynamic_feature_mask
}

function  touchwifiminidumpfile(){
    touch data/misc/wifi/minidump/minidumpfile1
    sleep 5
    rm data/misc/wifi/minidump/minidumpfile1
}

function collectwifidmesg(){
    WIFI_DUMP_PARENT_DIR=/data/vendor/tombstones/
    WIFI_DUMP_PATH=/data/vendor/tombstones/rfs/modem
    DCS_WIFI_LOG_PATH=/data/oppo/log/DCS/de/network_logs/wifi
    WIFI_DUMP_MONITOR=/data/misc/wifi/minidump
    DATA_MISC_WIFI=/data/misc/wifi/
    if [ ! -d ${DCS_WIFI_LOG_PATH} ];then
        mkdir -p ${DCS_WIFI_LOG_PATH}
    fi
    chown -R system:system ${DCS_WIFI_LOG_PATH}
    chmod -R 777 ${WIFI_DUMP_PARENT_DIR}
    chmod -R 777 ${WIFI_DUMP_PATH}

    zip_name=`getprop persist.sys.wifi.minidump.zipPath`
    product_board=`getprop ro.product.board`
    dmesg > ${WIFI_DUMP_PATH}/kernel.txt

    board=`getprop ro.board.platform`
    #echo "board:  ${board}"
    if [ "x${board}" == "xkona" ];then
        mv /data/vendor/ramdump/ramdump_wlan* ${WIFI_DUMP_PATH}
        reason=`dmesg | grep cmnos_thread.c | sed -n '$p'`
        #echo "reason:1 : ${reason}"
        reason=`echo ${reason#*mhi_process_sfr] }`
        #echo "reason:2 : ${reason}"
        setprop persist.wifi.minidump.failureDesc "${reason}"
    fi
    sleep 2
    dewifiminidumpcount=`ls -l /data/oppo/log/DCS/de/network_logs/wifi  | grep "^-" | wc -l`
    enwifiminidumpcount=`ls -l /data/oppo/log/DCS/en/network_logs/wifi  | grep "^-" | wc -l`
    if [ $dewifiminidumpcount -lt 10 ] && [ $enwifiminidumpcount -lt 10 ];then
        $XKIT tar -czvf  ${DCS_WIFI_LOG_PATH}/${zip_name}.tar.gz -C ${WIFI_DUMP_PATH} ${WIFI_DUMP_PATH}
    fi
    chown -R system:system ${DCS_WIFI_LOG_PATH}
    chmod -R 777 ${DCS_WIFI_LOG_PATH}
    rm -rf ${WIFI_DUMP_PATH}/*

    chown -R system:system ${WIFI_DUMP_PARENT_DIR}
    chmod -R 776 ${WIFI_DUMP_PARENT_DIR}
    chmod -R 776 ${WIFI_DUMP_PATH}
}

function skipscollectwifidmesg(){
    enablewififulldump=`getprop oppo.wifi.enablefulldump`
    enablewifiminidump=`getprop oppo.wifi.enableminidump`
    enablefulldump=`getprop persist.sys.dump`
    if [ "x${enablewififulldump}" = "xtrue" ] && [ "x${enablefulldump}" = "x1" ];then
        echo 1 > /sys/bus/platform/drivers/icnss/wlan_fw_crash_panic
    elif [ "x${enablewifiminidump}" = "xfalse" ];then
        WIFI_DUMP_PATH=/data/vendor/tombstones/rfs/modem
        chmod -R 777 ${WIFI_DUMP_PATH}
        rm -rf ${WIFI_DUMP_PATH}/*
        chmod -R 776 ${WIFI_DUMP_PATH}
    else
        touch data/misc/wifi/minidump/minidumpfile1
        sleep 5
        rm data/misc/wifi/minidump/minidumpfile1
    fi
}

#end, Add for dynamic collect wifi mini dump

#ifdef VENDOR_EDIT
#Laixin@PSW.CN.WiFi.Basic.Switch.1069763, 2018/09/03
#Add for: collect Wifi Switch Log
function collectWifiSwitchLog() {
    boot_completed=`getprop sys.boot_completed`
    while [ x${boot_completed} != x"1" ];do
        sleep 2
        boot_completed=`getprop sys.boot_completed`
    done
    wifiSwitchLogPath="/data/oppo_log/wifi_switch_log"
    if [ ! -d  ${wifiSwitchLogPath} ];then
        mkdir -p ${wifiSwitchLogPath}
    fi

    # collect driver and firmware log
    cnss_pid=`getprop vendor.oppo.wifi.cnss_diag_pid`
    if [[ "w${cnss_pid}" != "w" ]];then
        kill -s SIGUSR1 $cnss_pid
        sleep 2
        mv /data/vendor/wifi/buffered_wlan_logs/* $wifiSwitchLogPath
        chmod 666 ${wifiSwitchLogPath}/buffered*
    fi

    dmesg > ${wifiSwitchLogPath}/dmesg.txt
    /system/bin/logcat -b main -b system -f ${wifiSwitchLogPath}/android.txt -r10240 -v threadtime *:V
}

function packWifiSwitchLog() {
    wifiSwitchLogPath="/data/oppo_log/wifi_switch_log"
    sdcard_oppolog="${SDCARD_LOG_BASE_PATH}"
    DCS_WIFI_LOG_PATH="/data/oppo/log/DCS/de/network_logs/wifiSwitch"
    logReason=`getprop oppo.wifi.switch.log.reason`
    logFid=`getprop oppo.wifi.switch.log.fid`
    version=`getprop ro.build.version.ota`

    if [ "w${logReason}" == "w" ];then
        return
    fi

    if [ ! -d ${DCS_WIFI_LOG_PATH} ];then
        mkdir -p ${DCS_WIFI_LOG_PATH}
        chown system:system ${DCS_WIFI_LOG_PATH}
        chmod -R 777 ${DCS_WIFI_LOG_PATH}
    fi

    if [ "${logReason}" == "wifi_service_check" ];then
        file=`ls ${SDCARD_LOG_BASE_PATH} | grep ${logReason}`
        abs_file=${sdcard_oppolog}/${file}
        echo ${abs_file}
    else
        if [ ! -d  ${wifiSwitchLogPath} ];then
            return
        fi
        $XKIT tar -czvf  ${DCS_WIFI_LOG_PATH}/${logReason}.tar.gz -C ${wifiSwitchLogPath} ${wifiSwitchLogPath}
        abs_file=${DCS_WIFI_LOG_PATH}/${logReason}.tar.gz
    fi
    fileName="wifi_turn_on_failed@${logFid}@${version}@${logReason}.tar.gz"
    mv ${abs_file} ${DCS_WIFI_LOG_PATH}/${fileName}
    chown system:system ${DCS_WIFI_LOG_PATH}/${fileName}
    setprop sys.oppo.wifi.switch.log.stop 0
    rm -rf ${wifiSwitchLogPath}
}

#Gong Tao@PSW.CN.WiFi.Connect.Connect.1065680, 2020/03/16,
#Add for collect wifi connect fail log
function collectWifiConnectFailLog() {
    boot_completed=`getprop sys.boot_completed`
    while [ x${boot_completed} != x"1" ];do
        sleep 2
        boot_completed=`getprop sys.boot_completed`
    done
    wifiConnectFailLogPath="/data/oppo_log/wifi_connect_fail_log"
    if [ ! -d  ${wifiConnectFailLogPath} ];then
        mkdir -p ${wifiConnectFailLogPath}
    fi

    # collect driver and firmware log
    cnss_pid=`getprop vendor.oppo.wifi.cnss_diag_pid`
    if [[ "w${cnss_pid}" != "w" ]];then
        kill -s SIGUSR1 $cnss_pid
        sleep 2
        mv /data/vendor/wifi/buffered_wlan_logs/* $wifiConnectFailLogPath
        chmod 666 ${wifiConnectFailLogPath}/buffered*
    fi

    dmesg > ${wifiConnectFailLogPath}/dmesg.txt
    /system/bin/logcat -b main -b system -f ${wifiConnectFailLogPath}/android.txt -r10240 -v threadtime *:V
}

function packWifiConnectFailLog() {
    wifiConnectFailLogPath="/data/oppo_log/wifi_connect_fail_log"
    sdcard_oppolog="${SDCARD_LOG_BASE_PATH}"
    DCS_WIFI_LOG_PATH="/data/oppo/log/DCS/de/network_logs/wfd_connect_fail"
    logReason="connect_fail"
    logFid=`getprop oppo.wifi.connect.fail.log.fid`
    version=`getprop ro.build.version.ota`

    #if [ "w${logReason}" == "w" ];then
    #    return
    #fi

    if [ ! -d ${DCS_WIFI_LOG_PATH} ];then
        mkdir -p ${DCS_WIFI_LOG_PATH}
        chown system:system ${DCS_WIFI_LOG_PATH}
        chmod -R 777 ${DCS_WIFI_LOG_PATH}
    fi

    if [ "${logReason}" == "wifi_service_check" ];then
        file=`ls ${SDCARD_LOG_BASE_PATH} | grep ${logReason}`
        abs_file=${sdcard_oppolog}/${file}
        echo ${abs_file}
    else
        if [ ! -d  ${wifiConnectFailLogPath} ];then
            return
        fi
        $XKIT tar -czvf  ${DCS_WIFI_LOG_PATH}/${logReason}.tar.gz -C ${wifiConnectFailLogPath} ${wifiConnectFailLogPath}
        abs_file=${DCS_WIFI_LOG_PATH}/${logReason}.tar.gz
    fi
    fileName="wifi_connect_fail@${logFid}@${version}@${logReason}.tar.gz"
    mv ${abs_file} ${DCS_WIFI_LOG_PATH}/${fileName}
    chown system:system ${DCS_WIFI_LOG_PATH}/${fileName}
    setprop sys.oppo.wifi.connectfail.log.stop 0
    rm -rf ${wifiConnectFailLogPath}
}

#Guotian.Wu add for wifi p2p connect fail log
function collectWifiP2pLog() {
    boot_completed=`getprop sys.boot_completed`
    while [ x${boot_completed} != x"1" ];do
        sleep 2
        boot_completed=`getprop sys.boot_completed`
    done
    wifiP2pLogPath="/data/oppo_log/wifi_p2p_log"
    if [ ! -d  ${wifiP2pLogPath} ];then
        mkdir -p ${wifiP2pLogPath}
    fi

    # collect driver and firmware log
    cnss_pid=`getprop vendor.oppo.wifi.cnss_diag_pid`
    if [[ "w${cnss_pid}" != "w" ]];then
        kill -s SIGUSR1 $cnss_pid
        sleep 2
        mv /data/vendor/wifi/buffered_wlan_logs/* $wifiP2pLogPath
        chmod 666 ${wifiP2pLogPath}/buffered*
    fi

    dmesg > ${wifiP2pLogPath}/dmesg.txt
    /system/bin/logcat -b main -b system -f ${wifiP2pLogPath}/android.txt -r10240 -v threadtime *:V
}

function packWifiP2pFailLog() {
    wifiP2pLogPath="/data/oppo_log/wifi_p2p_log"
    DCS_WIFI_LOG_PATH=`getprop oppo.wifip2p.connectfail`
    logReason=`getprop oppo.wifi.p2p.log.reason`
    logFid=`getprop oppo.wifi.p2p.log.fid`
    version=`getprop ro.build.version.ota`

    if [ "w${logReason}" == "w" ];then
        return
    fi

    if [ ! -d ${DCS_WIFI_LOG_PATH} ];then
        mkdir -p ${DCS_WIFI_LOG_PATH}
        chown system:system ${DCS_WIFI_LOG_PATH}
        chmod -R 777 ${DCS_WIFI_LOG_PATH}
    fi

    if [ ! -d  ${wifiP2pLogPath} ];then
        return
    fi

    $XKIT tar -czvf  ${DCS_WIFI_LOG_PATH}/${logReason}.tar.gz -C ${wifiP2pLogPath} ${wifiP2pLogPath}
    abs_file=${DCS_WIFI_LOG_PATH}/${logReason}.tar.gz

    fileName="wifip2p_connect_fail@${logFid}@${version}@${logReason}.tar.gz"
    mv ${abs_file} ${DCS_WIFI_LOG_PATH}/${fileName}
    chown system:system ${DCS_WIFI_LOG_PATH}/${fileName}
    setprop sys.oppo.wifi.p2p.log.stop 0
    rm -rf ${wifiP2pLogPath}
}

# not support yet
function mvWifiSwitchLog() {
    DCS_WIFI_LOG_PATH="/data/oppo/log/DCS/de/network_logs/wifiSwitch"
    DCS_WIFI_CELLULAR_LOG_PATH="/data/oppo/log/DCS/de/network_logs/wifiSwitchByCellular"

    if [ ! -d ${DCS_WIFI_CELLULAR_LOG_PATH} ];then
        mkdir -p ${DCS_WIFI_CELLULAR_LOG_PATH}
        chmod -R 777 ${DCS_WIFI_CELLULAR_LOG_PATH}
    fi
    mv ${DCS_WIFI_LOG_PATH}/* ${DCS_WIFI_CELLULAR_LOG_PATH}
}
#endif /* VENDOR_EDIT */

#ifdef VENDOR_EDIT
#Xiao.Liang@PSW.CN.WiFi.Basic.Log.1072015, 2018/10/22, Add for collecting wifi driver log
function setiwprivpkt0() {
    iwpriv wlan0 pktlog 0
}

function setiwprivpkt1() {
    iwpriv wlan0 pktlog 1
}

function setiwprivpkt4() {
    iwpriv wlan0 pktlog 4
}
#endif /*VENDOR_EDIT*/

#ifdef VENDOR_EDIT
#Zaogen.Hong@PSW.CN.WiFi.Connect,2020/03/03, Add for trigger wifi dump by engineerMode
function wifi_minidump() {
    iwpriv wlan0 setUnitTestCmd 19 1 4
}
#endif /*VENDOR_EDIT*/

#ifdef VENDOR_EDIT
#Xiao.Liang@PSW.CN.WiFi.Basic.SoftAP.1610391, 2018/10/30, Modify for reading client devices name from /data/misc/dhcp/dnsmasq.leases
function changedhcpfolderpermissions(){
    state=`getprop oppo.wifi.softap.readleases`
    if [ "${state}" = "true" ] ;then
        chmod -R 0775 /data/misc/dhcp/
    else
        chmod -R 0770 /data/misc/dhcp/
    fi
}
#endif /* VENDOR_EDIT */

#ifdef VENDOR_EDIT
#Xuefeng.Peng@PSW.AD.Performance.Storage.1721598, 2018/12/26, Add for abnormal sd card shutdown long time
function fsck_shutdown() {
    needshutdown=`getprop persist.sys.fsck_shutdown`
    if [ x"${needshutdown}" == x"true" ]; then
        setprop persist.sys.fsck_shutdown "false"
        ps -A | grep fsck.fat  > /data/media/0/fsck_fat
        #echo "fsck test start" >> /data/media/0/fsck.txt

        #DATE=`date +%F-%H-%M-%S`
        #echo "${DATE}" >> /data/media/0/fsck.txt
        #echo "fsck test end" >> /data/media/0/fsck.txt
    fi
}

#Xuefeng.Peng@PSW.AD.Performance.Storage.1721598, 2018/12/26, Add for customize version to control sdcard
#Kang.Zou@PSW.AD.Performance.Storage.1721598, 2019/10/17, Add for customize version to control sdcard with new methods
function exstorage_support() {
    exStorage_support=`getprop persist.sys.exStorage_support`
    if [ x"${exStorage_support}" == x"1" ]; then
        #echo 1 > /sys/class/mmc_host/mmc0/exStorage_support
        echo 1 > /sys/bus/mmc/drivers_autoprobe
        mmc_devicename=$(ls /sys/bus/mmc/devices | grep "mmc0:")
        if [ -n "$mmc_devicename" ];then
            echo "$mmc_devicename" > /sys/bus/mmc/drivers/mmcblk/bind
        fi
        #echo "fsck test start" >> /data/media/0/fsck.txt

        #DATE=`date +%F-%H-%M-%S`
        #echo "${DATE}" >> /data/media/0/fsck.txt
        #echo "fsck test end" >> /data/media/0/fsck.txt
    fi
    if [ x"${exStorage_support}" == x"0" ]; then
        #echo 0 > /sys/class/mmc_host/mmc0/exStorage_support
        echo 0 > /sys/bus/mmc/drivers_autoprobe
        mmc_devicename=$(ls /sys/bus/mmc/devices | grep "mmc0:")
        if [ -n "$mmc_devicename" ];then
            echo "$mmc_devicename" > /sys/bus/mmc/drivers/mmcblk/unbind
        fi
        #echo "fsck test111 start" >> /data/media/0/fsck.txt

        #DATE=`date +%F-%H-%M-%S`
        #echo "${DATE}" >> /data/media/0/fsck.txt
        #echo "fsck test111 end" >> /data/media/0/fsck.txt
    fi
}
#endif /*VENDOR_EDIT*/

#ifdef VENDOR_EDIT
#Shuangquan.du@PSW.AD.Recovery.0, 2019/07/03, add for generate runtime prop
function generate_runtime_prop() {
    getprop | sed -r 's|\[||g;s|\]||g;s|: |=|' > /cache/runtime.prop
    chown root:root /cache/runtime.prop
    chmod 600 /cache/runtime.prop
    sync
    backupMinidump
}
#endif

#//Canjie.Zheng@AD.OppoFeature.Kinect.1069892,2019/03/09, Add for kill hidl
function killsensorhidl() {
    pid=`ps -A | grep android.hardware.sensors@1.0-service | tr -s ' ' | cut -d ' ' -f 2`
    kill ${pid}
}

function cameraloginit() {
    logdsize=`getprop persist.logd.size`
    echo "get logdsize ${logdsize}"
    if [ "${logdsize}" = "" ]
    then
        echo "camere init set log size 16M"
         setprop persist.logd.size 16777216
    fi
}

#add for oidt begin
function oidtlogs() {
    setprop sys.oppo.oidtlogs 0
    logTypes=`getprop sys.oppo.logTypes`
    mkdir -p sdcard/OppoStamp
    mkdir -p sdcard/OppoStamp/db
    mkdir -p sdcard/OppoStamp/log/stable
    mkdir -p sdcard/OppoStamp/config
    cp system/etc/sys_stamp_config.xml sdcard/OppoStamp/config/
    cp data/system/sys_stamp_config.xml sdcard/OppoStamp/config/

    if [ "$logTypes" = "" ] || ["$logTypes" = "100"];then
        logStable
        logPerformance
        logPower
    else
        arr=${logTypes//,/ }
        for each in ${arr[*]}
        do
            if [ "$each" = "101" ];then
                logStable
            elif [ "$each" = "102" ];then
                logPerformance
            elif [ "$each" = "103" ];then
                logPower
            fi
        done
    fi

    setprop sys.oppo.logTypes ''
    setprop sys.oppo.oidtlogs 1
}

function logStable(){
    mkdir -p sdcard/OppoStamp/log/stable
    cp -r data/oppo/log/DCS/de/minidump/ sdcard/OppoStamp/log/stable
    cp -r data/oppo/log/DCS/en/minidump/ sdcard/OppoStamp/log/stable
    cp -r data/oppo/log/DCS/en/AEE_DB/ sdcard/OppoStamp/log/stable
    cp -r data/vendor/mtklog/aee_exp/ sdcard/OppoStamp/log/stable
    mkdir -p sdcard/OppoStamp/log/stable/theia
    cp -r data/oppo/log/DCS/de/theia/ sdcard/OppoStamp/log/stable/theia
    cp -r data/oppo/log/DCS/en/theia/ sdcard/OppoStamp/log/stable/theia
}

function logPerformance(){
    mkdir -p sdcard/OppoStamp/log/performance
    cat /proc/meminfo > sdcard/OppoStamp/log/performance/meminfo_fs.txt
    dumpsys meminfo > sdcard/OppoStamp/log/performance/memifon_dump.txt
    cat cat proc/slabinfo > sdcard/OppoStamp/log/performance/slabinfo_fs.txt
}

function logPower(){
    mkdir -p sdcard/OppoStamp/log/power
    #ifdef COLOROS_EDIT
    #SunYi@Rom.Framework, 2019/11/25, add for collect trace_viewer log
    mkdir -p sdcard/OppoStamp/log/power/trace_viewer/de
    mkdir -p sdcard/OppoStamp/log/power/trace_viewer/en
    cp -r /data/oppo/log/DCS/de/trace_viewer sdcard/OppoStamp/log/power/trace_viewer/de
    cp -r /data/oppo/log/DCS/en/trace_viewer sdcard/OppoStamp/log/power/trace_viewer/en
    #am broadcast --user all -a android.intent.action.ACTION_OPPO_SAVE_BATTERY_HISTORY_TO_SD  com.oppo.oppopowermonitor
    #sleep 3
    #endif /* COLOROS_EDIT */
    cp /data/oppo/psw/powermonitor_backup  -r sdcard/OppoStamp/log/power
}
#add for oidt end
#add for change printk
function chprintk() {
    echo "1 6 1 7" >  /proc/sys/kernel/printk
}

#add for malloc debug
#ifdef VENDOR_EDIT
#Yufeng.Liu@Plf.TECH.Performance, 2019/9/3, Add for malloc_debug
function memdebugregister() {
    process=`getprop sys.memdebug.process`
    setprop persist.oppo.mallocdebug.process ${process}
    type=`getprop sys.memdebug.type`
    if [ x"${type}" = x"0" ] || [ x"${type}" = x"1" ]; then
        key="wrap."
        setprop ${key}${process} "LIBC_DEBUG_MALLOC_OPTIONS=backtrace=8"
    fi
    if [ x"${type}" = x"1" ]; then
        setprop sys.memdebug.status 1
        setprop sys.memdebug.reboot false
    else
        setprop sys.memdebug.reboot true
        setprop sys.memdebug.status 0
    fi
}

function memdebugstart() {
    process=`getprop persist.oppo.mallocdebug.process`
    if [ x"${process}" = x"system" ]; then
        pid=`getprop persist.sys.systemserver.pid`
    else
        pid=`getprop sys.memdebug.pid`
    fi
    type=`getprop sys.memdebug.type`
    if [ x"${type}" = x"0" ] || [ x"${type}" = x"2" ]; then
        kill -45 ${pid}
    fi
    setprop sys.memdebug.status 1
    setprop sys.memdebug.reboot false
}

function memdebugdump() {
    process=`getprop persist.oppo.mallocdebug.process`
    if [ x"${process}" = x"system" ]; then
        pid=`getprop persist.sys.systemserver.pid`
    else
        pid=`getprop sys.memdebug.pid`
    fi
    kill -47 ${pid}
    dumpfile_path="/data/oppo/log/DCS/de/quality_log/backtrace_heap.${pid}.txt"
    count=0
    while [ ! -f ${dumpfile_path} ] && [ $count -le 6 ];do
        count=$((count + 1))
        sleep 1
    done
    sleep 2
    mv /data/oppo/log/DCS/de/quality_log/backtrace_heap.${pid}.txt /data/oppo/log/DCS/de/quality_log/backtrace_heap.${process}.${pid}.txt
    chown -R system:system /data/oppo/log/DCS/de/quality_log/backtrace_heap.${process}.${pid}.txt
    setprop sys.memdebug.status 2
}

function memdebugremove() {
    process=`getprop persist.oppo.mallocdebug.process`
    type=`getprop sys.memdebug.type`
    if [ x"${type}" = x"0" ] || [ x"${type}" = x"1" ]; then
        key="wrap."
        setprop ${key}${process} ""
    fi
    setprop sys.memdebug.status 3
    setprop sys.memdebug.process ""
    setprop persist.oppo.mallocdebug.process ""
    setprop sys.memdebug.type ""
    setprop sys.memdebug.pid ""
    if [ x"${type}" = x"1" ]; then
        setprop sys.memdebug.reboot false
    else
        setprop sys.memdebug.reboot true
    fi
}
#endif /* VENDOR_EDIT */

#ifdef VENDOR_EDIT
#Bin.Li@BSP.Fingerprint.Secure 2018/12/27, Add for oae get bootmode
function oae_bootmode(){
    boot_modei_info=`cat /sys/power/app_boot`
    if [ "$boot_modei_info" == "kernel" ]; then
        setprop ro.oae.boot.mode kernel
      else
        setprop ro.oae.boot.mode normal
    fi
}
#endif /* VENDOR_EDIT */

function scan_switch_for_wifiroam() {
    scan_enabled=`getprop oppo.wifi.scan.enabled`
    if [ "x$scan_enabled" == "x1" ]; then
        iwpriv wlan0 setUnitTestCmd 9 2 1 0
        iwpriv wlan0 scan_disable 1
    elif [ "x$scan_enabled" == "x0" ]; then
        iwpriv wlan0 setUnitTestCmd 9 1 1
        iwpriv wlan0 scan_disable 0
    fi
}

#ifdef VENDOR_EDIT
#Baozhu.Yu@NW.MBN, 2019/10/08,add for switchmbn
function switch_mbntype() {
    next_mbntype=`getprop persist.sys.next_mbntype`
    current_mbntype=`getprop persist.sys.current_mbntype`
    nw_lab_test=`getprop persist.sys.nw_lab_test`
    echo "next_mbntype:"$next_mbntype
    echo "current_mbntype:"$current_mbntype
    echo "nw_lab_test:"$nw_lab_test

    if [ "$next_mbntype"x != ""x ]; then
        if [ "$current_mbntype"x != "$next_mbntype"x ]; then
            mount -o rw,remount /dev/block/bootdevice/by-name/modem /vendor/firmware_mnt
            cp /vendor/firmware_mnt/image/modem_pr/mcfg/configs/mcfg_sw/oem_sw_$next_mbntype.txt /vendor/firmware_mnt/image/modem_pr/mcfg/configs/mcfg_sw/oem_sw.txt
            cp /vendor/firmware_mnt/image/modem_pr/mcfg/configs/mcfg_sw/oem_sw_$next_mbntype.dig /vendor/firmware_mnt/image/modem_pr/mcfg/configs/mcfg_sw/mbn_sw.dig
            setprop persist.sys.current_mbntype $next_mbntype
            sync
            mount -o ro,remount /dev/block/bootdevice/by-name/modem /vendor/firmware_mnt
            echo "current_mbntype:"$next_mbntype
        fi
    #else
        #if [ "$nw_lab_test"x == "1"x ] && [ "$current_mbntype"x != "lab"x ]; then
        #    sync
        #   mount -o rw,remount /dev/block/bootdevice/by-name/modem /vendor/firmware_mnt
        #    cp /vendor/firmware_mnt/image/modem_pr/mcfg/configs/mcfg_sw/oem_sw_lab.txt /vendor/firmware_mnt/image/modem_pr/mcfg/configs/mcfg_sw/oem_sw.txt
        #    cp /vendor/firmware_mnt/image/modem_pr/mcfg/configs/mcfg_sw/oem_sw_lab.dig /vendor/firmware_mnt/image/modem_pr/mcfg/configs/mcfg_sw/mbn_sw.dig
        #    sync
        #    mount -o ro,remount /dev/block/bootdevice/by-name/modem /vendor/firmware_mnt
        #    setprop persist.sys.current_mbntype "lab"
        #    echo "nw_lab_test"
        #fi
    fi
}
#endif /* VENDOR_EDIT */

#ifdef VENDOR_EDIT
#Qing.Wu@PSW.AD.Stability.2278668, 2019/09/03, Add for capture binder info
function binderinfocapture() {
    alreadycaped=`getprop sys.debug.binderinfocapture`
    if [ "$alreadycaped" == "1" ] ;then
        return
    fi
    if [ ! -d ${SDCARD_LOG_BASE_PATH}/binder_info/ ];then
    mkdir -p ${SDCARD_LOG_BASE_PATH}/binder_info/
    fi

    LOGTIME=`date +%F-%H-%M-%S`
    BINDER_DIR=${SDCARD_LOG_BASE_PATH}/binder_info/binder_${LOGTIME}
    echo ${BINDER_DIR}
    mkdir -p ${BINDER_DIR}
    cat /d/binder/state > ${BINDER_DIR}/state
    cat /d/binder/stats > ${BINDER_DIR}/stats
    cat /d/binder/transaction_log > ${BINDER_DIR}/transaction_log
    cat /d/binder/transactions > ${BINDER_DIR}/transactions
    ps -A -T > ${BINDER_DIR}/ps.txt

    kill -3 `pidof system_server`
    kill -3 `pidof com.android.phone`
    debuggerd -b `pidof netd` > "/data/anr/debuggerd_netd.txt"
    sleep 10
    cp -r /data/anr/*  ${BINDER_DIR}/
#package log folder to upload if logkit not enable
    logon=`getprop persist.sys.assert.panic`
    if [ ${logon} == "false" ];then
        current=`date "+%Y-%m-%d %H:%M:%S"`
        timeStamp=`date -d "$current" +%s`
        uuid=`cat /proc/sys/kernel/random/uuid`
        #uuid 0df1ed41-e0d6-40e2-8473-cdf7ccbd0d98
        otaversion=`getprop ro.build.version.ota`
        logzipname="/data/oppo/log/DCS/de/quality_log/qp_deadsystem@"${uuid:0-12:12}@${otaversion}@${timeStamp}".tar.gz"
        tar -czf ${logzipname} ${BINDER_DIR}
        chown system:system ${logzipname}
    fi
    setprop sys.debug.binderinfocapture 1
}
#endif /* VENDOR_EDIT */
#ifdef VENDOR_EDIT
#Fuchun.Liao@BSP.CHG.Basic 2019/06/09 modify for black/bright check
function create_black_bright_check_file(){
	if [ ! -d "/data/oppo/log/bsp" ]; then
		mkdir -p /data/oppo/log/bsp
		chmod -R 777 /data/oppo/log/bsp
		chown -R system:system /data/oppo/log/bsp
	fi

	if [ ! -f "/data/oppo/log/bsp/blackscreen_count.txt" ]; then
		touch /data/oppo/log/bsp/blackscreen_count.txt
		echo 0 > /data/oppo/log/bsp/blackscreen_count.txt
	fi
	chmod 0664 /data/oppo/log/bsp/blackscreen_count.txt

	if [ ! -f "/data/oppo/log/bsp/blackscreen_happened.txt" ]; then
		touch /data/oppo/log/bsp/blackscreen_happened.txt
		echo 0 > /data/oppo/log/bsp/blackscreen_happened.txt
	fi
	chmod 0664 /data/oppo/log/bsp/blackscreen_happened.txt

	if [ ! -f "/data/oppo/log/bsp/brightscreen_count.txt" ]; then
		touch /data/oppo/log/bsp/brightscreen_count.txt
		echo 0 > /data/oppo/log/bsp/brightscreen_count.txt
	fi
	chmod 0664 /data/oppo/log/bsp/brightscreen_count.txt

	if [ ! -f "/data/oppo/log/bsp/brightscreen_happened.txt" ]; then
		touch /data/oppo/log/bsp/brightscreen_happened.txt
		echo 0 > /data/oppo/log/bsp/brightscreen_happened.txt
	fi
	chmod 0664 /data/oppo/log/bsp/brightscreen_happened.txt
}
#endif /* VENDOR_EDIT */

#ifdef VENDOR_EDIT
#Junhao.Liang@AD.OppoLog.bug000000, 2020/01/02, Add for OTA to catch log
function resetlogfirstbootbuffer() {
    echo "resetlogfirstbootbuffer start"
    setprop sys.tranfer.finished "resetlogfirstbootbuffer start"
    enable=`getprop persist.sys.assert.panic`
    argfalse='false'
    if [ "${enable}" = "${argfalse}" ]; then
    /system/bin/logcat -G 256K
    fi
    echo "resetlogfirstbootbuffer end"
    setprop sys.tranfer.finished "resetlogfirstbootbuffer end"
}

function logfirstbootmain() {
    echo "logfirstbootmain begin"
    setprop sys.tranfer.finished "logfirstbootmain begin"
    path=/data/oppo_log/firstboot
    mkdir -p ${path}
    /system/bin/logcat -G 5M
    /system/bin/logcat  -f ${path}/android.txt -r10240 -v threadtime *:V
    setprop sys.tranfer.finished "logfirstbootmain end"
    echo "logfirstbootmain end"
}

function logfirstbootevent() {
    echo "logfirstbootevent begin"
    setprop sys.tranfer.finished "logfirstbootevent begin"
    path=/data/oppo_log/firstboot
    mkdir -p ${path}
    /system/bin/logcat -b events -f ${path}/event.txt -r10240 -v threadtime *:V
    setprop sys.tranfer.finished "logfirstbootevent end"
    echo "logfirstbootevent end"
}

function logfirstbootkernel() {
    echo "logfirstbootkernel begin"
    setprop sys.tranfer.finished "logfirstbootkernel begin"
    path=/data/oppo_log/firstboot
    mkdir -p ${path}
    dmesg > ${path}/kinfo_boot.txt
    setprop sys.tranfer.finished "logfirstbootkernel end"
    echo "logfirstbootkernel end"
}
#endif /* VENDOR_EDIT */

#ifdef VENDOR_EDIT
#Hailong.Liu@ANDROID.MM, 2020/03/18, add for capture native malloc leak on aging_monkey test
function storeSvelteLog() {

    if [ ! -c "/dev/svelte_log" ]; then
        echo "svelte_log device not exist." >> /dev/kmsg
    fi

    if [ ! -d "/data/oppo_log/svelte" ]; then
        mkdir -p /data/oppo_log/svelte
    fi

    while true
    do
        echo --------`date` >> /data/oppo_log/svelte/svelte_log.txt 2>&1
        /system/bin/svelte logger >> /data/oppo_log/svelte/svelte_log.txt
    done
}
#endif

case "$config" in
##add for log kit 2 begin
    "tranfer2")
        Preprocess
        tranfer2
        ;;
    "deleteFolder")
        deleteFolder
        ;;
    "deleteOrigin")
        deleteOrigin
        ;;
    "testkit")
        initLogPath2
        ;;
    "calculateFolderSize")
        calculateFolderSize
        ;;
##add for log kit 2 end
    "ps")
        Preprocess
        Ps
        ;;
    "top")
        Preprocess
        Top
        ;;
    "server")
        Preprocess
        Server
        ;;
    "dump")
        Dumpsys
        ;;
    "dump_wechat_info")
        DumpWechatMeminfo
        ;;
    "dump_storage")
        DumpStorage
        ;;
    "tranfer")
        Preprocess
        tranfer
        ;;
    "tranfer_tombstone")
        tranferTombstone
        ;;
    "logcache")
        CacheLog
        ;;
    "logpreprocess")
        PreprocessLog
        ;;
    "prepacketlog")
        prepacketlog
        ;;
    #ifdef VENDOR_EDIT
    #Qianyou.Chen@PSW.Android.OppoDebug.LogKit.0000000, 2019/06/05, Add for modifying cpt list.
    "copy_cptlist")
        copyCptTmpListToDest
        ;;
    #endif VENDOR_EDIT
    "wifipktlogtransf")
        wifipktlogtransf
        ;;
    "pktcheck")
        pktcheck
        ;;
    "tranfer_anr")
        tranferAnr
        ;;
#Chunbo.Gao@PSW.AD.OppoLog.2514795, 2019/11/12, Add for copy binder_info
    "copybinderinfo")
        copybinderinfo
    ;;
#Wuchao.Huang@ROM.Framework.EAP, 2019/11/19, Add for copy binder_info
    "copyEapBinderInfo")
        copyEapBinderInfo
    ;;
    "main")
        initLogPath2
        Logcat2
        ;;
    "radio")
        initLogPath2
        LogcatRadio2
        ;;
    "fingerprint")
        initLogPath
        LogcatFingerprint
        ;;
    "logfor5G")
        initLogPath
        Logcat5G
        ;;
    "fpqess")
        initLogPath
        LogcatFingerprintQsee
        ;;
    "event")
    #logkit2
        # initLogPath
        # LogcatEvent
    #logkit2
        initLogPath2
        LogcatEvent2
        ;;
    "kernel")
        initLogPath2
        LogcatKernel2
        ;;
    #Qi.Zhang@TECH.BSP.Stability 2019/09/20, Add for uefi log
    "logcatuefi")
        LogcatUefi
        ;;
    "tcpdump")
        initLogPath2
        enabletcpdump
        tcpdumpLog2
        ;;
    "clean")
        CleanAll
        ;;
    "clearcurrentlog")
        clearCurrentLog
        ;;
    "calcutelogsize")
        calculateLogSize
        ;;
    "cleardataoppolog")
        clearDataOppoLog
        ;;
    "movescreenrecord")
        moveScreenRecord
        ;;
    "cppstore")
        initLogPath
        cppstore
        ;;
    "rmpstore")
        rmpstore
        ;;
    "cpoppousage")
        cpoppousage
        ;;
    "screen_record")
        initLogPath
        screen_record
        ;;
    "screen_record_backup")
        screen_record_backup
        ;;
#ifdef VENDOR_EDIT
#Deliang.Peng@MultiMedia.Display.Service.Log, 2017/3/31,
#add for dump sf back tracey
    "sfdump")
        sfdump
        ;;
    "sfsystrace")
        sfsystrace
        ;;
#endif /* VENDOR_EDIT */
#Xuefeng.Peng@PSW.AD.Performance.Storage.1721598, 2018/12/26, Add for abnormal sd card shutdown long time
    "fsck_shutdown")
        fsck_shutdown
        ;;
    "exstorage_support")
        exstorage_support
        ;;
#endif /* VENDOR_EDIT */
#ifdef VENDOR_EDIT
#Shuangquan.du@PSW.AD.Recovery.0, 2019/07/03, add for generate runtime prop
    "generate_runtime_prop")
        generate_runtime_prop
        ;;
#endif
#ifdef VENDOR_EDIT
#Yanzhen.Feng@Swdp.Android.OppoDebug.LayerDump, 2015/12/09, Add for SurfaceFlinger Layer dump
    "layerdump")
        layerdump
        ;;
#endif /* VENDOR_EDIT */
#ifdef VENDOR_EDIT
#Yanzhen.Feng@Swdp.Android.OppoDebug, 2017/03/20, Add for systrace on phone
    "cont_systrace")
        cont_systrace
        ;;
#endif /* VENDOR_EDIT */
#ifdef VENDOR_EDIT
    "systrace_trigger_start")
        systrace_trigger_start
        ;;
    "systrace_trigger_stop")
        systrace_trigger_stop
        ;;
    "systrace_snapshot")
        systrace_snapshot
        ;;
#fangpan@Swdp.shanghai, 2017/06/05, Add for systrace snapshot mode
    "dumpstate")
        Preprocess
        Dumpstate
        ;;
    "enabletcpdump")
        enabletcpdump
        ;;
    "dumpenvironment")
        DumpEnvironment
        ;;

#Haoran.Zhang@PSW.AD.BuildConfig.StandaloneUserdata.1143522, 2017/09/13, Add for set prop sys.build.display.full_id
     "userdatarefresh")
         userdatarefresh
         ;;
#end
    "initcache")
        initcache
        ;;
    "logcatcache")
        logcatcache
        ;;
    "radiocache")
        radiocache
        ;;
    "eventcache")
        eventcache
        ;;
    "kernelcache")
        kernelcache
        ;;
    "tcpdumpcache")
        tcpdumpcache
        ;;
    "fingerprintcache")
        fingerprintcache
        ;;
    "logfor5Gcache")
        logfor5Gcache
        ;;
    "fplogcache")
        fplogcache
        ;;
    "log_observer")
        logObserver
        ;;
    "junklogcat")
        junklogcat
    ;;
    "junkdmesg")
        junkdmesg
    ;;
    "junkststart")
        junksystrace_start
    ;;
    "junkststop")
        junksystrace_stop
    ;;
#ifdef VENDOR_EDIT
#Zhihao.Li@MultiMedia.AudioServer.FrameWork, 2016/10/19, Add for clean pcm dump file.
    "cleanpcmdump")
        cleanpcmdump
    ;;
#endif /* VENDOR_EDIT */
#ifdef VENDOR_EDIT
#Jianping.Zheng@Swdp.Android.Stability.Crash, 2016/08/09, Add for logd memory leak workaround
    "check_logd_memleak")
        check_logd_memleak
        ;;
#endif /* VENDOR_EDIT *
    "gettpinfo")
        gettpinfo
    ;;
    "inittpdebug")
        inittpdebug
    ;;
    "settplevel")
        settplevel
    ;;
#ifdef VENDOR_EDIT
#Canjie.Zheng@Swdp.Android.OppoDebug.LogKit,2017/01/21,add for ftm
        "logcatftm")
        logcatftm
    ;;
        "klogdftm")
        klogdftm
    ;;
#Canjie.Zheng@Swdp.Android.OppoDebug.LogKit,2017/03/09, add for Sensor.logger
    "resetlogpath")
        resetlogpath
    ;;
#Canjie.Zheng@Swdp.Android.OppoDebug.LogKit,2017/03/23, add for power key dump
    "pwkdumpon")
        pwkdumpon
    ;;
    "pwkdumpoff")
        pwkdumpoff
    ;;
    "dumpoff")
        dumpoff
    ;;
    "dumpon")
        dumpon
    ;;
    "rmminidump")
        rmminidump
    ;;
    "test")
        test
    ;;
    "readdump")
        readdump
    ;;
    "packupminidump")
        packupminidump
    ;;
    "junklogmonitor")
        junk_log_monitor
#endif VENDOR_EDIT
#ifdef VENDOR_EDIT
#Jianping.Zheng@Swdp.Android.Stability.Crash,2017/04/04,add for record performance
    ;;
        "perf_record")
        perf_record
#endif VENDOR_EDIT
    ;;
#Jianping.Zheng@PSW.Android.Stability.Crash,2017/05/08,add for systemserver futex_wait block check
        "checkfutexwait")
        do_check_systemserver_futexwait_block
    ;;
    "checkfutexwait_wrap")
        checkfutexwait_wrap
#end, add for systemserver futex_wait block check
    ;;
#Fei.Mo@PSW.BSP.Sensor, 2017/09/01 ,Add for power monitor top info
        "thermal_top")
        thermalTop
#end, Add for power monitor top info
    ;;
#Canjie.Zheng@PSW.AD.OppoDebug.LogKit.1078692, 2017/11/20, Add for iotop
        "getiotop")
        getiotop
    ;;
#Linjie.Xu@PSW.AD.Power.PowerMonitor.1104067, 2018/01/17, Add for OppoPowerMonitor get dmesg at O
        "kernelcacheforopm")
        kernelcacheforopm
    ;;
#Linjie.Xu@PSW.AD.Power.PowerMonitor.1104067, 2018/01/17, Add for OppoPowerMonitor get Sysinfo at O
        "psforopm")
        psforopm
    ;;
#Linjie.Xu@PSW.AD.Power.PowerMonitor.1104067, 2019/08/21, Add for OppoPowerMonitor get qrtr at Qcom
        "qrtrlookupforopm")
        qrtrlookupforopm
    ;;
        "cpufreqforopm")
        cpufreqforopm
    ;;
        "smapsforhealth")
        smapsforhealth
    ;;
        "slabinfoforhealth")
        slabinfoforhealth
    ;;
        "svelteforhealth")
        svelteforhealth
    ;;
        "meminfoforhealth")
        meminfoforhealth
    ;;
        "dmaprocsforhealth")
        dmaprocsforhealth
    ;;
     "systraceforopm")
        systraceforopm
    ;;
#Weitao.Chen@PSW.AD.Stability.Crash.1295294, 2018/03/01, Add for trying to recover from sysetm hang
        "recover_hang")
        recover_hang
    ;;
# Kun.Hu@PSW.TECH.RELIABILTY, 2019/1/3, fix the core domain limits to search /mnt/vendor/opporeserve
        "remount_opporeserve2")
        remount_opporeserve2
    ;;
# wenjie.liu@CN.NFC.Basic.Hardware, 2019/4/22, fix the core domain limits to search /mnt/vendor/opporeserve/connectivity
        "remount_opporeserve2_felica_to_data")
        remount_opporeserve2_felica_to_data
    ;;
#Liang.Zhang@TECH.Storage.Stability.OPPO_SHUTDOWN_DETECT, 2019/04/28, Add for shutdown detect
        "remount_opporeserve2_shutdown")
        remount_opporeserve2_shutdown
    ;;
#Fangfang.Hui@PSW.TECH.AD.OppoDebug.LogKit.1078692, 2019/03/07, Add for mount mnt/vendor/opporeserve/stamp to data/oppo/log/stamp
        "remount_opporeserve2_stamp_to_data")
        remount_opporeserve2_stamp_to_data
    ;;
#Jiemin.Zhu@PSW.AD.Memroy.Performance, 2017/10/12, add for low memory device
        "lowram_device_setup")
        lowram_device_setup
    ;;
#add for customer log
        "delcustomlog")
        delcustomlog
    ;;
        "customdmesg")
        customdmesg
    ;;
        "customdiaglog")
        customdiaglog
    ;;
        "cleanramdump")
        cleanramdump
    ;;
        "mvrecoverylog")
        mvrecoverylog
    ;;
        "writenoop")
        writenoop
    ;;
        "writecfq")
        writecfq
    ;;
        "logcusmain")
        logcusmain
    ;;
        "logcusevent")
        logcusevent
    ;;
        "logcusradio")
        logcusradio
    ;;
        "setdebugoff")
        setdebugoff
    ;;
        "logcustcp")
        logcustcp
    ;;
        "logcuskernel")
        logcuskernel
    ;;
        "logcuswifi")
        logcuswifi
    ;;
        "logcusqmistart")
        logcusqmistart
    ;;
        "logcusqmistop")
        logcusqmistop
    ;;
        "chmodmodemconfig")
        chmodmodemconfig
    ;;
#Jian.Wang@PSW.CN.WiFi.Basic.Log.1162003, 2018/7/02, Add for dynamic collect wifi mini dump
        "enablewifidump")
        enablewifidump
    ;;
        "disablewifidump")
        disablewifidump
    ;;
        "collectwifidmesg")
        collectwifidmesg
    ;;
        "skipscollectwifidmesg")
        skipscollectwifidmesg
    ;;
        "touchwifiminidumpfile")
        touchwifiminidumpfile
    ;;
#end, Add for dynamic collect wifi mini dump
#laixin@PSW.CN.WiFi.Basic.Switch.1069763, 2018/09/03, Add for collect wifi switch log
        "collectWifiSwitchLog")
        collectWifiSwitchLog
    ;;
        "packWifiSwitchLog")
        packWifiSwitchLog
    ;;
        "collectWifiP2pLog")
        collectWifiP2pLog
    ;;
        "packWifiP2pFailLog")
        packWifiP2pFailLog
    ;;
        "mvWifiSwitchLog")
        mvWifiSwitchLog
    ;;
#Gong Tao@PSW.CN.WiFi.Connect.Connect.1065680, 2020/03/16,
#Add for collect wifi connect fail log
        "collectWifiConnectFailLog")
        collectWifiConnectFailLog
    ;;
        "packWifiConnectFailLog")
        packWifiConnectFailLog
    ;;
#end
#ifdef VENDOR_EDIT
#Xiao.Liang@PSW.CN.WiFi.Basic.Log.1072015, 2018/10/22, Add for collecting wifi driver log
        "setiwprivpkt0")
        setiwprivpkt0
    ;;
        "setiwprivpkt1")
        setiwprivpkt1
    ;;
        "setiwprivpkt4")
        setiwprivpkt4
    ;;
#ifdef VENDOR_EDIT

        "scan_switch_for_wifiroam")
        scan_switch_for_wifiroam
    ;;

#ifdef VENDOR_EDIT
#Zaogen.Hong@PSW.CN.WiFi.Connect,2020/03/03, Add for trigger wifi dump by engineerMode
        "wifi_minidump")
        wifi_minidump
    ;;
#ifdef VENDOR_EDIT

#ifdef VENDOR_EDIT
#Xiao.Liang@PSW.CN.WiFi.Basic.SoftAP.1610391, 2018/10/30, Modify for reading client devices name from /data/misc/dhcp/dnsmasq.leases
        "changedhcpfolderpermissions")
        changedhcpfolderpermissions
    ;;
#add for change printk
        "chprintk")
        chprintk
    ;;
#ifdef VENDOR_EDIT
#Bin.Li@BSP.Fingerprint.Secure 2018/12/27, Add for oae get bootmode
        "oae_bootmode")
        oae_bootmode
    ;;
#Qing.Wu@PSW.AD.Stability.2278668, 2019/09/03, Add for capture binder info
    "binderinfocapture")
        binderinfocapture
        ;;
#endif /* VENDOR_EDIT */
#ifdef VENDOR_EDIT
#//Chunbo.Gao@PSW.AD.OppoDebug.LogKit.1968962, 2019/4/23, Add for qmi log
        "qmilogon")
        qmilogon
    ;;
        "qmilogoff")
        qmilogoff
    ;;
        "save_latest_log")
        save_latest_log
    ;;
#Chunbo.Gao@PSW.AD.OppoDebug.LogKit.NA, 2019/6/26, Add for bugreport log
        "dump_bugreport")
        dump_bugreport
    ;;
        "qrtrlookup")
        qrtrlookup
    ;;
        "adspglink")
        adspglink
    ;;
        "modemglink")
        modemglink
    ;;
        "cdspglink")
        cdspglink
    ;;
        "modemqrtr")
        modemqrtr
    ;;
        "sensorqrtr")
        sensorqrtr
    ;;
        "npuqrtr")
        npuqrtr
    ;;
        "slpiqrtr")
        slpiqrtr
    ;;
        "slpiglink")
        slpiglink
    ;;
#ifdef OPLUS_DEBUG_SSLOG_CATCH
#//Wankang.Zhang@TECH.MDM.POWER 2020/04/02,add for catch ss log
        "logcatModemTmp")
        logcatModemTmp
    ;;
#endif
#endif /* VENDOR_EDIT */
        "killsensorhidl")
        killsensorhidl
    ;;
    "cameraloginit")
        cameraloginit
    ;;
        "oidtlogs")
        oidtlogs
    ;;
#ifdef VENDOR_EDIT
#Baozhu.Yu@NW.MBN, 2019/10/08,add for switchmbn
        "switch_mbntype")
        switch_mbntype
    ;;
#endif /*VENDOR_EDIT*/
#Yufeng.Liu@Plf.TECH.Performance, 2019/9/3, Add for malloc_debug
        "memdebugregister")
        memdebugregister
    ;;
        "memdebugstart")
        memdebugstart
    ;;
        "memdebugdump")
        memdebugdump
    ;;
        "memdebugremove")
        memdebugremove
    ;;
#endif /* VENDOR_EDIT */
#ifdef VENDOR_EDIT
#Fuchun.Liao@BSP.CHG.Basic 2019/06/09 modify for black/bright check
	"create_black_bright_check_file")
        create_black_bright_check_file
    ;;
#endif /* VENDOR_EDIT */
#add for firstboot log
        "resetlogfirstbootbuffer")
        resetlogfirstbootbuffer
    ;;
        "logfirstbootmain")
        logfirstbootmain
    ;;
        "logfirstbootevent")
        logfirstbootevent
    ;;
        "logfirstbootkernel")
        logfirstbootkernel
    ;;
#ifdef VENDOR_EDIT
#Hailong.Liu@ANDROID.MM, 2020/03/18, add for capture native malloc leak on aging_monkey test
        "storeSvelteLog")
        storeSvelteLog
    ;;
#endif /*VENDOR_EDIT*/
       *)

      ;;
esac
