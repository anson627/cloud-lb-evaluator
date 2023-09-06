#!/bin/bash

tag=$1
side=$2
public_ip=${3:-''}
iteration=${4:-1000000}

cd /home/adminuser
curl -L -s -o ${side}.tar.gz https://github.com/anson627/cloud-lb-evaluator/releases/download/$tag/${side}.tar.gz
tar -xzvf ${side}.tar.gz 
rm ${side}.tar.gz

cd ${side}_build
if [[ "$side" == "client" ]]; then
  echo "Running client"
  ./${side} $public_ip $iteration &> logs.txt &
else
  echo "Running server"
  ./${side} &> logs.txt &
fi
ps -ef | grep $side