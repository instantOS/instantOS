#!/bin/bash

echo "pulling upstream stuff"
echo "DO NOT COMMIT, MANUALLY MERGE THINGS BY LOOKING AT GIT TO PRESERVE INSTANTOS PATCHES"

rm -rf releng/

cp -r /usr/share/archiso/configs/releng/ .

echo "reapplying overlay stuff"

cp -a overlay/. releng/airootfs/
