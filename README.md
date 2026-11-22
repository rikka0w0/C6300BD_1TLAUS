This repository contains a mod guide for the C6300BD_1TLAUS pre-NBN DOCSIS 3.0 modem.

 * Enable Telnet access on the Linux side
 * Add the Dropbear SSH server
 * Utilize the unused linuxapps partition to store more data
 * Access the eCos shell after SSHing into the Linux side
 * Remote reboot
 * Remote Linux-side firmware update
 * curl, for sending GET/POST HTTP requests and similar tasks

__This guide requires a USB-TTL adapter for accessing the serial console. A
Linux system is required to apply the patches. WSL2 has been tested.__

# Backup

Before start, I strongly recommend making a full backup of the modem. I also
provide my own dumped firmware images under `stock-nand` and `stock-nor`.

After opening the modem case, connect the USB-TTL adapter to J361, which is near
the 2-pin jumper. Only RX, TX, and GND are needed. On the PC side, software such
as PuTTY can be used.

Power on the modem. Once the eCos console appears, enter `MSO` as the user name,
press Enter, then enter `changeme` as the password and press Enter again to
enter the eCos shell.

At this point, the shell might be filled with lines containing "Scanning". Run
`/cm_hal/scan_stop` to stop the output.

Then run the following commands to enable the eCos Telnet server:

```bash
/msgLog/remoteAccess/stop_server telnet
/msgLog/remoteAccess/read_default_settings telnet
/msgLog/remoteAccess/start_server telnet
```

