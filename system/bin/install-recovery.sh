#!/system/bin/sh
if ! applypatch -c EMMC:/dev/block/platform/mtk-msdc.0/by-name/recovery:4665344:03a860aa78fe36cf1c56bbcc6c395ca031e3f9b0; then
  applypatch -b /system/etc/recovery-resource.dat EMMC:/dev/block/platform/mtk-msdc.0/by-name/boot:4040704:0840098336117c43d8414cce04f341c286223208 EMMC:/dev/block/platform/mtk-msdc.0/by-name/recovery 03a860aa78fe36cf1c56bbcc6c395ca031e3f9b0 4665344 0840098336117c43d8414cce04f341c286223208:/system/recovery-from-boot.p && echo "
Installing new recovery image: succeeded
" >> /cache/recovery/log || echo "
Installing new recovery image: failed
" >> /cache/recovery/log
else
  log -t recovery "Recovery image already installed"
fi
