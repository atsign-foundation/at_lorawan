#!/bin/bash

mkdir -p runDir
cd runDir

for gw_num in {20001..20003}
do
  gw_name="demo_lorawan_gateway_$gw_num"
  echo "Starting demo lorawan gateway client for @${gw_name}"
  mkdir -p "@${gw_name}"
  cd "@${gw_name}"

  rm -f reloadConfig
  ln -s ../../reloadConfigSingleFile reloadConfig

  dart ../../../packages/at_lorawan/bin/lw_gateway_main.dart \
      --root-domain "vip.ve.atsign.zone" \
      --atsign "@$gw_name" \
      --storage-dir "$gw_name" \
      --cram-secret "$gw_name" \
      --manager-atsigns "@demo_lorawan_gateway_manager_1" \
      --namespace "lorawan_demo" \
      --never-sync \
    >& "${gw_name}.client.out" 2>&1 &
  cd ..
done
