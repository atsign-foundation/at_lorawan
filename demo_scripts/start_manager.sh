#!/bin/bash

mkdir -p runDir
cd runDir

mgr_name="demo_lorawan_gateway_manager_1"
echo "Starting ${mgr_name}"

dart ../../packages/at_lorawan/bin/lw_manager_main.dart \
    -a "@$mgr_name" \
    -c "$mgr_name" \
    -d "vip.ve.atsign.zone" \
    --configs-dir configs
