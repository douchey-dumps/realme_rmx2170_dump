#!/system/bin/sh
if ! applypatch --check EMMC:/dev/block/bootdevice/by-name/recovery:100663296:7bd716f8e7988456807ad33ded23cf5c656ce7d6; then
  applypatch  \
          --patch /vendor/recovery-from-boot.p \
          --source EMMC:/dev/block/bootdevice/by-name/boot:67108864:aa37499e2e37e2eb4a8de86bfb07d160fcb0f2c9 \
          --target EMMC:/dev/block/bootdevice/by-name/recovery:100663296:7bd716f8e7988456807ad33ded23cf5c656ce7d6 && \
      log -t recovery "Installing new oppo recovery image: succeeded" && \
      setprop ro.recovery.updated true || \
      log -t recovery "Installing new oppo recovery image: failed" && \
      setprop ro.recovery.updated false
else
  log -t recovery "Recovery image already installed"
  setprop ro.recovery.updated true
fi
