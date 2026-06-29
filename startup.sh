#!/bin/sh

# Fix root 
killall lxginit

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

# Collect ssh keys
if [ -f /etc/dropbear/authorized_keys ]; then
    mkdir -p /root/.ssh
    cp /etc/dropbear/authorized_keys /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
fi

# Start Dropbear SSH server
mkdir -p /var/run
/usr/sbin/dropbear \
  -r /etc/dropbear/dropbear_rsa_host_key \
  -r /etc/dropbear/dropbear_ed25519_host_key \
  -p 22 -s
