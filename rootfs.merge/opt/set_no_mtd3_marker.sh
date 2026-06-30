#!/bin/sh
echo 'C6300BD_NO_MTD3!' | dd of=/dev/mem bs=1 seek=$((0x07FFFFF0)) count=16 conv=notrunc
