#!/bin/bash

DEFAULT_FS_TYPE=${FS_TYPE:-btrfs}

WORKSPACE_FS_TYPE=swap
DOCKER_FS_TYPE=ext4
STORAGE_FS_TYPE=ext4
LSTORAGE_FS_TYPE=ext4
APP_FS_TYPE=ext4
GIT_FS_TYPE=ext4
GIT_MOUNTPOINT=/lstorage/git

REBOOT_ON_FORMAT=true

source /etc/os-release
COREOS_VERSION="$VERSION"

if [ -e "/etc/farm-environment" ]; then
    source /etc/farm-environment
fi

set -xe

use_swap() {
    local part_dev=$1

    local priority=0
    local blockdev=$(dirname $(find -L /sys/block -mindepth 2 -maxdepth 2 -name $(echo $part_dev | sed 's#/dev/##')))
    if [ -z "$blockdev" ]; then
        if [ -e "/sys/block/$(echo $part_dev | sed 's#/dev/##')" ]; then
            blockdev=$(echo $part_dev | sed 's#/dev/##')
        fi
    fi

    if [ -z "$blockdev" ]; then
        echo "Unable to find device for $part_dev"
        return 1
    fi

    if [[ "$(cat ${blockdev}/queue/rotational)" == "0" ]]; then
        # SSD
        priority=10
    fi

    # Keep existing label if it contains 'swap'
    local label=$(blkid -s LABEL -o value $part_dev)
    local label_opt=""
    if [ -n "$label" ]; then
        if echo $label | grep swap; then
            label_opt=-L
        else
            label=""
        fi
    fi

    if grep $part_dev /proc/swaps; then
        echo "$part_dev already enabled, removing"
        swapoff $part_dev
        if [ $? -ne 0 ]; then
            echo "Unable to swapoff $part_dev"
            return 1
        fi
    fi

    mkswap $label_opt $label -f $part_dev
    if [ $? -ne 0 ]; then
        echo "Error formatting $part_dev"
        return 1
    fi

    swapon --priority $priority $part_dev
    if [ $? -ne 0 ]; then
        echo "Error activating swap on $part_dev"
        return 1
    fi
}

use_swap_partitions() {
    for part in $(blkid | grep swap | sed -r 's^(.*):.*^\1^g' | grep -v loop); do
        use_swap $part
    done
}

format_part() {
    local part_name=$1
    local part_dev=$2
    local part_fs=${3:-$DEFAULT_FS_TYPE}

    echo "Formatting $part_name = $part_dev ($part_fs)"
    case $part_fs in
        btrfs)
            [ -e "/usr.squashfs (deleted)" ] || touch "/usr.squashfs (deleted)" # work around a bug in mkfs.btrfs 3.12
            mkfs.btrfs -L ${part_name} -f ${part_dev}
            ;;
        xfs)
            mkfs.xfs -L ${part_name} -f ${part_dev}
            ;;
        ext4)
            mkfs.ext4 -L ${part_name} -F ${part_dev}
            ;;
        swap)
            mkswap -L ${part_name} -f ${part_dev}
            ;;
        bind | zfs)
            echo "Nothing to do for ${part_fs}"
            ;;
        *)
            echo "Unknown fs '${part_fs}'"
            exit 1
            ;;
    esac
}

mount_part() {
    local part_name=$1
    local part_dev=$2
    local part_mountpoint=$3
    local part_fs=${4:-$DEFAULT_FS_TYPE}
    local part_opt=$5

    local type_arg=-t

    echo "Mounting $part_name = $part_dev ($part_fs)"
    case $part_fs in
        btrfs)
            [ -n "$part_opt" ] || part_opt="rw,noatime"
            ;;
        ext4)
            [ -n "$part_opt" ] || part_opt="rw,noatime"
            ;;
        tmpfs)
            [ -n "$part_opt" ] || part_opt="size=128g"
            ;;
        bind | zfs)
            part_opt="bind"
            type_arg=""
            part_fs=""
            ;;
        *)
            echo "Unknown fs '$part_fs'"
            exit 1
            ;;
    esac

    mount ${part_dev} ${part_mountpoint} ${type_arg} ${part_fs} -o ${part_opt}
}

partition_drives_diy1() {
    if [ $DISK_PART_1 -eq 4 ]; then
        # Disk 1: 2 partitions [512M,+]
        echo -en ",512M,L,*\n,,L,-\n" | sfdisk --force $DISK_NAME_1
    else
        echo "Invalid configuration for disk 1"
    fi

    if [ $DISK_PART_2 -eq 2 ]; then
        # Disk 2: 3 partitions [128G,+]
        echo -en ",128G,L,-\n,128G,L,-\n,,L,-\n" | sfdisk --force $DISK_NAME_2
    else
        echo "Invalid configuration for disk 2"
    fi

    partprobe || true
}

