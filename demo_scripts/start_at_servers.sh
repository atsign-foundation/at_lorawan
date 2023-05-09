#!/bin/bash

path_to_at_server_script="$HOME/dev/atsign/repos/at_server"
start_at_server_cmd="$path_to_at_server_script/tools/run_locally/scripts/macos/at_server"

mkdir -p runDir

cd runDir

for gw_num in {20001..20003}
do
  gw_name="demo_lorawan_gateway_$gw_num"
  echo "Starting atServer for @${gw_name}"
  $start_at_server_cmd -a "@$gw_name" -p "$gw_num"  -s "$gw_name" >& "${gw_name}.atServer.out" 2>&1 &
done

gw_mgr_name="demo_lorawan_gateway_manager_1"
echo "Starting atServer for @${gw_mgr_name}"
$start_at_server_cmd -a "@$gw_mgr_name" -p 30001 -s "$gw_mgr_name" >& "${gw_mgr_name}.atServer.out" 2>&1 &

