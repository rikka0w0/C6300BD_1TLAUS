本Repo包含了C6300BD_1TLAUS这款pre-NBN DOCSIS3.0 modem的魔改教程。

__本教程需要自备一个USB-TTL转接线用于访问串口控制台，应用patch需要Linux系统(WSL2已测试)__

# 备份
在开始之前，我强烈建议对整个modem进行备份。我也在`stock-nand`和`stock-nor`中提供了我Dump出来的固件。

拆开Modem的外壳后，把USB-TTL转接线接到J361（靠近2-Pin jumper那个），只需要接Rx、Tx和GND。PC端可采用Putty等软件。

启动电源，等出现eCos控制台后，直接输入`MSO`(User name)，按回车，然后输入`changeme`(Password)，再按回车，进入eCos的Shell。

此时会刷屏很多行Scanning之类的信息，执行`/cm_hal/scan_stop`即可停止刷屏。

随后运行如下命令开启eCos的telnet服务器：
```
/msgLog/remoteAccess/stop_server telnet
/msgLog/remoteAccess/read_default_settings telnet
/msgLog/remoteAccess/start_server telnet
```

随后在PC上使用[bcm2dump](https://github.com/jclehner/bcm2-utils#bcm2dump)把每个分区分别dump下来：
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
不需要dump linuxapps，因为里面没有东西。

# 对Linux侧进行Patch
虽然PCB上有Linux侧的串口，但是完全不可交互，因此我们需要设法开启Linux侧的Telnet。

## Linux侧固件解包
这里需要魔改过的[ProgramStore](https://github.com/rikka0w0/aeolus/blob/master/ProgramStore/README.md)才能正确解包Linux侧的镜像。

魔改过的ProgramStore才能正确处理LZMA Linux Kernel + 裸SquashFS这种组合。

```bash
mkdir build
cd build
wget -O ProgramStore https://github.com/rikka0w0/aeolus/releases/download/C6300BD-1TLAUS/ProgramStore_linux_amd64
chmod +x ProgramStore

# Replace ../stock-nand/C6300BD_1TLAUS_K2630V1.01.06u_140526.bin with your linux.bin
./ProgramStore -l -f ../stock-nand/C6300BD_1TLAUS_K2630V1.01.06u_140526.bin
./ProgramStore -x -f ../stock-nand/C6300BD_1TLAUS_K2630V1.01.06u_140526.bin -o img1.bin
./ProgramStore -x3 -f ../stock-nand/C6300BD_1TLAUS_K2630V1.01.06u_140526.bin -o img2.bin

sudo apt install squashfs-tools fakeroot
../c6300bd-sqfs-unpack.sh img2.bin
```

此外，固件采用的SquashFS驱动也是魔改过。`c6300bd-sqfs-unpack.sh`会修改Magic number和压缩方式字段，让常规SquashFS工具能识别。

## 开启Telnet
固件的启动脚本会判断内核命令行有没有`nouart`字段，如果没有才开启Telnet。如下命令可以强制开启Telnet（只对LAN侧）：

`sed -i "s|^\([[:space:]]*\)grep nouart /proc/cmdline > /dev/null|\1/bin/true # grep nouart /proc/cmdline > /dev/null|" ./rootfs.fakeroot/etc/init.d/rcS`

## 加入Dropbear SSH服务器
静态编译MIPS32 Dropbear:
```bash
pushd ../
./build-dropbear-static.sh
popd

mkdir -p rootfs.fakeroot/usr/sbin rootfs.fakeroot/usr/bin
cp -v dropbear-2025.88/dropbearmulti rootfs.fakeroot/usr/sbin/
chmod 755 rootfs.fakeroot/usr/sbin/dropbearmulti

# server
ln -sf dropbearmulti rootfs.fakeroot/usr/sbin/dropbear

# tools / client
ln -sf ../sbin/dropbearmulti rootfs.fakeroot/usr/bin/dropbearkey
ln -sf ../sbin/dropbearmulti rootfs.fakeroot/usr/bin/dropbearconvert
ln -sf ../sbin/dropbearmulti rootfs.fakeroot/usr/bin/dbclient
ln -sf ../sbin/dropbearmulti rootfs.fakeroot/usr/bin/ssh
ln -sf ../sbin/dropbearmulti rootfs.fakeroot/usr/bin/scp
```

产生Host key:
```bash
apt download dropbear-bin
rm -rf ./dropbear.extract
dpkg-deb -x ./dropbear-bin_*.deb ./dropbear.extract
mkdir -p rootfs.fakeroot/etc/dropbear
./dropbear.extract/usr/bin/dropbearkey -t rsa \
  -f ./rootfs.fakeroot/etc/dropbear/dropbear_rsa_host_key
./dropbear.extract/usr/bin/dropbearkey -t ed25519 \
  -f ./rootfs.fakeroot/etc/dropbear/dropbear_ed25519_host_key
```

加入启动脚本:
```bash
cat >> ./rootfs.fakeroot/etc/init.d/rcS <<'EOF'

# Start Dropbear SSH server
mkdir -p /var/run
/usr/sbin/dropbear \
  -r /etc/dropbear/dropbear_rsa_host_key \
  -r /etc/dropbear/dropbear_ed25519_host_key \
  -p 22
EOF
```

## 重新打包Linux侧固件
`../c6300bd-sqfs-pack.sh --force rootfs.fakeroot img2-patched.bin`

这一步会在保证rootfs内部Device Node和FIFO都存在的情况下重新打包SquashFS，并改成固件期望的Magic number(shsq)和压缩方式字段（采用LZMA，但是标记为GZIP）。

## Patch Linux内核
__这是个可选项，一般建议跳过！__

在原版固件的内核中，NAND MTD分区表是通过RPC的方式从eCos侧获取的，eCos侧只允许我们写dhtml和linuxapps这两个mtd分区。
如果你想写其它的mtd分区，使用这个对内核进行二进制级别的patch：

`../patch_img1_maskflags_writable.py img1.bin img1-patched.bin`


## 打包固件
`./ProgramStore -f img1-patched.bin -f3 img2-patched.bin -o C6300BD_1TLAUS_K2630_PATCHED.bin -c 4 -p 0x1a0000 -s a0eb -v 0114.0514`

产生的`C6300BD_1TLAUS_K2630_PATCHED.bin`可用于刷机。

# 刷写Patch过的固件
首先把Modem关机，然后用网线连到PC上，另一端接入任意Modem的LAN口。把PC相应网络接口的IP设为静态的`192.168.0.3`，子网掩码`255.255.255.0`，不用设置网关：
```bash
sudo ip link set enx00e04d69792e up
sudo ip addr flush dev enx00e04d69792e
sudo ip addr add 192.168.0.3/24 dev enx00e04d69792e
```

在确认串口已连接的情况下打开电源，当看到`Enter '1', '2', or 'p' within 2 seconds or take default...`时立刻按`p`中断正常启动，进入Bootloader菜单:
```
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
按`d`，然后输入PC的IP和固件文件名(C6300BD_1TLAUS_K2630_PATCHED.bin):
```
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
输入`3`选择`3/8 = Linux kernel&rootfs image`，随后选y或者n都行。
```
Writing image 3 to NAND flash at offset 35c0000...
NandFlashEraseBlock: Erasing block at 0x59a0000
Store parameters to flash? [n]
```
回到`Main Menu`后，可以按`b`继续启动，进入新固件。

# 相关资料
1. [NetGear GPL源码](https://archive.org/download/netgearfirmwaresgpl)
2. [OpenWrt Wiki上的C6300BD_TLAUS](https://openwrt.org/inbox/toh/netgear/c6300bd-1tlaus)
