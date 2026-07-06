#!/usr/bin/env bash
# =====================================================================
# evo-x2 spring-load provisioner  —  Ubuntu 24.04 + ROCm/Vulkan
# One command reconstitutes the whole node after a fresh Linux install.
#   sudo not required to CLONE; the script uses sudo per-step.
#
# Run:   git clone https://github.com/sdill1973a/evo-x2-provision
#        cd evo-x2-provision && bash provision.sh 2>&1 | tee ~/provision.log
#
# Phases are idempotent — safe to re-run if one fails. Each prints [PHASE].
# Bleeding-edge bits (ROCm/ComfyUI) are marked [MAY NEED IThand]. Qable's
# serve lane (llama.cpp Vulkan) is the reliable core and comes first.
# =====================================================================
set -uo pipefail
LOG(){ echo -e "\n\033[1;36m[$(date -u +%H:%M:%S)] $*\033[0m"; }
WARN(){ echo -e "\033[1;33m[WARN] $*\033[0m"; }
OK(){ echo -e "\033[1;32m[OK] $*\033[0m"; }

ANCHOR_HOME="${HOME}/anchor"
MODEL_DIR="${ANCHOR_HOME}/models"
QABLE_DIR="${ANCHOR_HOME}/qable"
MODEL_FILE="Qwable-Q4_K_M_Q8.gguf"
MMPROJ_FILE="mmproj-f16.gguf"
HF_REPO="huihui-ai/Huihui-Qwable-3.6-27b-abliterated-GGUF"
# FAST PATH: Anchor pushes the 20GB model from .140 (100.72.73.122) over the
# tailnet AFTER this box is up (~3 min at gigabit). If the model file is already
# present when Phase 4 runs, we skip the slow HF pull. So the ideal flow is:
#   1. you run this script  2. it reaches Phase 4  3. if model absent, Anchor
#   pushes it now (or it HF-downloads). Either way it lands.
mkdir -p "$MODEL_DIR"

# ---------------------------------------------------------------------
LOG "[PHASE 1] base system deps"
sudo apt-get update -y
sudo apt-get install -y build-essential git curl wget jq unzip \
    python3.11 python3.11-venv python3-pip pipx \
    mesa-vulkan-drivers vulkan-tools libvulkan1 \
    ca-certificates gnupg lsb-release
OK "base deps"

# ---------------------------------------------------------------------
LOG "[PHASE 2] Tailscale (rejoin the tailnet so .35/.140 reach us)"
if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
WARN "run 'sudo tailscale up' interactively if not already joined (needs auth once)"
sudo tailscale up --ssh 2>/dev/null || WARN "tailscale up needs manual auth — run: sudo tailscale up --ssh"