partition_drives_testbench() {
    if [ $DISK_PART_1 -eq 3 ]; then
        # Disk 1: 3 partitions [2M,30G,+]
        echo -en ",2M,L,*\n,30G,L,-\n,,L,-\n" | sfdisk --force $DISK_NAME_1
    else
        echo "Invalid configuration for disk 1"
    fi

    partprobe || true
}

partition_drives_gerrit() {
    echo -en ",2M,L,*\n,10G,L,-\n,,L,-\n" | sfdisk --force $DISK_NAME_1
    echo -en ",,L,-\n" | sfdisk $DISK_NAME_2

    partprobe || true
}

partition_drives_relay() {

    # Do not overwrite the git partition if it already exists
    if ! [ -e "/dev/disk/by-label/local-git" ]; then
        echo -en ",,L,-\n" | sfdisk $DISK_NAME_1
    fi

    if [ -n "$DISK_NAME_2" ]; then
        echo -en ",,L,-\n" | sfdisk $DISK_NAME_2
    fi

    partprobe || true
}

partition_drives_monitor() {
    echo -en ",,L,-\n" | sfdisk $DISK_NAME_1

    partprobe || true
}

partition_drives_klocwork() {
    local disk_name=$1
    echo -en ",,L,-\n" | sfdisk ${disk_name}

    partprobe || true
}

partition_drives_klocwork_legacy() {
    echo -en ",2M,L,*\n,,L,-\n" | sfdisk $DISK_NAME_1
    echo -en ",32G,L,*\n,,L,-\n" | sfdisk $DISK_NAME_2

    partprobe || true
}

partition_drives_cdn_mirror() {
    echo -en ",2M,L,*\n,,L,-\n" | sfdisk $DISK_NAME_1
    echo -en ",32G,L,*\n,,L,-\n" | sfdisk $DISK_NAME_2

    partprobe || true
}

partition_drives_master() {
    echo -en ",,L,-\n" | sfdisk $DISK_NAME_1

    partprobe || true
}

partition_drives_master_k8s() {
    echo -en ",,L,-\n" | sfdisk $DISK_NAME_1

    partprobe || true
}

partition_drives_node_azure() {

    echo -en "${DISK_PARTITIONS_1}" | sfdisk --force $DISK_NAME_1

    if [ -e "$DISK_NAME_2" ]; then
        echo -en "${DISK_PARTITIONS_2}"  | sfdisk $DISK_NAME_2
    fi

    partprobe || true
}

format_drives() {
    # Provide master boot record
    if [[ "$BOOT_MBR" == "true" ]]; then
        # Setup MBR
        echo "Getting boot configuration"
        wget -O /tmp/mbr.bin               "${CONFIG_URL}/mbr.bin"

        echo "MBR routine"
        dd bs=440 count=1 conv=notrunc if=/tmp/mbr.bin of=$DISK_NAME_1
    fi

    # Format boot partition
    if [ -n "$BOOT_PART" ]; then
        echo "iPXE boot"
        wget -O /tmp/ipxe-$MACHINE_TYPE.hd "${CONFIG_URL}/ipxe-$MACHINE_TYPE.hd"
        dd if=/tmp/ipxe-$MACHINE_TYPE.hd of=${BOOT_PART}
    fi

    # Format jenkins workspace
    if [ -n "$WORKSPACE_PART" ]; then
        format_part "local-workspace" ${WORKSPACE_PART} ${WORKSPACE_FS_TYPE}
    fi

    # Format docker partition
    if [ -n "$DOCKER_PART" ]; then
        format_part "local-docker" ${DOCKER_PART} ${DOCKER_FS_TYPE}
    fi

    # Format swap partition
    if [ -n "$SWAP_PART" ]; then
        format_part "local-swap" ${SWAP_PART} swap
    fi

    # Format storage partition
    if [ -n "$STORAGE_PART" ]; then
        format_part "storage" ${STORAGE_PART} ${STORAGE_FS_TYPE}
    fi

    # Format local storage partition
    if [ -n "$LSTORAGE_PART" ]; then
        format_part "local-storage" ${LSTORAGE_PART} ${LSTORAGE_FS_TYPE}
    fi

    # Format git partition
    if [ -n "$GIT_PART" ]; then
        format_part "local-git" ${GIT_PART} ${GIT_FS_TYPE}
    fi

    # Format app partition
    if [ -n "$APP_PART" ]; then
        format_part "app-storage" ${APP_PART} ${APP_FS_TYPE}
    fi

    if $REBOOT_ON_FORMAT; then
        reboot
        sleep 120
        exit 1
    fi
}

