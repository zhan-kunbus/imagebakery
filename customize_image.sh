#!/bin/sh
# customize raspbian image for revolution pi

if [ "$#" != 1 ] ; then
	echo 1>&1 "Usage: `basename $0` <image>"
	exit 1
fi

set -ex

IMAGEDIR=/tmp/img.$$
BAKERYDIR=`dirname $0`

# mount ext4 + FAT filesystems
losetup /dev/loop0 $1
partprobe /dev/loop0
mkdir $IMAGEDIR
mount /dev/loop0p2 $IMAGEDIR
mount /dev/loop0p1 $IMAGEDIR/boot

# copy templates
cp $BAKERYDIR/templates/cmdline.txt $IMAGEDIR/boot
cp $BAKERYDIR/templates/config.txt $IMAGEDIR/boot

# copy piTest source code
git clone https://github.com/RevolutionPi/piControl /tmp/piControl.$$
cp -pr /tmp/piControl.$$/piTest $IMAGEDIR/home/pi/demo
cp -p /tmp/piControl.$$/piControl.h $IMAGEDIR/home/pi/demo
sed -i -r -e 's%\.\./%%' $IMAGEDIR/home/pi/demo/Makefile
chown -R 1000:1000 $IMAGEDIR/home/pi/demo
chmod -R a+rX $IMAGEDIR/home/pi/demo
rm -r /tmp/piControl.$$

# customize settings
echo Europe/Berlin > $IMAGEDIR/etc/timezone
rm $IMAGEDIR/etc/localtime
echo RevPi > $IMAGEDIR/etc/hostname
sed -i -e 's/raspberrypi/RevPi/g' $IMAGEDIR/etc/hosts
echo piControl >> $IMAGEDIR/etc/modules
sed -i -r -e 's/^(XKBLAYOUT).*/\1="de"/'		\
	  -e 's/^(XKBVARIANT).*/\1="nodeadkeys"/'	\
	  $IMAGEDIR/etc/default/keyboard
install -d -m 755 -o root -g root $IMAGEDIR/etc/revpi
ln -s /var/www/pictory/projects/_config.rsc $IMAGEDIR/etc/revpi/config.rsc

# activate settings
chroot $IMAGEDIR dpkg-reconfigure -fnoninteractive keyboard-configuration
chroot $IMAGEDIR dpkg-reconfigure -fnoninteractive tzdata

# free up disk space
dpkg --root $IMAGEDIR --purge `egrep -v '^#' $BAKERYDIR/debs-to-remove`

# avoid installing unnecessary packages on this space-constrained machine
echo 'APT::Install-Recommends "false";' >> $IMAGEDIR/etc/apt/apt.conf

# download and install missing packages
chroot $IMAGEDIR apt-get update
chroot $IMAGEDIR apt-get -y install `egrep -v '^#' $BAKERYDIR/debs-to-download`
chroot $IMAGEDIR apt-get clean

# annoyingly, the postinstall script starts apache2 on fresh installs
mount -t proc procfs $IMAGEDIR/proc
chroot $IMAGEDIR /etc/init.d/apache2 stop
umount $IMAGEDIR/proc

# configure apache2
chroot $IMAGEDIR a2enmod ssl

# remove package lists, they will be outdated within days
rm $IMAGEDIR/var/lib/apt/lists/*Packages

# install local packages
dpkg --root $IMAGEDIR --force-depends --purge pixel-wallpaper
dpkg --root $IMAGEDIR -i $BAKERYDIR/debs-to-install/*.deb

# remove logs
find $IMAGEDIR/var/log -type f -delete

# clean up
umount $IMAGEDIR/boot
umount $IMAGEDIR
rmdir $IMAGEDIR
fsck.vfat -a /dev/loop0p1
fsck.ext4 -f -p /dev/loop0p2
delpart /dev/loop0 1
delpart /dev/loop0 2
losetup -d /dev/loop0
