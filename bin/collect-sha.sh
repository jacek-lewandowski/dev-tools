#!/bin/bash

set +e

DATA_FILE="db.txt"
i=0
find "$1" -type f -name "$2" | grep -v '@eaDir' | while read -d $'\n' fn
do
	i=$((i+1))
	echo "$i: $fn"
	grep "$fn" "$DATA_FILE" > /dev/null
	if [[ $? != 0 ]]; then
		sha512sum "$fn" >> "$DATA_FILE"
	fi
done