check_docker_format() {
    local format_docker_required=false

    # Docker: format if partition is marked for removal
    if blkid | grep "local-docker-rm"; then
        format_docker_required=true

    # Docker: format if there is less than 20% free
    elif [[ "$DOCKER_FS_TYPE" == "btrfs" ]]; then
        if btrfs fi show $DOCKER_PART | grep used | grep -qe "used \([0-9]*\).*GiB"; then
            USED_SPACE=$(btrfs fi show $DOCKER_PART | grep used | tail -1 | sed 's/.* used \([0-9]*\).*GiB .*/\1/g')
            TOTAL_SPACE=$(btrfs fi show $DOCKER_PART | grep size | tail -1 | sed 's/.* size \([0-9]*\).*GiB .*/\1/g')
            if [[ $(((USED_SPACE*100)/TOTAL_SPACE)) -gt 80 ]]; then
                format_docker_required=true
            fi
        fi

    # Docker: partition type has changed
    elif [[ "$DOCKER_FS_TYPE" == "ext4" ]] && [ -n "${DOCKER_PART}" ] && ! dumpe2fs -h "${DOCKER_PART}"; then
        format_docker_required=true
    fi

    if [[ "$format_docker_required" == "true" ]] && [ -n "${DOCKER_PART}" ]; then
        format_part 'local-docker' ${DOCKER_PART} ${DOCKER_FS_TYPE}
        return 1
    fi

    return 0
}

write_config() {
    local part_env="/etc/part-environment"

    rm -f "${part_env}.tmp"
    touch "${part_env}.tmp"

    [ -z "$BOOT_PART" ] || echo "BOOT_PART=${BOOT_PART}" >> "${part_env}.tmp"
    [ -z "$DOCKER_PART" ] || echo "DOCKER_PART=${DOCKER_PART}" >> "${part_env}.tmp"
    [ -z "$WORKSPACE_PART" ] || echo "WORKSPACE_PART=${WORKSPACE_PART}" >> "${part_env}.tmp"
    [ -z "$SWAP_PART" ] || echo "SWAP_PART=${SWAP_PART}" >> "${part_env}.tmp"
    [ -z "$STORAGE_PART" ] || echo "STORAGE_PART=${STORAGE_PART}" >> "${part_env}.tmp"
    [ -z "$LSTORAGE_PART" ] || echo "LSTORAGE_PART=${LSTORAGE_PART}" >> "${part_env}.tmp"
    [ -z "$GIT_PART" ] || echo "GIT_PART=${GIT_PART}" >> "${part_env}.tmp"

    rm -f "${part_env}"
    mv "${part_env}.tmp" "${part_env}"
}

test_drives_diy1() {
    local format_required=false

    # DIY servers
    export DISK_PART_1=2 # SSD
    export DISK_PART_2=2 # HDD

    # Try to detect
    local disk_ssd_name=$(ls -1 /dev/disk/by-id/ | grep -v '\-part' | grep -iE '(SSD|Kingston)' | head -1)
    if [ -n "$disk_ssd_name" ]; then
        # Detection OK

        # SSD
        export DISK_NAME_1="$(readlink -f /dev/disk/by-id/${disk_ssd_name})"

        # HDD
        local disk_hdd_name=$(ls -1 /dev/disk/by-id/ | grep -v '\-part' | grep -v "${disk_ssd_name}" | grep -v 'DVD' | head -1)
        if [ -z "$disk_hdd_name" ]; then
            echo "Error: only one hard drive present in server"
            exit 1
        fi
        export DISK_NAME_2="$(readlink -f /dev/disk/by-id/${disk_hdd_name})"
    else
        # Detection failed, fallback to default configuration
        export DISK_NAME_1="/dev/sda"
        export DISK_NAME_2="/dev/sdb"
    fi

    echo "SSD: ${DISK_NAME_1}"
    echo "HDD: ${DISK_NAME_2}"

    export BOOT_MBR=false # PXE boot or MBR is installed by 'erase' USB key
    export BOOT_PART="${DISK_NAME_1}1"
    export GIT_PART="${DISK_NAME_1}2"
    export SWAP_PART="${DISK_NAME_2}1"
    export DOCKER_PART="${DISK_NAME_2}2"
    export LSTORAGE_PART="${DISK_NAME_2}3"

    if blkid | grep "ROOT"; then
        echo "!!! WRONG BOOT CONFIG !!!"
        tail -f /dev/null
    fi

    # Detect migration
    if ! blkid | grep "${SWAP_PART}" | grep swap; then
        format_required=true
    elif [ -n "$GIT_PART" ] && ! blkid | grep "${GIT_PART}" | grep "local-git"; then
        format_required=true
    elif [ -n "$DOCKER_PART" ] && ! blkid | grep "${DOCKER_PART}" | grep "local-docker"; then
        format_required=true
    fi

    if [[ "$format_required" == "true" ]]; then
        partition_drives_diy1
        format_drives
    fi

    # Docker
    check_docker_format
}