Then use [bcm2dump](https://github.com/jclehner/bcm2-utils#bcm2dump) on the PC
to dump each partition:

```bash
./bcm2dump -P c6300bd info
./bcm2dump dump 192.168.0.1,admin,password nvram bootloader bootloader.bin
./bcm2dump dump 192.168.0.1,admin,password nvram permnv permnv.bin
./bcm2dump dump 192.168.0.1,admin,password nvram vennv vennv.bin
./bcm2dump dump 192.168.0.1,admin,password nvram dynnv dynnv.bin
./bcm2dump dump 192.168.0.1,admin,password flash image1 image1.bin
./bcm2dump dump 192.168.0.1,admin,password flash image2 image2.bin
./bcm2dump dump 192.168.0.1,admin,password flash linux linux.bin
./bcm2dump dump 192.168.0.1,admin,password flash linuxkfs linuxkfs.bin
./bcm2dump dump 192.168.0.1,admin,password flash dhtml dhtml.bin
```

There is no need to dump linuxapps because it is empty.

# Patching the Linux Side

Although the PCB has a serial port for the Linux side, it is completely
non-interactive. Therefore, we need to enable Telnet access on the Linux side.

## Unpacking the Linux-side Firmware

The modified [ProgramStore](https://github.com/rikka0w0/aeolus/blob/master/ProgramStore/README.md)
is required to correctly unpack the Linux-side image.

The modified ProgramStore can correctly handle the combination of an LZMA Linux
kernel and a raw SquashFS root filesystem.

In addition, the firmware uses a modified SquashFS driver. The
`c6300bd-sqfs-unpack.sh` script patches the magic number and compression field
so that regular SquashFS tools can recognize the image.

```bash
sudo apt install squashfs-tools fakeroot
make extract-linux-kernel unpack-linux-rootfs
```

## Enabling Telnet

The firmware startup script checks whether the kernel command line contains the
`nouart` field. Telnet is only enabled if that field is absent.

If `ENABLE_TELNET` in the Makefile is set to 1, which is the default, the startup
script will be patched during firmware packing to force Telnet on.

## Adding the Dropbear SSH Server

Statically build Dropbear for MIPS32:

```bash
make dropbear
```

The output is `build/dropbear-2025.88/dropbearmulti`.

Generate host keys:

```bash
make dropbearkey-host-gen-hostkey
```

Then place your `authorized_keys` file under `rootfs.merge/etc/dropbear`.

Note: for safety, password login is disabled by default. To enable password
login, remove the `-s` option from the Dropbear command in `startup.sh`.

If you need public Internet access, add a port forwarding rule in the web administration
UI that forwards to `192.168.0.200:22`.

This Dropbear build uses old Unix-style PTYs so that PTY allocation works.
However, the kernel limits the number of available PTYs to only two, so it is easy
to hit `PTY allocation request failed on channel 0`. The workaround is to run
`ssh root@LINUX_SIDE_IP -T /opt/pty-release-all.sh` to close all programs that
are occupying PTYs.

## Repacking the Linux-side Firmware

```bash
make pack-linux-rootfs
```

This repacks SquashFS while preserving device nodes and FIFOs inside the rootfs,
then restores the magic number expected by the firmware (`shsq`) and the
compression field. The actual compression is LZMA, but the image is marked as
GZIP.

During packing, the contents of `rootfs.merge` are merged in, the Telnet startup
patch is applied, and the Dropbear binary is added. Therefore, before packing
the Linux-side firmware, place any files you want to add under `rootfs.merge`.

## Patching the Linux Kernel

__This is optional and is generally recommended to skip.__

In the stock firmware kernel, the NAND MTD partition table is obtained from the
eCos side via RPC. The eCos side only allows writing to the dhtml and linuxapps
MTD partitions.

This can be controlled with `LINUX_KERNEL_RW_ALL_MTD` in the Makefile. By
default, this patch is not applied.

## Packing the Firmware

```bash
make pack-linux-firmware
```

The generated `C6300BD_1TLAUS_K2630_PATCHED.bin` can be used for flashing.

## Flashing the Patched Firmware

First power off the modem, then connect it to the PC with an Ethernet cable.
Connect the other end to any LAN port on the modem. Set the corresponding PC
network interface to the static IP `192.168.0.3` with subnet mask
`255.255.255.0`; no gateway is needed:

```bash
sudo ip link set enx00e04d69792e up
sudo ip addr flush dev enx00e04d69792e
sudo ip addr add 192.168.0.3/24 dev enx00e04d69792e
```

With the serial console connected, power on the modem. When you see
`Enter '1', '2', or 'p' within 2 seconds or take default...`, immediately press
`p` to interrupt normal boot and enter the bootloader menu:

```text
Board IP Address  [192.168.0.1]:
Board IP Mask     [255.255.255.0]:
Board IP Gateway  [0.0.0.0]:
Board MAC Address [00:10:18:ff:ff:ff]:

Internal/External phy? (e/i/a)[a]
Switch detected
Using GMAC0, phy 0

Enet link up: 1G full


Main Menu:
==========
  b) Boot from flash
  g) Download and run from RAM
  d) Download and save to flash
  e) Erase flash sector
  m) Set mode
  s) Store bootloader parameters to flash
  i) Re-init ethernet
  r) Read memory
  w) Write memory
  j) Jump to arbitrary address
  p) Print flash partition map
  E) Erase flash region/partition
  X) Erase all of flash except the bootloader
  z) Reset
```

Press `d`, then enter the PC IP address and the firmware file name
(`C6300BD_1TLAUS_K2630_PATCHED.bin`):

```text
TFTP Get Selected
Board TFTP Server IP Address [192.168.0.3]:  192.168.0.3
Enter filename [C6300BD_1TLAUS_K2630V1.01.06u_140526.bin]: C6300BD_1TLAUS_K2630_PATCHED.bin


Destination: abf00000

Destination: abf00000
Starting TFTP of C6300BD_1TLAUS_K2630_PATCHED.bin from 192.168.0.3
Getting C6300BD_1TLAUS_K2630_PATCHED.bin using octet mode
................................................................................
................................................................................
................................................................................
................................................................................
Tftp complete
Received 9424896 bytes

Image 3 Program Header:
   Signature: a0eb
     Control: 0105
   Major Rev: 0114
   Minor Rev: 0514
  Build Time: 2026/6/29 18:43:37 Z
 File Length: 9424804 bytes
Load Address: 00000000
    Filename: C6300BD_1TLAUS_K2630_PATCHED.bin
         HCS: 3c40
         CRC: 58e0eccd

CRC Verified

Destination image
  0 = bootloader
  1/2 = CM image
  3/8 = Linux kernel&rootfs image
  4 = Linux apps
(0-3)[2]:
```

Enter `3` to select `3/8 = Linux kernel&rootfs image`, then answer either `y` or `n` when prompted.

```text
Writing image 3 to NAND flash at offset 35c0000...
NandFlashEraseBlock: Erasing block at 0x59a0000
Store parameters to flash? [n]
```

After returning to `Main Menu`, press `b` to continue booting into the new firmware.

# Using the linuxapps Partition(squashfs)

According to the rcS script, `/dev/mtdblock3`, the partition named linuxapps,
may be mounted as UBIFS or JFFS2 during startup.

I tried statically compiling mtd-utils from the
[GPL source](https://archive.org/download/netgearfirmwaresgpl/C6300BD_1TLAUS_v1.01.03_src_20140319.zip)
and using it on the device to create and mount UBIFS, and also tried formatting
JFFS2 with the firmware's built-in `flash_eraseall`. All attempts failed at the
mount step.

The reason is unknown. I suspect the vendor modified the drivers of these two
filesystems. Since there is no usable linuxapps sample, I cannot analyze what
exactly causes the issue.

The only workable approach here is a crude one: write a SquashFS image directly
to `/dev/mtdblock3`. The image must use the same modified SquashFS format, and
`startup.sh` mounts it during boot.

In the modified firmware, if `startup.sh` exists inside linuxapps, it will be executed
automatically during boot. If `authorized_keys` exists inside linuxapps, it will
also be merged and used when the modem starts.

Files in the `linuxapps` directory can be packed into `build/mtdblock3.bin` with:

```bash
chmod +x linuxapps/startup.sh
make clean-linuxapps
make pack-linuxapps
```

Then copy `build/mtdblock3.bin` to a USB drive, plug it into the modem, and use
`dd` to write it to `/dev/mtdblock3`.

__If you try to unmount linuxapps after it has been mounted, it causes a
segmentation fault and the Linux side hangs. The reason is unknown.__

If linuxapps has already been automatically mounted during startup, call
`/opt/set_no_mtd3_marker.sh`. On the next reboot without power loss, linuxapps
will not be mounted. You can then use `dd` to write a new image to
`/dev/mtdblock3` and mount it manually.

__Calling reboot from the Linux side does not reboot the entire router. Instead,
it causes a hang.__

The workaround is to call `/opt/modem_restart.sh`, but it requires the hardware
modification described in [Accessing the eCos Shell from the Linux Side](#ecos-shell).
Sometimes one attempt does not work, and `/opt/modem_restart.sh` needs to be run
multiple times.

# Using the linuxapps Partition(ext4)

As an alternative to SquashFS, linuxapps can be formatted as ext4 and mounted
read-only by default, then temporarily remounted read-write to update files.
This is experimental: ext4 is not NAND-aware, and it still uses the same vendor
MTD/RPC driver. It does not fix the previously observed stale-data reads or
remove the need for ECC, OOB tags, and bad-block handling.

`rootfs.merge/bin/mkfs.ext4` is a static MIPS32 big-endian, o32, soft-float build
of `mke2fs` from the official GPL archive's `e2fsprogs-1.41.14.tar.gz`.
It is installed as `/bin/mkfs.ext4` when the Linux rootfs is repacked, along with
`/bin/c6300bd-mke2fs.conf`. This old version and the supplied configuration avoid
modern ext4 features that Linux 2.6.30 cannot mount, such as `64bit` and
`metadata_csum`. The binary is a general-purpose formatter; always use the
configuration and explicit options below to disable journaling.

## Creating the ext4 Filesystem

__Formatting destroys the existing contents of linuxapps and writes to NAND.
Back up anything important first.__ On the Linux side, check the device and
filesystem support:

```sh
cat /proc/mtd
cat /proc/mounts
grep ext4 /proc/filesystems
```

Confirm that `mtd3` is linuxapps. Use the block device `/dev/mtdblock3`, not the
character device `/dev/mtd3`. Before formatting, ensure it is not mounted
anywhere or attached to UBI. If the old SquashFS cannot be unmounted safely, use
`/opt/set_no_mtd3_marker.sh` and reboot the whole modem as described above;
do not force formatting of a mounted filesystem.

```sh
MKE2FS_CONFIG=/bin/c6300bd-mke2fs.conf /bin/mkfs.ext4 \
    -t ext4 -b 4096 -I 256 -m 0 \
    -O ^has_journal \
    -E nodiscard,lazy_itable_init=0 \
    /dev/mtdblock3
```

This creates a filesystem without a journal, disables discard, and initializes
the inode tables during formatting rather than leaving that work to a later
mount. Do not add `-c`/`-cc` bad-block tests or `-F` to bypass safety checks.
If formatting reports I/O errors, stop and inspect `dmesg` rather than forcing
a mount or erasing bad-block markers.

After successful formatting, mount it read-only:

```sh
mkdir -p /mnt/mtdblock3
mount -t ext4 -o ro,noload /dev/mtdblock3 /mnt/mtdblock3
grep ' /mnt/mtdblock3 ' /proc/mounts
df -h /mnt/mtdblock3
```

At boot, `/opt/startup.sh` checks for the ext filesystem superblock magic first,
then for the vendor SquashFS magic. It mounts ext4 with explicit `ro,noload`
options, or SquashFS with the original mount command (SquashFS is inherently
read-only). It never formats the partition or runs a repair tool automatically.
The skip-mount marker applies only to SquashFS; ext4 neither checks nor clears it.
Both formats support the existing
`startup.sh` and `authorized_keys` files in the partition root.

## Updating Files

Temporarily allow writes on an already mounted ext4 filesystem:

```sh
mount -t ext4 -o remount,rw /dev/mtdblock3 /mnt/mtdblock3
```

Copy or edit files under `/mnt/mtdblock3`. For example, after preparing the
files in `/tmp`:

```sh
cp /tmp/startup.sh /mnt/mtdblock3/startup.sh
chmod 755 /mnt/mtdblock3/startup.sh
cp /tmp/authorized_keys /mnt/mtdblock3/authorized_keys
```

When finished, flush writes and restore read-only mode. If either command fails,
check `dmesg` and do not assume the changes are safely stored:

```sh
sync
mount -t ext4 -o remount,ro /dev/mtdblock3 /mnt/mtdblock3
grep ' /mnt/mtdblock3 ' /proc/mounts
```

There is no journal, so power loss or resetting while writing can leave an
inconsistent filesystem. Verify files again after a full modem reboot, without
reformatting, because immediate reads can be served from cache.

__Read-only is not hardware NAND write protection.__ A journaled ext4 filesystem
can replay its journal even with `ro`; `noload` prevents that replay
([kernel documentation](https://docs.kernel.org/admin-guide/ext4.html)). Do not
treat skipping replay on an unclean filesystem as a repair. The automatic mount
avoids filesystem-level writes, but cannot prevent another process from writing
through MTD or the eCos side. A custom linuxapps `startup.sh` can also issue its
own writes or remount commands, so keep it read-only unless explicitly needed.

<a id="ecos-shell"></a>

# Accessing the eCos Shell from the Linux Side

The eCos shell can be accessed through either serial or Telnet. Serial is
straightforward, but it cannot be accessed remotely over the network.

In the stock firmware, telnet first requires entering the shell over serial and then running
`/msgLog/remoteAccess/restart_server telnet`; it cannot be enabled
automatically at boot.

## New Method: Patch eCos

Through reverse engineering, I found that eCos Telnet has a global switch (at 0x814FD43F, 1-byte). The
Telnet service is enabled only after this switch is ANDed with the value of
`/non-vol/userif/telnet_enable`.

The initial value of this global switch is 0. It is set again in one function
through a VSIF message delivered over DOCSIS. We obviously cannot deliver such a
VSIF message through DOCSIS, so the practical approach is to patch the eCos
firmware and force this global switch to remain 1.

After running `make pack-ecos`, you get
`build/C6300BD_1TLAUS_V1.04.13u_TELNET.bin`. It can be downloaded through the
bootloader. The only difference from the Linux firmware flashing step is that
you should choose 1 here:

```text
Destination image
  0 = bootloader
  1/2 = CM image
  3/8 = Linux kernel&rootfs image
  4 = Linux apps
(0-3)[2]:
```

After that, from the Linux side you can connect directly with
`/opt/busybox-mips telnet 192.168.0.1`. Press `ctrl+]` to exit.

You may need to log in twice. The first username and password may be `admin` and
`password`; the second may be `MSO` and `changeme`.

After logging in once with `MSO` + `changeme`, `admin` + `password` should work
directly afterwards.

If it shows `Invalid login...`, swap the order and try again. Reverse
engineering also found another credential pair in the firmware:
`factory` + `z^Yq2c(jSv`.

Running `/reset` in Telnet reboots the modem.

## Old Method: Hardware Modification, Not Recommended

I came up with a workaround: cross-connect the two middle pins between J360 and
J361 on the PCB with wires (RX-TX and TX-RX), and short JP360, the 2-pin header.
This allows the Linux side to access the eCos serial shell through `/dev/ttyS0`
with `/opt/busybox-mips microcom -s 115200 /dev/ttyS0`. However, the shell shown
through this method contains a lot of garbled characters.

With this setup, `/opt/modem_start_telnet.sh` can be called to enable eCos
Telnet. Sometimes one attempt does not work, so `/opt/modem_start_telnet.sh` may
need to be called multiple times.

The username and password are `admin` and `password`.

__This method cannot show eCos boot logs or the bootloader menu.__

# Updating the Linux-side Firmware from the eCos Shell

An eCos shell patched by `patch-ecos-iphal-dload-stack.py` (automatically called
by `make pack-ecos`) can download firmware from a specified TFTP server on the
LAN side, or even from the WAN side.

In other words, you can first SSH into the Linux side from the Internet, Telnet
from the Linux side into the eCos shell, then run the following commands to
flash the Linux firmware. The new firmware takes effect after reboot:

```text
/snoop/enable (25) false
/ip_hal/dload (4) -i 3 192.168.0.3  C6300BD_1TLAUS_K2630_PATCHED.bin
/snoop/enable (25) true
/reset
```

The `(4)` above corresponds to the LAN side. For the WAN side, use `(3)`
instead.

`/snoop/enable (25) false` temporarily disables firewall snoop instance 25 in
eCos. This snoop checks and drops packets in the packet path according to IPv4
firewall rules. After disabling it, packets are passed through directly, which
makes TFTP updates from a LAN-side IP possible. __The risk is that IPv4 packet
filtering is temporarily relaxed. After flashing, it is recommended to
immediately re-enable it with `/snoop/enable (25) true`, or reboot with
`/reset`.__

# Enabling IPv6

Enter the eCos shell and run:

```text
/non-vol/eRouter/ip_prov_mode 3
/non-vol/write
```

You may also need `/call function -r -a 0x8059B870` to obtain IPv6 without a
reboot, but I recommend rebooting instead. In this mode, the Linux side also
gets a publicly pingable IPv6 address.

You can also manually obtain IPv6 temporarily, but only on the eCos side. It
does not continue sending RA to the Linux side or LAN side:

```text
/ip_hal/ip_addr_show (2)
/ip_hal/ipv6config (2) linklocal
/ip_hal/ipv6config (4) linklocal
/ip_hal/ipv6config (2) renew
/ip_hal/ip_addr_show (2)
/ip_hal/ip_addr_show (4)
```

IPv6 firewall-related commands:

```text
/non-vol/eRouter/ipv6/firewall/firewall_enable
/non-vol/eRouter/ipv6/firewall/fw_filter_show
```

__The Linux-side Telnet server has been changed to IPv4-only access to avoid
exposure on the public IPv6 Internet.__

# References

1. [NetGear GPL source](https://archive.org/download/netgearfirmwaresgpl)
2. [C6300BD_TLAUS on the OpenWrt Wiki](https://openwrt.org/inbox/toh/netgear/c6300bd-1tlaus)
3. [/opt/busybox-mips](https://www.zhiwanyuzhou.com/download/Software/busybox/busybox-mips)
4. [DOCSIS eCos command reference](https://www.innomedia.com/wp-content/uploads/2014/02/EMTA_6528-4B_Admin_Guide_v1_0.pdf)
