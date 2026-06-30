#!/bin/sh
{
    /opt/busybox-mips printf 'MSO\r\n'
    sleep 1
    /opt/busybox-mips printf 'changeme\r\n'
    sleep 1
    /opt/busybox-mips printf '/msgLog/remoteAccess/restart_server telnet\r\n'
} > /dev/ttyS0
