#!/bin/bash

set -e

cd ~/dev/datastax/cassandra/cassandra-update
ant realclean

set +e
ant jar
if [ $? != 0 ]; then
	exit 125 # tell git that the source code is broken and this commit should not be tested
fi

echo "org/apache/cassandra/distributed/test/BooleanTest.java" > testlist.txt

ant testclasslist -Dtest.classlistprefix=distributed -Dtest.classlistfile=testlist.txt -Dno-build-test=true

if [ $? == 0 ]; then
	exit 0
else
	exit 1
fi