get_part() {
    local disk=$1
    local part_nb=${2:-1}

    sfdisk -l $disk | grep -E "^$disk" | head -$part_nb | tail -1 | awk '{print $1}'
}

test_drives_testbench() {
    local format_required=false

    unset DISK_NAME_1
    export DISK_PART_1=3

    for block in $(ls -1 /sys/block | grep -vE "(loop|sr[0-9]|dm-)"); do
        if [ -z "$DISK_NAME_1" ]; then
            # Grab first partition, if available
            BOOT_PART=$(get_part /dev/$block 1)
            if [ -z "$BOOT_PART" ]; then
                echo "Device is blank, using /dev/$block"
                format_required=true
            elif blkid | grep "/dev/$block" | grep 'local-docker'; then
                echo "Device was previously used, so reusing"
            else
                format_required=true
            fi

            DISK_NAME_1=/dev/$block
        fi
    done

    if [[ "$format_required" == "true" ]]; then
        partition_drives_testbench
    fi

    export BOOT_MBR=true
    export BOOT_PART=$(get_part $DISK_NAME_1 1)
    export DOCKER_PART=$(get_part $DISK_NAME_1 2)
    export LSTORAGE_PART=$(get_part $DISK_NAME_1 3)

    if [[ "$format_required" == "true" ]]; then
        format_drives
    fi

    # Docker
    check_docker_format

    # Activate all VGs on the server (for ceph)
    vgchange -ay
}

is_qemu() {
    grep -qi qemu /proc/cpuinfo
}

test_drives_gerrit() {

    export BOOT_MBR=true
    export BOOT_PART=$(blkid -t PTTYPE="dos" -o device | head -1)
    export DOCKER_PART="/dev/disk/by-label/local-docker"
    export SWAP_PART="/dev/disk/by-label/local-swap"
    if [ -e "/dev/disk/by-label/local-storage" ]; then
        export LSTORAGE_PART="/dev/disk/by-label/local-storage"
    else
        export LSTORAGE_PART="/dev/disk/by-label/storage"
    fi

    # 4 partitions are required, if they are not present,
    # let the admin take care of it (unless we are in QEmu).
    if [ -z "$BOOT_PART" ] ||
       [ ! -e "$DOCKER_PART" ] ||
       [ ! -e "$SWAP_PART" ] ||
       [ ! -e "$LSTORAGE_PART" ]; then
        if is_qemu; then
            echo "QEmu detected, partitioning ..."

            export DISK_NAME_1="/dev/sda"
            export DISK_NAME_2="/dev/sdb"

            export BOOT_PART="${DISK_NAME_1}1"
            export DOCKER_PART="${DISK_NAME_1}2"
            export SWAP_PART="${DISK_NAME_1}3"
            export STORAGE_PART="${DISK_NAME_2}1"

            partition_drives_gerrit
            format_drives
        else
            DOCKER_PART="$(blkid | grep "local-docker" | awk '{print $1}' | sed 's/://')"
            if [ -n "$DOCKER_PART" ]; then
                # Might need to format docker
                if ! check_docker_format; then
                    reboot
                    sleep 120
                    exit 1
                fi
            fi

            echo "Manual partitioning required"
            exit 1
        fi
    fi

    # Docker
    check_docker_format
}

test_drives_azure() {
    local resource_as_swap=${1:-true}

    if [[ "$FARM_PLATFORM" != "cloud-azure" ]]; then
        return 0
    fi

    if grep " /mnt/resource " /proc/mounts; then
        local disk_res="$(grep " /mnt/resource " /proc/mounts | awk '{print $1}' | sed 's/[0-9]*//g')"

        echo "Local disk as $disk_res"

        # Resource storage is mounted, so umount, force format and reboot
        if ! umount /mnt/resource; then
            echo "WARN: Error unmounting /mnt/resource"
        fi

        # Force MBR erase
        dd if=/dev/zero of="${disk_res}" count=10 bs=1M

        # jbd2 keeps the partition busy, so we can't do much as this point and
        # we need to reboot to actually free it
        reboot
        sleep 120
        exit 1
    fi

    # Use temp storage as swap
    if [[ "$resource_as_swap" == "true" ]]; then
        export DISK_NAME_2="/dev/sdb"
        export SWAP_PART="/dev/sdb"

        format_part "local-swap" ${SWAP_PART} swap
    fi

    # Force temp disk to be seen as SSD
    if [ -e "/sys/block/sdb/queue/rotational" ] && \
       [[ "$(cat /sys/block/sdb/queue/rotational)" == "1" ]]; then
        echo 0 | tee /sys/block/sdb/queue/rotational
    fi
}

