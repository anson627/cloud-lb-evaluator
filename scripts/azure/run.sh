#!/bin/bash

tag=$1
side=$2
public_ip=${3:-''}

cd /home/adminuser
curl -L -s -o ${side}.tar.gz https://github.com/anson627/cloud-lb-evaluator/releases/download/$tag/${side}.tar.gz
tar -xzvf ${side}.tar.gz 
rm ${side}.tar.gz

cd ${side}_build
if [ ! -z "$side" ]; then
  ./${side} $public_ip &> logs.txt &
else
  ./${side} &> logs.txt &
fi
ps -ef | grep $side