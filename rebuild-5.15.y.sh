#!/usr/bin/env bash
# Chainedbox RK3328 image post-processor; historic filename for compatibility.
# Usage: sudo bash rebuild-5.15.y.sh [1296mhz|1392mhz|1512mhz] [l1pro|chainedbox] [legacy|ophub]
set -Eeuo pipefail

cpu_frequency="${1:-1296mhz}"
board="${2:-l1pro}"
dtb_source="${3:-legacy}"

case "$cpu_frequency" in 1296mhz|1392mhz|1512mhz) ;; *) echo "Invalid CPU frequency: $cpu_frequency" >&2; exit 2 ;; esac
case "$board" in l1pro|chainedbox) ;; *) echo "Invalid board: $board" >&2; exit 2 ;; esac
case "$dtb_source" in legacy|ophub) ;; *) echo "Invalid DTB source: $dtb_source (expected legacy or ophub)" >&2; exit 2 ;; esac
if (( EUID != 0 )); then echo "Run this script as root (sudo)." >&2; exit 2; fi
command -v dtc >/dev/null || { echo "Install device-tree-compiler (dtc) first." >&2; exit 1; }

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
image_dir="$repo_dir/build/output/images"
dtb="$repo_dir/dtbs/$dtb_source/rk3328-l1pro-${cpu_frequency}.dtb"

shopt -s nullglob
images=( "$image_dir"/*.img )
(( ${#images[@]} == 1 )) || { echo "Expected exactly one uncompressed .img in $image_dir" >&2; exit 1; }
image="${images[0]}"
[[ -s "$dtb" ]] || { echo "Device tree not found: $dtb" >&2; exit 1; }
for loader_file in idbloader.bin uboot.img trust.bin; do
  [[ -s "$repo_dir/loader/$loader_file" ]] || { echo "Missing loader/$loader_file" >&2; exit 1; }
done

# Strictly validate and export the selected vendor DTB and its decompiled DTS.
# The DTS is for review only; the unmodified vendor DTB is used for boot.
dtb_export="Chainedbox_${board}_${dtb_source}_${cpu_frequency}.dtb"
install -Dm644 "$dtb" "$image_dir/$dtb_export"
dtc -I dtb -O dts -o "$image_dir/${dtb_export%.dtb}.dts" "$dtb"
echo "DTB: $dtb_source / $cpu_frequency"
sha256sum "$dtb"

# Fixed RK3328 loader regions occupy sectors 64 and 16384..32767.
# Refuse images whose first filesystem partition would overlap the old loaders.
partition_table="$(sfdisk -d "$image")"
if grep -q '^label: gpt' <<< "$partition_table"; then
  echo "Refusing GPT image: legacy RK3328 loader layout has not been verified for GPT." >&2
  exit 1
fi
first_sector="$(sed -nE 's/.*start=[[:space:]]*([0-9]+).*/\1/p' <<< "$partition_table" | sort -n | head -1)"
[[ "$first_sector" =~ ^[0-9]+$ ]] && (( first_sector >= 32768 )) || {
  echo "First partition must start at or after sector 32768 (16 MiB), found: ${first_sector:-unknown}" >&2
  exit 1
}

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
[[ -s "$mount_dir/boot/armbianEnv.txt" ]] || { echo "Missing /boot/armbianEnv.txt" >&2; exit 1; }
[[ -s "$mount_dir/boot/boot.scr" ]] || { echo "Missing /boot/boot.scr" >&2; exit 1; }

set_boot_env() {
  local key="$1" value="$2" file="$mount_dir/boot/armbianEnv.txt"
  if grep -q "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

# Armbian's upstream Rockchip boot.scr expects fdtfile relative to /boot/dtb/.
install -Dm644 "$dtb" "$mount_dir/boot/dtb/rockchip/$(basename "$dtb")"
set_boot_env verbosity 7
set_boot_env fdtfile "rockchip/$(basename "$dtb")"
set_boot_env extraargs "usbcore.autosuspend=-1"
set_boot_env usbstoragequirks "0x2537:0x1066:u,0x2537:0x1068:u"

# Never copy ophub's /dev/mmcblk0p2 boot environment: this image uses p1.
install -Dm644 /dev/stdin "$mount_dir/etc/chainedbox-dtb-source" <<EOF
source=$dtb_source
frequency=$cpu_frequency
board=$board
filename=$(basename "$dtb")
EOF

install -Dm755 "$repo_dir/l1pro/install-docker.sh" "$mount_dir/root/install-docker.sh"
install -Dm755 "$repo_dir/l1pro/install-omv.sh" "$mount_dir/root/install-omv.sh"

if [[ "$dtb_source" == legacy ]]; then
  # Historical legacy PWM sysfs service: retained only for backward compatibility.
  install -Dm755 "$repo_dir/l1pro/pwm-fan.pl" "$mount_dir/usr/bin/pwm-fan.pl"
  install -Dm644 "$repo_dir/l1pro/pwm-fan.service" "$mount_dir/etc/systemd/system/pwm-fan.service"
  mkdir -p "$mount_dir/etc/systemd/system/multi-user.target.wants"
  ln -sfn ../pwm-fan.service "$mount_dir/etc/systemd/system/multi-user.target.wants/pwm-fan.service"
else
  # ophub DTB provides pwm-fan and thermal cooling maps. Do not compete for the PWM.
  rm -f "$mount_dir/etc/systemd/system/multi-user.target.wants/pwm-fan.service"
  rm -f "$mount_dir/etc/systemd/system/pwm-fan.service"
fi

rm -f "$mount_dir/etc/systemd/system/getty.target.wants/serial-getty@ttyS2.service"
printf '%s\n' "$board" > "$mount_dir/etc/hostname"
ln -sfn /usr/share/zoneinfo/Asia/Shanghai "$mount_dir/etc/localtime"

sync
umount "$mount_dir"
losetup -d "$loop_device"
loop_device=""

# Legacy Chainedbox loader offsets; do not replace until validated on real hardware.
dd if="$repo_dir/loader/idbloader.bin" of="$image" seek=64 bs=512 conv=notrunc status=none
dd if="$repo_dir/loader/uboot.img" of="$image" seek=16384 bs=512 conv=notrunc status=none
dd if="$repo_dir/loader/trust.bin" of="$image" seek=24576 bs=512 conv=notrunc status=none

name="$(basename "$image")"
name="${name//Rock64/Chainedbox}"
name="${name//L1pro/Chainedbox}"
name="${name//L1Pro/Chainedbox}"
if [[ "$name" == "$(basename "$image")" ]]; then name="Chainedbox_$name"; fi
name="${name%.img}_${dtb_source}_${cpu_frequency}.img"
new_image="$image_dir/$name"
if [[ "$new_image" != "$image" ]]; then mv -- "$image" "$new_image"; fi
gzip -1 -- "$new_image"
(
  cd "$image_dir"
  sha256sum "$name.gz" > "$name.gz.sha256"
  sha256sum -c "$name.gz.sha256"
)
echo "Image ready: $new_image.gz (DTB source: $dtb_source)"