test_drives_relay() {
    local format_required=false

    test_drives_azure true

    export DISK_NAME_1="/dev/sdc"
    export DISK_NAME_2="/dev/sdd"

    export GIT_PART="/dev/sdc1"
    export LSTORAGE_PART="/dev/sdd1"

    if ! blkid | grep "${GIT_PART}" | grep "local-git"; then
        format_required=true
    elif ! blkid | grep "${LSTORAGE_PART}" | grep "local-storage"; then
        format_required=true
    fi

    if [[ "$format_required" == "true" ]]; then
        partition_drives_relay
        format_drives
    fi
}

test_drives_monitor() {
    local format_required=false

    test_drives_azure true

    export DISK_NAME_1="/dev/sdc"
    export LSTORAGE_PART="/dev/sdc1"

    if ! blkid | grep "${LSTORAGE_PART}" | grep "local-storage"; then
        format_required=true
    fi

    if [[ "$format_required" == "true" ]]; then
        partition_drives_monitor
        format_drives
    fi
}

test_drives_klocwork() {

    test_drives_azure true

    export DISK_NAME_1="/dev/sdc"
    export LSTORAGE_PART="/dev/sdc1"
    if ! blkid | grep "${LSTORAGE_PART}" | grep "local-storage"; then
        partition_drives_klocwork "$DISK_NAME_1"
        format_drives
    fi

    export DISK_NAME_2="/dev/sdd"
    export APP_PART="/dev/sdd1"
    export APP_MOUNTPOINT="/lstorage/services/fossology/"
    if ! blkid | grep "${APP_PART}" | grep "app-storage"; then
        unset LSTORAGE_PART
        partition_drives_klocwork "${DISK_NAME_2}"
        format_drives
        export LSTORAGE_PART="/dev/sdc1"
    fi
}

test_drives_klocwork_legacy() {
    local format_required=false

    export BOOT_MBR=true

    export DISK_NAME_1="/dev/sda"
    export DISK_NAME_2="/dev/sdb"

    export BOOT_PART="${DISK_NAME_1}1"
    export DOCKER_PART="${DISK_NAME_1}2"

    export SWAP_PART="${DISK_NAME_2}1"
    export STORAGE_PART="${DISK_NAME_2}2"

    if ! blkid | grep "${DOCKER_PART}" | grep "local-docker"; then
        format_required=true
    fi

    if [[ "$format_required" == "true" ]]; then
        partition_drives_klocwork_legacy
        format_drives
    fi
}

test_drives_cdn_mirror() {
    local format_required=false

    export BOOT_MBR=true

    export DISK_NAME_1="/dev/sda"
    export DISK_NAME_2="/dev/sdb"

    export BOOT_PART="${DISK_NAME_1}1"
    export DOCKER_PART="${DISK_NAME_1}2"

    export SWAP_PART="${DISK_NAME_2}1"
    export LSTORAGE_PART="${DISK_NAME_2}2"

    if ! blkid | grep "${DOCKER_PART}" | grep "local-docker"; then
        format_required=true
    fi

    if [[ "$format_required" == "true" ]]; then
        partition_drives_cdn_mirror
        format_drives
    else
        # Docker
        check_docker_format
    fi
}

test_drives_master_k8s() {
    export BOOT_MBR=true

    if [[ "$FARM_PLATFORM" == "cloud-azure" ]]; then
        test_drives_azure false

        export DISK_NAME_1="/dev/sdc"
        export LSTORAGE_PART="${DISK_NAME_1}1"

        if [ ! -e "/dev/disk/by-label/local-storage" ]; then
            partition_drives_master_k8s
            format_drives
        fi

    elif [[ "$MACHINE_TYPE" == "carmd-master3" ]]; then
        export DISK_NAME_1="/dev/sda"
        export DISK_NAME_2="/dev/sdb"

        export BOOT_PART="${DISK_NAME_1}1"
        export DOCKER_PART="${DISK_NAME_1}2"

        export LSTORAGE_PART="${DISK_NAME_2}2"
    else
        echo "Unsupported machine $MACHINE_TYPE"
    fi

    if [ -n "$DOCKER_PART" ]; then
        # Docker
        check_docker_format
    fi
}

