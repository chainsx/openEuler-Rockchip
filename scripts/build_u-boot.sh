#!/bin/bash

__usage="
Usage: build_u-boot [OPTIONS]
Build rk3399 u-boot image.
The target files idbloader.img and u-boot.itb will be generated in the build/u-boot folder of the directory where the build_u-boot.sh script is located.

Options: 
  -c, --config BOARD_CONFIG     Required! The name of target board which should be a space separated list, which defaults to firefly-rk3399_defconfig.
  -h, --help                    Show command help.
"

help()
{
    echo "$__usage"
    exit $1
}

default_param() {
    config="firefly-rk3399_defconfig"
    workdir=$(pwd)/build
    u_boot_url="https://gitlab.arm.com/systemready/firmware-build/u-boot.git"
    bsp_u_boot_url="https://github.com/chainsx/u-boot-rk3588"
    rk3588_bl32_url="https://github.com/chainsx/rkbin/raw/main/bin/rk35/rk3588_bl32_v1.09.bin"
    rk3588_bl31_url="https://github.com/chainsx/rkbin/raw/main/bin/rk35/rk3588_bl31_v1.20.elf"
    rk3399_bl31_url="https://github.com/rockchip-linux/rkbin/raw/master/bin/rk33/rk3399_bl31_v1.35.elf"
    log_dir=$workdir/log
}

local_param(){
    if [ -f $workdir/.param ]; then
        config=$(cat $workdir/.param | grep config)
        config=${config:7}
    fi
}

parseargs()
{
    if [ "x$#" == "x0" ]; then
        return 0
    fi

    while [ "x$#" != "x0" ];
    do
        if [ "x$1" == "x-h" -o "x$1" == "x--help" ]; then
            return 1
        elif [ "x$1" == "x" ]; then
            shift
        elif [ "x$1" == "x-c" -o "x$1" == "x--config" ]; then
            config=`echo $2`
            shift
            shift
        else
            echo `date` - ERROR, UNKNOWN params "$@"
            return 2
        fi
    done
}

buildid=$(date +%Y%m%d%H%M%S)
builddate=${buildid:0:8}

ERROR(){
    echo `date` - ERROR, $* | tee -a ${log_dir}/${builddate}.log
}

LOG(){
    echo `date` - INFO, $* | tee -a ${log_dir}/${builddate}.log
}

build_u-boot() {
    cd $workdir
    if [ -d u-boot ];then
        cd u-boot
        remote_url_exist=`git remote -v | grep "origin"`
        remote_url=`git ls-remote --get-url origin`
        if [[ ${remote_url_exist} = "" || ${remote_url} != ${u_boot_url} ]]; then
            cd ../
            rm -rf $workdir/u-boot
            git clone --depth=1 -b ${u_boot_ver} ${u_boot_url}
            if [[ $? -eq 0 ]]; then
                LOG "clone u-boot done."
            else
                ERROR "clone u-boot failed."
                exit 1
            fi
        fi
    else
        git clone --depth=1 -b ${u_boot_ver} ${u_boot_url}
        LOG "clone u-boot done."
    fi
    cd $workdir/u-boot
    if [[ -f $workdir/u-boot/u-boot.itb && -f $workdir/u-boot/idbloader.img ]];then
        LOG "u-boot is the latest"
    else
        if [ -f bl31.elf ];then rm bl31.elf; fi
        wget -O bl31.elf ${rk3399_bl31_url}
        if [ ! -f bl31.elf ]; then
            ERROR "arm-trusted-firmware(bl31.elf) can not be found!"
            exit 2
        fi
        make ARCH=arm $config
        make ARCH=arm -j$(nproc)
        make ARCH=arm u-boot.itb -j$(nproc)
        LOG "make u-boot done."
    fi
    if [ ! -f u-boot.itb ]; then
        ERROR "make u-boot failed!"
        exit 2
    fi

}

build_bsp_u-boot() {
    cd $workdir
    if [ -d u-boot ];then
        cd u-boot
        remote_url_exist=`git remote -v | grep "origin"`
        remote_url=`git ls-remote --get-url origin`
        if [[ ${remote_url_exist} = "" || ${remote_url} != ${bsp_u_boot_url} ]]; then
            cd ../
            rm -rf $workdir/u-boot
            git clone --depth=1 ${bsp_u_boot_url}
            if [[ $? -eq 0 ]]; then
                LOG "clone u-boot done."
            else
                ERROR "clone u-boot failed."
                exit 1
            fi
        fi
    else
        git clone --depth=1 ${bsp_u_boot_url}
        LOG "clone u-boot done."
    fi
    cd $workdir/u-boot
    if [[ -f $workdir/u-boot/u-boot.itb && -f $workdir/u-boot/idbloader.img ]];then
        LOG "u-boot is the latest"
    else
        if [ -f bl31.elf ];then rm bl31.elf; fi
        wget -O bl31.elf ${rk3588_bl31_url}
        if [ ! -f bl31.elf ]; then
            ERROR "arm-trusted-firmware(bl31.elf) can not be found!"
            exit 2
        fi
        if [ -f tee.bin ];then rm tee.bin; fi
        wget -O tee.bin ${rk3588_bl32_url}
        if [ ! -f tee.bin ]; then
            ERROR "op-tee firmware can not be found!"
            exit 2
        fi
        make ARCH=arm $config
        make ARCH=arm -j$(nproc)
        make ARCH=arm u-boot.itb -j$(nproc)
        ./tools/mkimage -n rk3588 -T rksd -d tpl/u-boot-tpl.bin idbloader.img
        cat spl/u-boot-spl.bin >> idbloader.img
        LOG "make u-boot done."
    fi
    if [ ! -f u-boot.itb ]; then
        ERROR "make u-boot failed!"
        exit 2
    fi

}

set -e
default_param
local_param
parseargs "$@" || help $?

if [ ! -d $workdir ]; then
    mkdir $workdir
fi
if [ ! -d ${log_dir} ];then mkdir -p ${log_dir}; fi
if [ ! -f $workdir/.done ];then
    touch $workdir/.done
fi
sed -i 's/u-boot//g' $workdir/.done
LOG "build u-boot..."
if [ "x$config" == "xrk3588_defconfig" ];then
    build_bsp_u-boot
else
    u_boot_ver="v2020.10"
    build_u-boot

LOG "The u-boot.itb and idbloader.img are generated in the ${workdir}/u-boot."
echo "u-boot" >> $workdir/.done
