#!/bin/bash

mkdir -p runDir
cd runDir

mgr_name="demo_lorawan_gateway_manager_1"
echo "Starting ${mgr_name}"

dart ../../packages/at_lorawan/bin/lw_manager_main.dart \
    --atsign "@$mgr_name" \
    --cram-secret "$mgr_name" \
    --root-domain "vip.ve.atsign.zone" \
    --never-sync \
    --storage-dir "$mgr_name" \
    --configs-dir configs