test_drives_master() {
    local format_required=false

    test_drives_azure true

    if [[ "$FARM_PLATFORM" == "cloud-azure" ]]; then

        export DISK_NAME_1="/dev/sdc"
        export LSTORAGE_PART="/dev/sdc1"

        export GIT_PART="/dev/disk/by-label/local-git"
        export GIT_MOUNTPOINT=/storage/git

        GIT_DISK=$(readlink -f ${GIT_PART} | sed 's/[0-9]*//g')

        if ! blkid | grep "${LSTORAGE_PART}" | grep "local-storage"; then
            format_required=true
        fi

        export PATH="/var/run/torcx/bin:${PATH}"

        if ! which zpool; then

            TORCX_ZFS_VERSION=$(curl https://api.github.com/repos/swi-infra/torcx-zfs-bin/tags \
                                | jq -r '.[].name' \
                                | grep "${COREOS_VERSION}" \
                                | head -1)
            if [ -z "$TORCX_ZFS_VERSION" ]; then
                echo "Unable to determine torcx-zfs version"
                exit 1
            fi

            ZOL_VERSION="$(echo "$TORCX_ZFS_VERSION" | sed 's/-.*//')"

            echo zfs > /etc/torcx/next-profile

            tee /etc/torcx/profiles/zfs.json <<ZfsProfile
{
  "kind": "profile-manifest-v0",
  "value": {
    "images": [
      {
        "name": "zfs",
        "reference": "$ZOL_VERSION"
      }
    ]
  }
}
ZfsProfile

            source /etc/os-release

            mkdir -p "/var/lib/torcx/store/$COREOS_VERSION/"
            wget -O "/var/lib/torcx/store/$COREOS_VERSION/zfs:${ZOL_VERSION}.torcx.tgz" \
                "https://cdn.rawgit.com/swi-infra/torcx-zfs-bin/${TORCX_ZFS_VERSION}/zfs%3A${ZOL_VERSION}.torcx.tgz"

            echo "ZFS torcx installed, rebooting!"
            reboot
        fi

        if ! zpool status farm; then
            if [[ "$FORCE_CREATE_POOL" == "true" ]] || \
               ( ! zpool import farm && [ -n "$FARM_ENV" ] && [[ "$FARM_ENV" != "production" ]] ); then
                # If the pool cannot be imported, create if:
                # Farm environment is not prod
                # OR
                # Creation is being forced through FORCE_CREATE_POOL

                echo "Creating zfs pool ..."

                CACHE_DISKS=""
                DATA_DISKS=""

                # List all block devices sda->sdz, except the first 3, which are:
                # sda -> os
                # sdb -> resource disk
                # sdc -> storage
                # sdd -> git
                # ... but the order of letters might be different ...
                for disk in $(ls -1 /sys/class/block/ | grep '^sd[a-z]$' | tail -n +3); do
                    if [[ "$disk" == "$(basename $GIT_DISK)" ]]; then
                        echo "Ignoring git disk"
                    elif [ $(cat "/sys/class/block/$disk/size") -lt $((200*1024*1024*2)) ]; then
                        # If the disk if less than 200GB, use as log disk
                        if [[ "$FARM_ENV" == "production" ]]; then
                            CACHE_DISKS+=" /dev/$disk"
                        fi
                    elif [ $(cat "/sys/class/block/$disk/size") -gt $((1024*1024*1024*2)) ]; then
                        # If the disk if less than 1TB, use as data disk
                        DATA_DISKS+=" /dev/$disk"
                    fi
                done

                echo "Cache (L2ARC) disks: $CACHE_DISKS"
                echo "Data disks: $DATA_DISKS"

                zpool create farm $DATA_DISKS

                zfs create farm/storage
                zfs set compression=lz4 atime=off farm/storage

                if [ -n "$CACHE_DISKS" ]; then
                    zpool add farm cache $CACHE_DISKS
                fi
            else
                exit 1
            fi
        fi

        export STORAGE_PART=/farm/storage
        export STORAGE_FS_TYPE=zfs

    elif [[ "$FARM_PLATFORM" == "virtualbox" ]]; then
        if [ -e "/dev/sdb" ]; then
            SWAP_PART="/dev/sdb"
        fi
        export LSTORAGE_PART=/storage
        export LSTORAGE_FS_TYPE=bind
    fi

    if [[ "$format_required" == "true" ]]; then
        partition_drives_master
        format_drives
    else
        # Docker
        check_docker_format
    fi
}