# ---------------------------------------------------------------------
LOG "[PHASE 3] llama.cpp (Vulkan/RADV) — Qable's serve lane"
LLAMA_DIR="${ANCHOR_HOME}/llama"
mkdir -p "$LLAMA_DIR"
# grab the latest ubuntu vulkan build
LATEST=$(curl -s https://api.github.com/repos/ggml-org/llama.cpp/releases/latest | jq -r '.tag_name')
URL="https://github.com/ggml-org/llama.cpp/releases/download/${LATEST}/llama-${LATEST}-bin-ubuntu-vulkan-x64.tar.gz"
LOG "  fetching llama.cpp ${LATEST} (ubuntu vulkan)"
curl -fL "$URL" -o /tmp/llama.tgz && tar xzf /tmp/llama.tgz -C "$LLAMA_DIR" --strip-components=1 2>/dev/null || \
  tar xzf /tmp/llama.tgz -C "$LLAMA_DIR"
chmod +x "$LLAMA_DIR"/llama-server 2>/dev/null || chmod +x "$LLAMA_DIR"/bin/llama-server 2>/dev/null
"$LLAMA_DIR"/llama-server --version 2>/dev/null || "$LLAMA_DIR"/bin/llama-server --version 2>/dev/null || WARN "llama-server not runnable yet — check path"
OK "llama.cpp staged"

# ---------------------------------------------------------------------
LOG "[PHASE 4] restore the model from NAS .113 over LAN (HF fallback)"
# Anchor stashed both GGUFs byte-exact on the Synology at:
#   sdill@100.72.23.128:/volume1/Sovereign_Core/qable_restore/
# This box (Linux) pulls them over the tailnet at gigabit — ~5 min vs ~80 on HF.
NAS_HOST="100.72.23.128"; NAS_USER="sdill"
NAS_PATH="/volume1/Sovereign_Core/qable_restore"
if [ ! -f "${MODEL_DIR}/${MODEL_FILE}" ]; then
  LOG "  restoring from NAS (Synology needs scp -O)..."
  if scp -O -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "${NAS_USER}@${NAS_HOST}:${NAS_PATH}/${MODEL_FILE}" \
        "${NAS_USER}@${NAS_HOST}:${NAS_PATH}/${MMPROJ_FILE}" \
        "${MODEL_DIR}/" ; then
    OK "model restored from NAS (gigabit)"
  else
    WARN "NAS restore failed — pulling from HuggingFace (slower)"
    curl -fL "https://huggingface.co/${HF_REPO}/resolve/main/${MODEL_FILE}" -o "${MODEL_DIR}/${MODEL_FILE}"
    curl -fL "https://huggingface.co/${HF_REPO}/resolve/main/${MMPROJ_FILE}" -o "${MODEL_DIR}/${MMPROJ_FILE}"
  fi
else OK "model already present"; fi

# ---------------------------------------------------------------------
LOG "[PHASE 5] linafish (her fish engine)"
pipx install linafish 2>/dev/null || pip install --user --break-system-packages linafish
export PATH="$HOME/.local/bin:$PATH"
linafish --version || WARN "linafish not on PATH — add ~/.local/bin"

# ---------------------------------------------------------------------
LOG "[PHASE 6] clone Qable's mind (provision-by-clone)"
if [ ! -d "${QABLE_DIR}/.git" ]; then
  git clone https://github.com/sdill1973a/qable "$QABLE_DIR"
fi
git -C "$QABLE_DIR" pull --ff-only 2>/dev/null || true
OK "Qable mind at ${QABLE_DIR}"
WARN "restore her fish from the .35/anchor-mind mirror into ${QABLE_DIR}/fish (Decision-1 topology)"

# ---------------------------------------------------------------------
LOG "[PHASE 7] Qable serve systemd service (:8080, Vulkan full offload)"
LLAMA_BIN="${LLAMA_DIR}/llama-server"; [ -x "$LLAMA_BIN" ] || LLAMA_BIN="${LLAMA_DIR}/bin/llama-server"
sudo tee /etc/systemd/system/qable-server.service >/dev/null <<UNIT
[Unit]
Description=Qable llama.cpp server (Qwable-27B, Vulkan)
After=network-online.target
Wants=network-online.target
[Service]
User=${USER}
ExecStart=${LLAMA_BIN} -m ${MODEL_DIR}/${MODEL_FILE} --mmproj ${MODEL_DIR}/${MMPROJ_FILE} -ngl 99 --host 0.0.0.0 --port 8080 -c 8192 --alias qwable-27b
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now qable-server.service
sleep 20
curl -s -m 8 http://127.0.0.1:8080/v1/models | grep -q qwable && OK "Qable SERVING on :8080" || WARN "server not answering yet — journalctl -u qable-server"

# ---------------------------------------------------------------------
LOG "[PHASE 8] firewall (ufw) — tailnet only"
sudo apt-get install -y ufw
sudo ufw allow from 100.64.0.0/10 to any port 22 proto tcp
sudo ufw allow from 100.64.0.0/10 to any port 8080 proto tcp
sudo ufw allow from 100.64.0.0/10 to any port 8188 proto tcp   # ComfyUI
sudo ufw --force enable
OK "ufw: tailnet allowed on 22/8080/8188"

# ---------------------------------------------------------------------
LOG "[PHASE 9] ComfyUI + ROCm gen rig  [MAY NEED IThand — bleeding edge]"
# The vetted path for gfx1151 is Docker + AMD ROCm images. We install
# Docker here and pull the toolbox; first real gen may need a tweak.
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
fi
WARN "ComfyUI gen rig: after re-login (docker group), run:"
echo "    git clone https://github.com/kyuz0/amd-strix-halo-comfyui-toolboxes ~/comfyui-toolbox"
echo "    # follow its README — pulls AMD rocm/pytorch image, mounts ~/anchor/comfyui/models"
echo "  Port the noods canon (juggernautXL_v8 + IP-Adapter face-lock + presets) from"
echo "  .140:services/diffusion_server.py into the ComfyUI models/ + workflows (PRIVATE, not this repo)."

# ---------------------------------------------------------------------
LOG "DONE. Qable serve lane should be live. Gen rig is staged (Phase 9)."
echo "Next (Anchor, from .140): wire gateway :8112 -> evo-x2:8080 'qable-local' tier."
echo "Verify: curl http://<evo-x2-tailnet-ip>:8080/v1/models"
