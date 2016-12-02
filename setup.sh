#!/bin/bash
set -e

USERNAME=${USERNAME:=dev}
PASSWORD=${PASSWORD:=dev}
IP=`/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1`

if [ ! "$(ls -A /data/db1)" ]; then
    mkdir /data/db1
    mkdir /data/db2
    mkdir /data/db3

    mongod --smallfiles --noprealloc --dbpath /data/db1 &
    MONGO_PID=$!

    sleep 3
    echo "CREATING USER ACCOUNT"
    mongo admin --eval "db.createUser({ user: '$USERNAME', pwd: '$PASSWORD', roles: ['root', 'restore', 'readWriteAnyDatabase', 'dbAdminAnyDatabase'] })"

    echo "KILLING MONGO"
    kill $MONGO_PID
    sleep 3
fi

echo "WRITING KEYFILE"

openssl rand -base64 741 > /var/mongo_keyfile
chown mongodb /var/mongo_keyfile
chmod 600 /var/mongo_keyfile

echo "STARTING CLUSTER"

mongod --port 27001 --smallfiles --noprealloc --dbpath /data/db1 --auth --replSet rs0 --keyFile /var/mongo_keyfile  &
DB1_PID=$!
mongod --port 27002 --smallfiles --noprealloc --dbpath /data/db2 --auth --replSet rs0 --keyFile /var/mongo_keyfile  &
DB2_PID=$!
mongod --port 27003 --smallfiles --noprealloc --dbpath /data/db3 --auth --replSet rs0 --keyFile /var/mongo_keyfile  &
DB3_PID=$!

sleep 10
echo "CONFIGURING REPLICA SET: $IP"
CONFIG="{ _id: 'rs0', members: [{_id: 0, host: '$IP:27001', priority: 2 }, { _id: 1, host: '$IP:27002' }, { _id: 2, host: '$IP:27003' } ]}"
mongo admin --port 27001 -u $USERNAME -p $PASSWORD --eval "db.runCommand({ replSetInitiate: $CONFIG })"

mongo admin --port 27001 -u $USERNAME -p $PASSWORD --eval "db.runCommand({ setParameter: 1, quiet: 1 })"
mongo admin --port 27002 -u $USERNAME -p $PASSWORD --eval "db.runCommand({ setParameter: 1, quiet: 1 })"
mongo admin --port 27003 -u $USERNAME -p $PASSWORD --eval "db.runCommand({ setParameter: 1, quiet: 1 })"

trap 'echo "KILLING"; killall mongod; wait $DB1_PID; wait $DB2_PID; wait $DB3_PID' SIGINT SIGTERM EXIT

wait $DB1_PID
wait $DB2_PID
wait $DB3_PID
