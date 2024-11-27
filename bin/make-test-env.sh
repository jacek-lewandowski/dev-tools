#!/bin/bash

cassandra_dir="$1"
cassandra_dtest_dir="$2"

if [ -z "$cassandra_dir" ] || [ -z "$cassandra_dtest_dir" ]; then
    echo "No cassandra or cassandra-dtest dir provided" 1>&2
    exit 1
fi

docker run -di -m 8G --cpus 4 \
    --mount type=bind,source=/home/jlewandowski/dev/datastax/cassandra/$cassandra_dir,target=/home/cassandra/cassandra \
    --mount type=bind,source=/home/jlewandowski/dev/datastax/cassandra-dtest/$cassandra_dtest_dir,target=/home/cassandra/cassandra-dtest \
    --name test ds-cassandra-build-tests:latest dumb-init bash
