# remote_install.ps1 — get Ubuntu 24.04 onto the EVO-X2 REMOTELY, no physical media (s238).
# Run as Admin on the (Windows) box over SSH. UEFI + Secure Boot OFF (verified) makes this clean.
# ⚠️ IRREVERSIBLE at STEP 5 (the reboot). Everything before is non-destructive + reversible.
# Fire ONLY after: [A] anchor-dill key in autoinstall  [B] TAILSCALE_AUTHKEY set  [C] model stashed to NAS
#                  [D] this script dry-validated (STEP 4 checks pass)
$ErrorActionPreference = "Stop"
$ISO_URL = "https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso"
$WORK    = "C:\evo-provision"

# STEP 1 — fetch the ISO (non-destructive; ~2.6GB, 808GB free)
New-Item -ItemType Directory -Force $WORK | Out-Null
if (-not (Test-Path "$WORK\ubuntu.iso")) { curl.exe -L -C - -o "$WORK\ubuntu.iso" $ISO_URL }

# STEP 2 — build the nocloud seed (autoinstall user-data + meta-data) on a FAT partition GRUB can read.
#   - Write autoinstall-user-data (from evo-x2-provision repo) as \user-data, empty \meta-data, label 'cidata'.
#   - Ubuntu's subiquity reads ds=nocloud from a 'cidata'-labelled vol -> fully unattended.
# (staged into the ESP or a new small FAT partition; both readable pre-boot)

# STEP 3 — stage GRUB to loopback-boot the ISO with autoinstall (Secure Boot OFF => unsigned grub OK):
#   grub.cfg:
#     loopback loop /ubuntu.iso
#     linux  (loop)/casper/vmlinuz autoinstall "ds=nocloud;s=/cidata/" ---
#     initrd (loop)/casper/initrd
#   Drop grubx64.efi + grub.cfg + ubuntu.iso onto the ESP (mountvol S: /s).

# STEP 4 — VALIDATE before firing (all must pass):
#   - Confirm-SecureBootUEFI  -> False (unsigned grub will boot)
#   - Test-Path the staged grubx64.efi, grub.cfg, ubuntu.iso, \cidata\user-data
#   - `bcdedit /enum firmware` shows the new "Ubuntu Installer" UEFI entry
#   - user-data has NO 'REPLACE_WITH' placeholders left (anchor key + authkey filled)
#   - model confirmed on NAS .113

# STEP 5 — ⚠️ FIRE (irreversible): set ONE-TIME next boot to the installer, then reboot.
#   $u = (bcdedit /enum firmware | Select-String -Context 1 "Ubuntu Installer")  # get its {guid}
#   bcdedit /set "{fwbootmgr}" bootsequence "{that-guid}"   # ONE-TIME: falls back to Windows if it doesn't take
#   Restart-Computer -Force
#   -> box installs unattended (~15-20m), reboots into Ubuntu with both keys + Tailscale,
#      auto-clones evo-x2-provision; then run provision.sh (Anchor) + fish restore + gated re-verify (Olorina).
#
# RECOVERY: if it never comes back in ~30m, the one-time entry means a power-cycle *should* land on Windows.
# Worst case = the exact USB install we're avoiding. That's the whole risk, bounded.
