docker compose run --rm kafka-controller-0 kafka-storage format \
  --config /etc/kafka/kraft-server.properties \
  --cluster-id Rv_mOiSXQMSkcOpL_jZ01Q \
  --add-scram 'SCRAM-SHA-512=[name=ninja,password=hi]' \
  --ignore-formatted