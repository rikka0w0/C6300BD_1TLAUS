#!/bin/sh
{
    /opt/busybox-mips printf 'MSO\r\n'
    sleep 1
    /opt/busybox-mips printf 'changeme\r\n'
    sleep 1
    /opt/busybox-mips printf '/reset\r\n'
} > /dev/ttyS0
