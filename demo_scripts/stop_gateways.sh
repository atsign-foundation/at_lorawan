#!/bin/bash

ps -ef | grep lw_gateway_main | grep -v grep

kill `ps -ef | grep lw_gateway_main | grep -v grep | awk '{print $2}'`