get_disk_size() {
    cat "/sys/block/$(basename "$1")/size"
}

test_drives_node_azure() {
    local format_required=false

    test_drives_azure false

    # Make sure that Azure provided us with:
    # - ROOT disk as sda
    # - temp disk as sdb
    # - local-git as sdc
    if ! readlink -f "/dev/disk/by-label/ROOT" | grep "sda"; then
        local root_disk="$(readlink -f "/dev/disk/by-label/ROOT")"
        echo "ROOT on ${root_disk} while expecting it to be on sda, rebooting"
        reboot
        sleep 120
        exit 1
    elif [ -e "/dev/disk/by-label/local-git" ] && ! readlink -f "/dev/disk/by-label/local-git" | grep "sdc"; then
        local git_disk="$(readlink -f "/dev/disk/by-label/local-git")"
        echo "local-git on ${git_disk} while expecting local SSD on sdb and HDD on sdc, rebooting"
        reboot
        sleep 120
        exit 1
    fi

    # Use local SSD for local-storage, docker and swap
    export DISK_NAME_1="/dev/sdb"
    export LSTORAGE_PART=/dev/sdb1
    export DOCKER_PART=/dev/sdb2
    export WORKSPACE_PART=/dev/sdb3

    if [ "$(get_disk_size $DISK_NAME_1)" -gt 117500000 ]; then
        DISK_PARTITIONS_1=",1G,L,*\n,75G,L,*\n,,L,-\n"
    elif [ "$(get_disk_size $DISK_NAME_1)" -gt 50500000 ]; then
        DISK_PARTITIONS_1=",1G,L,*\n,30G,L,*\n,,L,-\n"
    else
        DISK_PARTITIONS_1=",1G,L,*\n,24G,L,*\n,,L,-\n"
    fi

    REBOOT_ON_FORMAT=false
    WORKSPACE_MIN_SIZE=20971520 # Min 10gb
    DOCKER_MIN_SIZE=20971520 # Min 10gb
    if [[ "$FARM_ENV" != "production" ]]; then
        DOCKER_MIN_SIZE=52500000
    fi

    # Use spare HDD as swap (if available)
    export DISK_NAME_2="/dev/sdd"
    export SWAP_PART="/dev/sdd1"
    DISK_PARTITIONS_2=",,L,-\n"

    GERRIT_MODE=${GERRIT_MODE:-mirror}

    # If there is no git disk, then the swap disk appears
    # as sdc.
    if [ ! -e "/dev/disk/by-label/local-git" ]; then
        if [ ! -e "$DISK_NAME_2" ]; then
            export DISK_NAME_2="/dev/sdc"
            export SWAP_PART="/dev/sdc1"
        fi

        if [[ "$GERRIT_MODE" == "mirror" ]]; then
            # Wait 10 minutes for the partition
            for (( i=0; i<60; i++ )); do
                if [ ! -e "/dev/disk/by-label/local-git" ]; then
                    echo "Warning: git partition doesn't exist"
                    sleep 10
                else
                    break
                fi
            done

            if [ ! -e "/dev/disk/by-label/local-git" ]; then
                exit 1
            fi
        fi
    fi

    if ! [ -e "/dev/disk/by-label/local-storage" ]; then
        format_required=true
    elif ! [ -e "/dev/disk/by-label/local-docker" ]; then
        format_required=true
    elif [ -n "$WORKSPACE_PART" ] && [ ! -e "/sys/block/$(basename $DISK_NAME_1)/$(basename $WORKSPACE_PART)/size" ] || \
         [ "$(cat "/sys/block/$(basename $DISK_NAME_1)/$(basename $WORKSPACE_PART)/size")" -lt $WORKSPACE_MIN_SIZE ]; then
        # If the workspace part doesn't have enough space, reformat.
        format_required=true
    elif [ -n "$DOCKER_PART" ] && [ ! -e "/sys/block/$(basename $DISK_NAME_1)/$(basename $DOCKER_PART)/size" ] || \
         [ "$(cat "/sys/block/$(basename $DISK_NAME_1)/$(basename $DOCKER_PART)/size")" -lt $DOCKER_MIN_SIZE ]; then
        # If the docker part doesn't have enough space, reformat.
        format_required=true
    elif [ -n "$DISK_NAME_2" ] && [ -e "$DISK_NAME_2" ] && [ ! -e "/dev/disk/by-label/local-swap" ]; then
        format_required=true
        REBOOT_ON_FORMAT=true
    fi

    if [[ "$format_required" == "true" ]]; then

        # Make sure that the swap is not in use
        if [ -e "${WORKSPACE_PART}" ]; then
            swapoff "${WORKSPACE_PART}" || true
        fi

        partition_drives_node_azure
        format_drives
    else
        # Docker
        check_docker_format
    fi

    partprobe || true
    sleep 10

    # Might not be available depending on the configuration.
    export GIT_PART="/dev/disk/by-label/local-git"
    if [ ! -e "$GIT_PART" ]; then
        if [[ "$GERRIT_MODE" == "mirror" ]]; then
            echo "Something is wrong, local-git should exist"
            exit 1
        fi

        unset GIT_PART
    else
        # Treat as SSD
        echo 0 | tee /sys/block/sdc/queue/rotational
    fi
}

