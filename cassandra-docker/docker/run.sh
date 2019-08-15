#!/bin/bash

# Give kube-dns some time, otherwise cassandra-0.cassandra cannot be resolved when starting the seed node
sleep 5

sed -i -e "s/{{listen_address}}/$POD_IP/g" /cassandra/conf/cassandra.yaml
sed -i -e "s/{{rpc_address}}/$POD_IP/g" /cassandra/conf/cassandra.yaml

JVM_OPTS="-Dmx4jaddress=0.0.0.0 -Dmx4jport=8081"

cd /cassandra/bin

exec ./cassandra -f
