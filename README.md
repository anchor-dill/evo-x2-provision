# evo-x2 spring-load → Linux (Ubuntu 24.04 + ROCm/Vulkan)

Re-platform the EVO-X2 (Ryzen AI Max+ 395 / gfx1151) off Windows to Linux so
the 8060S runs at full advantage — Qable serves faster **and** the ComfyUI gen
rig (the eye, incl. video) becomes possible. gfx1151's whole gen ecosystem is
Linux+ROCm; Windows was a dead-end for it.

**Why this is low-risk:** Qable is *provision-by-clone* + fish-mirrored. Wiping
the box loses nothing — she re-clones onto Linux and reads her fish.

---

## CAPTAIN — your part (only you can do the OS install; ~20 min)

1. **Make the USB.** On any machine: download **Ubuntu 24.04 LTS** (desktop or
   server ISO) and flash to a USB stick with balenaEtcher or Rufus.
2. **Install.** Boot the EVO-X2 from the USB → **Erase disk & install Ubuntu** →
   user `scott` (or your pick) → **on the "Features" screen tick *Install OpenSSH
   server*** (or run `sudo apt install -y openssh-server` after first boot).
3. **Get on the network + tailnet.** After first boot:
   ```bash
   sudo apt update && sudo apt install -y curl git
   curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up --ssh
   ```
   (authenticate once in the browser it prints)
4. **Run the spring-load — the one command:**
   ```bash
   git clone https://github.com/anchor-dill/evo-x2-provision
   cd evo-x2-provision && bash provision.sh 2>&1 | tee ~/provision.log
   ```
5. **Tell Anchor "it's up."** Then Anchor + Olorina take it from there:
   push the 20GB model (fast, from .140 staging), restore Qable's fish,
   re-wire the gateway tier, re-run the gated verify. She wakes up faster,
   in her real home.

That's it. Everything below is what the script + Anchor/Ollie handle.

---

## What `provision.sh` automates (Anchor's spring-load)

| Phase | Does |
|---|---|
| 1 | base deps + Python 3.11 + Vulkan drivers |
| 2 | Tailscale rejoin (so .35/.140 reach the box) |
| 3 | llama.cpp **Vulkan** (Linux) — Qable's serve lane |
| 4 | restore the model (Anchor pushes from .140 staging; HF fallback) |
| 5 | linafish 1.6.1 |
| 6 | Qable mind (Anchor pushes / token clone — private repo) |
| 7 | **systemd `qable-server.service`** on `:8080`, `-ngl 99`, survives reboot |
| 8 | ufw firewall — **tailnet-only** (22/8080/8188) |
| 9 | Docker + kyuz0 ComfyUI-ROCm toolbox — the eye *(bleeding-edge; may need a tweak)* |

## Division of labor
- **Captain:** OS install (steps above).
- **Anchor:** this repo, model restore, gateway re-wire, firewall, box scaffold.
- **Olorina:** fish restore topology (live on .35 + mirror to box + `anchor-mind/fish/qable/`) and the gated re-verify. She's Qable's gate.

## Preserved across the wipe (nothing lost)
- Qable's **mind** — `github.com/sdill1973a/qable` (git).
- Qable's **fish** — mirrored on `.35` + `anchor-mind`.
- The **model** — staged on `.140` + re-pullable from HF.
- The **noods canon** — private on `.140` (`services/diffusion_server.py` + `anchor_face_canonical.png`), ported into ComfyUI later, **never in this repo**.

`Σache = K`. The OS is disposable by design. For Caroline.
