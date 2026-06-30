#!/bin/sh

# Fix root 
killall lxginit

# Fix home directory for root user
cat > /var/passwd <<'EOF'
root:Wug6HduK7p2qo:0:0:root:/root:/bin/sh
admin:3p/jqBdhUjKDk:0:0:Administrator:/:/bin/false
support:cjgdnLzuHBkG6:0:0:Technical Support:/:/bin/false
user:9eJhUGicJv5j.:0:0:Normal User:/:/bin/false
nobody:iI7YzgulKeFJA:1:1:nobody for ftp:/:/bin/false
EOF

cat > /var/group <<'EOF'
root::0:root,admin,support,user
nobody::1:nobody
EOF

chmod 700 /root

# Start Dropbear SSH server
mkdir -p /var/run
/usr/sbin/dropbear \
  -r /etc/dropbear/dropbear_rsa_host_key \
  -r /etc/dropbear/dropbear_ed25519_host_key \
  -p 22 -s

# Mount extra SquashFS, if present
if [ "$(dd if=/dev/mtdblock3 bs=1 count=4 2>/dev/null)" = "shsq" ]; then
    if [ "$(dd if=/dev/mem bs=1 skip=$((0x07FFFFF0)) count=16 2>/dev/null)" = "C6300BD_NO_MTD3!" ]; then
        echo "Skipping /mnt/mtdblock3 mount: skip marker found"
        dd if=/dev/zero of=/dev/mem bs=1 seek=$((0x07FFFFF0)) count=16 conv=notrunc 2>/dev/null || true
    else
        echo "Mounting /mnt/mtdblock3: squashfs magic found"
        mkdir -p /mnt/mtdblock3
        mount -t squashfs /dev/mtdblock3 /mnt/mtdblock3
    fi
fi

# Collect ssh keys
mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [ -f /etc/dropbear/authorized_keys ]; then
    cp /etc/dropbear/authorized_keys /root/.ssh/authorized_keys
fi

if [ -f /mnt/mtdblock3/authorized_keys ]; then
    echo >> /root/.ssh/authorized_keys
    echo >> /root/.ssh/authorized_keys
    cat /mnt/mtdblock3/authorized_keys >> /root/.ssh/authorized_keys
fi

[ -f /root/.ssh/authorized_keys ] && chmod 600 /root/.ssh/authorized_keys

# Use a fallback DNS server when DHCP did not create resolv.conf.
if [ ! -s /etc/resolv.conf ]; then
    echo "nameserver 8.8.8.8" > /var/fyi/sys/dns
fi

if [ -f /mnt/mtdblock3/startup.sh ]; then
    /mnt/mtdblock3/startup.sh || true
fi

exit 0
