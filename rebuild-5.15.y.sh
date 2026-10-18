#!/usr/bin/env bash
# Historical filename retained for compatibility; supports the pinned modern build.
# Run as root on the host (not inside the Armbian build container).
set -Eeuo pipefail

cpu_frequency="${1:-1296mhz}"
board="${2:-l1pro}"
case "$cpu_frequency" in 1296mhz|1392mhz|1512mhz) ;; *) echo "Unsupported CPU frequency: $cpu_frequency" >&2; exit 2 ;; esac
case "$board" in l1pro|chainedbox) ;; *) echo "Unsupported board: $board" >&2; exit 2 ;; esac
if (( EUID != 0 )); then echo "Run this script as root (sudo)." >&2; exit 2; fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
image_dir="$repo_dir/build/output/images"
dtb_dir="$repo_dir/dtbs/5.15.y-bsp"
shopt -s nullglob
images=( "$image_dir"/*.img )
(( ${#images[@]} == 1 )) || { echo "Expected exactly one uncompressed .img in $image_dir" >&2; exit 1; }
image="${images[0]}"
dtb="$dtb_dir/rk3328-l1pro-${cpu_frequency}.dtb"
[[ -s "$dtb" ]] || { echo "Device tree not found: $dtb" >&2; exit 1; }
for bootloader in idbloader.bin uboot.img trust.bin; do
  [[ -s "$repo_dir/loader/$bootloader" ]] || { echo "Missing loader/$bootloader" >&2; exit 1; }
done

mount_dir="$(mktemp -d "$repo_dir/.chainedbox-mount.XXXXXX")"
loop_device=""
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if mountpoint -q "$mount_dir"; then umount "$mount_dir" || status=1; fi
  if [[ -n "$loop_device" ]]; then losetup -d "$loop_device" || status=1; fi
  rmdir "$mount_dir" || status=1
  exit "$status"
}
trap cleanup EXIT INT TERM

loop_device="$(losetup --find --show --partscan "$image")"
udevadm settle || true
root_partition="${loop_device}p1"
[[ -b "$root_partition" ]] || { echo "Missing expected root partition: $root_partition" >&2; exit 1; }
mount "$root_partition" "$mount_dir"
[[ -s "$mount_dir/boot/armbianEnv.txt" ]] || { echo "Armbian /boot/armbianEnv.txt not found" >&2; exit 1; }
[[ -s "$mount_dir/boot/boot.scr" ]] || { echo "Armbian /boot/boot.scr not found" >&2; exit 1; }

set_boot_env() {
  local key="$1" value="$2" file="$mount_dir/boot/armbianEnv.txt"
  if grep -q "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}
# Keep the current upstream boot script and its dtb/${fdtfile} convention.
install -Dm644 "$dtb" "$mount_dir/boot/dtb/rockchip/$(basename "$dtb")"
set_boot_env verbosity 7
set_boot_env fdtfile "rockchip/$(basename "$dtb")"
set_boot_env extraargs "usbcore.autosuspend=-1"
set_boot_env usbstoragequirks "0x2537:0x1066:u,0x2537:0x1068:u"

install -Dm755 "$repo_dir/l1pro/pwm-fan.pl" "$mount_dir/usr/bin/pwm-fan.pl"
install -Dm644 "$repo_dir/l1pro/pwm-fan.service" "$mount_dir/etc/systemd/system/pwm-fan.service"
install -Dm755 "$repo_dir/l1pro/install-docker.sh" "$mount_dir/root/install-docker.sh"
install -Dm755 "$repo_dir/l1pro/install-omv.sh" "$mount_dir/root/install-omv.sh"
mkdir -p "$mount_dir/etc/systemd/system/multi-user.target.wants"
ln -sfn ../pwm-fan.service "$mount_dir/etc/systemd/system/multi-user.target.wants/pwm-fan.service"
rm -f "$mount_dir/etc/systemd/system/getty.target.wants/serial-getty@ttyS2.service"
printf '%s\n' "$board" > "$mount_dir/etc/hostname"
ln -sfn /usr/share/zoneinfo/Asia/Shanghai "$mount_dir/etc/localtime"

# Avoid chroot on x86 runners: no QEMU/binary format dependency for systemctl.
sync
umount "$mount_dir"
losetup -d "$loop_device"
loop_device=""

# These offsets/loader binaries are specific to the RK3328 Chainedbox hardware.
# Do not use losetup -D, which would detach unrelated loop devices.
dd if="$repo_dir/loader/idbloader.bin" of="$image" seek=64 bs=512 conv=notrunc status=none
dd if="$repo_dir/loader/uboot.img" of="$image" seek=16384 bs=512 conv=notrunc status=none
dd if="$repo_dir/loader/trust.bin" of="$image" seek=24576 bs=512 conv=notrunc status=none

name="$(basename "$image")"
name="${name//Rock64/Chainedbox}"
name="${name//L1pro/Chainedbox}"
name="${name//L1Pro/Chainedbox}"
if [[ "$name" == "$(basename "$image")" ]]; then
  name="Chainedbox_${name}"
fi
new_image="$image_dir/$name"
if [[ "$new_image" != "$image" ]]; then mv -- "$image" "$new_image"; fi
gzip -1 -- "$new_image"
(
  cd "$image_dir"
  sha256sum "$name.gz" > "$name.gz.sha256"
  sha256sum -c "$name.gz.sha256"
)
echo "Image ready: $new_image.gz"
