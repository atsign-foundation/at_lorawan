#!/bin/bash


# shellcheck disable=SC2009
ps -ef | grep lorawan | grep dart

# shellcheck disable=SC2009
for pid in $(ps -ef | grep lorawan | grep dart | awk '{print $2}')
do
  kill "$pid"
done
