# Base-image pin (confirmed by Anchor, sourced) — for the autoinstall front-end

- **Distro:** Ubuntu 24.04 LTS (server). The gfx1151 ecosystem standard.
- **Serve lane (Qable / llama.cpp): VULKAN/RADV — NOT ROCm.**
  On gfx1151, Vulkan/RADV ~50-60 TPS on 26B; ROCm/HIP "performs poorly" +
  memory-permission-faults (llama.cpp #13565, ROCm #6186/#5853). Our 8.6 t/s
  was *Windows*, not Vulkan. So: `mesa-vulkan-drivers vulkan-tools libvulkan1`
  + the llama.cpp **ubuntu-vulkan** binary. ~6-7x speedup from the OS alone.
- **Eye lane (ComfyUI / PyTorch): ROCm 6.4+/7.x, containerized.**
  `HSA_OVERRIDE_GFX_VERSION=11.5.1`; prebuilt gfx1151 wheels via lemonade-sdk
  or TheRock; AMD `rocm/pytorch` Docker (ROCm 7.2 / torch 2.9.1). Docker only
  — gfx1151 ROCm is fault-prone bare-metal.
- **Model restore:** NOT in the installer. Anchor pushes from .140 / NAS .113
  post-boot; HF fallback.
- **Keys:** both `keys/anchor-dill.pub` + Olorina's in authorized_keys.
