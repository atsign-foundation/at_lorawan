#!/bin/bash

mkdir -p runDir
cd runDir

mkdir -p configs
cd configs

for gw_num in {20001..20003}
do
  gw_name="demo_lorawan_gateway_$gw_num"
  echo "Creating demo data for $gw_name"
  mkdir -p "@${gw_name}"
  cd "@${gw_name}"
  if [ ! -f config ]; then
    touch config
    echo "# Config file for ${gw_name}" >> config
    echo "# $(date)" >> config
  fi
  cd ..
done