test_drives() {
    case "$MACHINE_TYPE" in
        node-diy1)
            test_drives_diy1
            ;;
        node-testbench*)
            test_drives_testbench
            ;;
        node-azure)
            test_drives_node_azure
            ;;
        gerrit-*)
            test_drives_gerrit
            ;;
        klocwork)
            test_drives_klocwork
            ;;
        klocwork_legacy)
            test_drives_klocwork_legacy
            ;;
        cdn-mirror)
            test_drives_cdn_mirror
            ;;
        master-k8s | carmd-master*)
            test_drives_master_k8s
            ;;
        relay)
            test_drives_relay
            ;;
        monitor)
            test_drives_monitor
            ;;
        nas)
            # Deprecated
            exit 1
            ;;
        master)
            test_drives_master
            ;;
        *)
            ;;
    esac

    # Write part config
    write_config
}

mount_local_storage() {
    # Docker: Handled in cloud-config (ie, node-diy1.yml)
    if [ -n "$DOCKER_PART" ]; then
        mkdir -p /var/lib/docker
    fi

    # Jenkins Workspace
    if [ -n "$WORKSPACE_PART" ]; then
        mkdir -p /home/jenkins/workspace
        if [[ "${WORKSPACE_FS_TYPE}" == "swap" ]]; then
            mount_part "local-workspace" tmpfs              /home/jenkins/workspace tmpfs "size=256g,nr_inodes=0"
        else
            mount_part "local-workspace" ${WORKSPACE_PART}  /home/jenkins/workspace ${WORKSPACE_FS_TYPE}
        fi
        chown 1000:1000 /home/jenkins/workspace
    fi

    # Storage
    if [ -n "$STORAGE_PART" ]; then
        mkdir -p /storage
        mount_part "storage" ${STORAGE_PART} /storage ${STORAGE_FS_TYPE}
        chown 1000:1000 /storage
    fi

    # Local storage
    if [ -n "$LSTORAGE_PART" ]; then
        mkdir -p /lstorage
        mount_part "local-storage" ${LSTORAGE_PART} /lstorage ${LSTORAGE_FS_TYPE}
        chown 1000:1000 /lstorage
    fi

    # Local storage swap
    if [ -n "$LSTORAGE_PART" ] && [ -e "/lstorage/swapfile" ]; then
        swapon /lstorage/swapfile
    fi

    # Git
    if [ -n "$GIT_PART" ]; then
        mkdir -p ${GIT_MOUNTPOINT}
        mount_part "local-git" ${GIT_PART} ${GIT_MOUNTPOINT} ${GIT_FS_TYPE}
        chown 1000:1000 ${GIT_MOUNTPOINT}
    fi

    # Application storage
    if [ -n "$APP_PART" ]; then
        mkdir -p ${APP_MOUNTPOINT}
        mount_part "app-storage" ${APP_PART} ${APP_MOUNTPOINT} ${APP_FS_TYPE}
        chown 1000:1000 ${APP_MOUNTPOINT}
    fi
}

update_disk_options() {
    if [[ "$MACHINE_TYPE" == "node-diy1" ]]; then
        local disk_ssd=$(basename "$DISK_NAME_1")

        if [ -n "$disk_ssd" ] && [ -e "/sys/block/$disk_ssd" ]; then
            cat /sys/block/$disk_ssd/queue/scheduler

            # Use deadline scheduler instead of CFQ
            echo deadline > /sys/block/$disk_ssd/queue/scheduler

            # Mark disk as non-rotational
            echo 0 > /sys/block/$disk_ssd/queue/rotational
        fi
    fi
}

MACHINE_TYPE=${2:-node-diy1}

case "$1" in
    start)
        test_drives
        update_disk_options
        use_swap_partitions
        mount_local_storage
        ;;
    stop)
        ;;
    restart)
        $0 stop
        $0 start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart} <machine type>"
        exit 1
        ;;
esac

exit 0
