#!/bin/bash

DEFAULT_FS_TYPE=${FS_TYPE:-btrfs}

WORKSPACE_FS_TYPE=swap
DOCKER_FS_TYPE=ext4
STORAGE_FS_TYPE=ext4
LSTORAGE_FS_TYPE=ext4
HOME_FS_TYPE=ext4
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
    return
}
partition_drives_testbench() {
    return
}
partition_drives_gerrit() {
    return
}
partition_drives_relay() {
    return
}
partition_drives_monitor() {
    return
}
partition_drives_klocwork() {
    return
}
partition_drives_klocwork_legacy() {
    return
}
partition_drives_cdn_mirror() {
    return
}
partition_drives_master() {
    return
}
partition_drives_master_k8s() {
    return
}
partition_drives_node_azure() {
    return
}
test_drives_diy1() {
    return
}
get_part() {
    return
}
test_drives_testbench() {
    return
}
is_qemu() {
    return
}
test_drives_gerrit() {
    return
}
partition_drives_gerrit_cnshz() {
    return
}
test_drives_gerrit_cnshz() {
    return
}
partition_drives_fwbuild() {
    return
}
test_drives_fwbuild() {
    return
}
test_drives_azure() {
    return
}
test_drives_relay() {
    return
}
test_drives_monitor() {
    return
}
test_drives_klocwork() {
    return
}
test_drives_klocwork_legacy() {
    return
}
test_drives_node_azure() {
    return
}
test_drives_cdn_mirror () {
    return
}
test_drives_master_k8s () {
    return
}
test_drives_master() {
    return
}

# export BOOT_PART="${DISK_NAME_1}1"     ---> /dev/sda1
# export DOCKER_PART="${DISK_NAME_1}2"   ---> /dev/sda2
# export SWAP_PART="${DISK_NAME_1}3"     ---> /dev/sda3
# export STORAGE_PART="${DISK_NAME_2}1"  ---> /dev/sdb1

format_drives() {
    # Provide master boot record
    # if [[ "$BOOT_MBR" == "true" ]]; then
    #     # Setup MBR
    #     echo "Getting boot configuration"
    #     wget -O /tmp/mbr.bin               "${CONFIG_URL}/mbr.bin"
    
    #     echo "MBR routine"
    #     dd bs=440 count=1 conv=notrunc if=/tmp/mbr.bin of=$DISK_NAME_1
    # fi
    
    # Format boot partition
    # if [ -n "$BOOT_PART" ]; then
    #     echo "iPXE boot"
    #     wget -O /tmp/ipxe-$MACHINE_TYPE.hd "${CONFIG_URL}/ipxe-$MACHINE_TYPE.hd"
    #     dd if=/tmp/ipxe-$MACHINE_TYPE.hd of=${BOOT_PART}
    # fi

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

    # Format app partition
    if [ -n "$HOME_PART" ]; then
        format_part "local-home" ${HOME_PART} ${HOME_FS_TYPE}
    fi

    if $REBOOT_ON_FORMAT; then
        reboot # reboot !!!!
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

partition_drives_jenkins_cnshz() {
    #echo -en ",2M,L,*\n,1G,L,*\n,,L,-\n" | sfdisk --force $DISK_NAME_1
    echo -en ",,L,-\n" | sfdisk $DISK_NAME_2
    echo -en ",,L,-\n" | sfdisk $DISK_NAME_3
    echo -en ",,L,-\n" | sfdisk $DISK_NAME_4

    partprobe || true
}

test_drives_jenkins_cnshz() {

    export BOOT_MBR=false
    export BOOT_PART=$(blkid -t PTTYPE="dos" -o device | grep -v sr0 | head -1)
    export DOCKER_PART="/dev/disk/by-label/local-docker"
    export SWAP_PART="/dev/disk/by-label/local-swap"
    export LSTORAGE_PART="/dev/disk/by-label/local-storage"

    # 4 partitions are required, if they are not present,
    if [ ! -e "$DOCKER_PART" ] ||
       [ ! -e "$SWAP_PART" ] ||
       [ ! -e "$LSTORAGE_PART" ]; then
        # now: use coreos-install -d /dev/sda install system, so ignore /dev/sda
        # 16 + 32 + 256 + 32 G
        #export DISK_NAME_1="/dev/sda"          # 32G
        export DISK_NAME_2="/dev/sdb"          # swap 32G
        export DISK_NAME_3="/dev/sdc"          # /lstorage/git 256G
        export DISK_NAME_4="/dev/sdd"          # /lstorage 32G

        #export BOOT_PART="${DISK_NAME_1}1"
        export SWAP_PART="${DISK_NAME_2}1"
        export LSTORAGE_PART="${DISK_NAME_3}1"
        export DOCKER_PART="${DISK_NAME_4}1"

        # Detect migration
        if ! blkid | grep "${SWAP_PART}" | grep swap; then
            format_required=true
        elif [ -n "$DOCKER_PART" ] && ! blkid | grep "${DOCKER_PART}" | grep "local-docker"; then
            format_required=true
        elif [ -n "$LSTORAGE_PART" ] && ! blkid | grep "${LSTORAGE_PART}" | grep "local-storage"; then
            format_required=true
        fi

        if [[ "$format_required" == "true" ]]; then
            partition_drives_jenkins_cnshz
            format_drives
        fi
    fi

    # Docker
    check_docker_format
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
        cnshz-gerrit-master)
            test_drives_gerrit_cnshz
            ;;
        cnshz-jenkins-master)
            test_drives_jenkins_cnshz
            ;;
        coreos-fwbuild)
            test_drives_fwbuild
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
        mount_part "local-docker" ${DOCKER_PART} /var/lib/docker ${DOCKER_FS_TYPE}
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
