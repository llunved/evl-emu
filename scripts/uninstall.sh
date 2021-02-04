#!/bin/bash


set -x

SERVICE=$IMAGE

env

# Make sure the host is mounted
if [ ! -d /host/etc -o ! -d /host/proc -o ! -d /host/var/run ]; then
	    echo "Host file system is not mounted at /host" >&2
	        exit 1
fi

# Remove udev rules
rm -f /host/etc/udev/rules.d/10-insteon.rules
# Remove the container and unit file
chroot /host systemctl stop ${NAME}
chroot /host systemctl disable ${NAME}
rm -fv /host/etc/systemd/system/dockerregistry.service
chroot /host /usr/bin/podman rm ${NAME}

