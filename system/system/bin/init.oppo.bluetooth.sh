#! /system/bin/sh
#***********************************************************
#** Copyright (C), 2008-2016, OPPO Mobile Comm Corp., Ltd.
#** VENDOR_EDIT
#**
#** Version: 1.0
#** Date : 2019/06/25
#** Author: Liangwen.Ke@PSW.CN.BT.Basic.Customize.2120948
#** Add  for supporting QC firmware update by sau_res
#**
#** ---------------------Revision History: ---------------------
#**  <author>    <data>       <version >       <desc>
#**  Liangwen.Ke 2019.6.25      1.0            build this module
#****************************************************************/

config="$1"

saufwdir="/data/oppo/common/sau_res/res/SAU-AUTO_LOAD_FW-10/"
pushfwdir="/data/vendor/bluetooth/fw/"
pushdatadir="data/misc/bluedroid/"

# cp bt sau file to data/vendor/bluetooth dir
function btfirmwareupdate() {

    if [ -f ${saufwdir}/crbtfw32.tlv ]; then
        cp  ${saufwdir}/crbtfw32.tlv  ${pushfwdir}
        chown bluetooth:bluetooth ${pushfwdir}/crbtfw32.tlv
        chmod 0440 bluetooth:bluetooth ${pushfwdir}/crbtfw32.tlv
    fi

    if [ -f ${saufwdir}/crnv32.bin ]; then
        cp  ${saufwdir}/crnv32.bin  ${pushfwdir}
        chown bluetooth:bluetooth ${pushfwdir}/crnv32.bin
        chmod 0440 bluetooth:bluetooth ${pushfwdir}/crnv32.bin
    fi

    if [ -f ${saufwdir}/crbtfw32.ver ]; then
        cp  ${saufwdir}/crbtfw32.ver  ${pushfwdir}
        cp  ${saufwdir}/crbtfw32.ver  ${pushdatadir}
        chown bluetooth:bluetooth ${pushfwdir}/crbtfw32.ver
        chown bluetooth:bluetooth ${pushdatadir}/crbtfw32.ver
        chmod 0440 bluetooth:bluetooth ${pushfwdir}/crbtfw32.ver
        chmod 0440 bluetooth:bluetooth ${pushdatadir}/crbtfw32.ver
    fi
}

# delete all bt sau file
function btfirmwaredelete() {

    if [ -f ${saufwdir}/crbtfw32.tlv ]; then
        rm -rf  ${saufwdir}/crbtfw32.tlv
    fi

    if [ -f ${pushfwdir}/crbtfw32.tlv ]; then
        rm -rf  ${pushfwdir}/crbtfw32.tlv
    fi

    if [ -f ${saufwdir}/crnv32.bin ]; then
        rm -rf  ${saufwdir}/crnv32.bin
    fi

    if [ -f ${pushfwdir}/crnv32.bin ]; then
        rm -rf  ${pushfwdir}/crnv32.bin
    fi

    if [ -f ${saufwdir}/crbtfw32.ver ]; then
        rm -rf  ${saufwdir}/crbtfw32.ver
    fi

    if [ -f ${pushfwdir}/crbtfw32.ver ]; then
        rm -rf  ${pushfwdir}/crbtfw32.ver
    fi

    if [ -f ${pushdatadir}/crbtfw32.ver ]; then
        rm -rf  ${pushdatadir}/crbtfw32.ver
    fi
}

case "$config" in
    "btfirmwareupdate")
        btfirmwareupdate
    ;;

    "btfirmwaredelete")
        btfirmwaredelete
    ;;
esac
