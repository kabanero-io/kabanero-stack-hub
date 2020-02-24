#!/bin/bash

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
base_dir=$(cd "${script_dir}/.." && pwd)

if [ -z $ASSETS_DIR ]
then
    assets_dir="${base_dir}/assets"
else
    assets_dir=$ASSETS_DIR
fi

echo "Assets in $assets directory are:"
echo "-------------------------------"
ls -al $assets_dir/*
echo "-------------------------------"
echo "Content of index file(s) are:"
for index in $(ls $assets_dir/*-index.yaml 2>/dev/null)
do
    echo "------------------------------------"
    echo "$(basename $index)"
    echo "------------------------------------"
    cat $index
done
echo "-------------------------------"
