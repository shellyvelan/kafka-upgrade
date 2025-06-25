#!/bin/bash

docker compose up kafka-controller-0

sleep 1

docker exec -it kafka-controller-0 bash -c "kafka-storage format --config /etc/kafka/kraft/server.properties --cluster-id Rv_mOiSXQMSkcOpL_jZ01Q --add-scram 'SCRAM-SHA-512=[name=ninja,password=hi]' --ignore-formatted"

sleep 5

docker compose up kafka-broker-0 
