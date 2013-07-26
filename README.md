# kdev: a script to automatize running kernel images

kdev is a series of scripts to automatize linux images creation and
running.

kdev has 4 main subcommands:

* ./kdev.sh rootfs _file.img|dir_: create a root fs into an image file or
dir (uses debootstrap)
* ./kdev.sh modules\_install _file.img|dir_: install kernel modules into
a file/dir
* ./kdev.sh qemu _bzImage_ _file.img|dir_: run a kernel bzImage using the
file dir as root fs
* help: show help page

There is a test file (test/image\_creation.sh) that shows the main kdev
subcommands in action.

