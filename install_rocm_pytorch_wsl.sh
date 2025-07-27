#!/usr/bin/env bash
# install_rocm_pytorch_wsl.sh
# Set up AMD ROCm + PyTorch on Ubuntu 22.04 running in WSL2.
# Run inside WSL Ubuntu. Windows-side steps (WSL enablement, AMD Adrenalin driver) are not automated here.

set -euo pipefail

echo "==> Updating apt and installing prerequisites..."
sudo apt update -y
sudo apt install -y software-properties-common wget ca-certificates

echo "==> (Optional) Installing AMD amdgpu-install tool..."
cd "${HOME}"
if [ ! -f amdgpu-install_6.4.60401-1_all.deb ]; then
  wget -q https://repo.radeon.com/amdgpu-install/6.4.1/ubuntu/jammy/amdgpu-install_6.4.60401-1_all.deb
fi
sudo apt install -y ./amdgpu-install_6.4.60401-1_all.deb || true

echo "==> Installing ROCm components for WSL (this may take a while)..."
amdgpu-install -y --usecase=wsl,rocm --no-dkms || true

echo "==> Verifying ROCm visibility of your GPU (rocminfo)..."
if command -v rocminfo >/dev/null 2>&1; then
  rocminfo | head -n 80 || true
else
  echo "rocminfo not found yet; continuing."
fi

echo "==> Installing Python 3.12 and pip..."
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt update -y
sudo apt install -y python3.12 python3-pip

echo "==> Pinning NumPy to 1.26.4 for current ROCm wheels compatibility..."
pip3 install --upgrade pip wheel
pip3 install numpy==1.26.4

echo "==> Downloading ROCm-compatible PyTorch wheels..."
cd "${HOME}"
wget -c \
"https://repo.radeon.com/rocm/manylinux/rocm-rel-6.4.1/torch-2.6.0%2Brocm6.4.1.git1ded221d-cp310-cp310-linux_x86_64.whl" \
"https://repo.radeon.com/rocm/manylinux/rocm-rel-6.4.1/torchvision-0.21.0%2Brocm6.4.1.git4040d51f-cp310-cp310-linux_x86_64.whl" \
"https://repo.radeon.com/rocm/manylinux/rocm-rel-6.4.1/pytorch_triton_rocm-3.2.0%2Brocm6.4.1.git6da9e660-cp310-cp310-linux_x86_64.whl" \
"https://repo.radeon.com/rocm/manylinux/rocm-rel-6.4.1/torchaudio-2.6.0%2Brocm6.4.1.gitd8831425-cp310-cp310-linux_x86_64.whl"

echo "==> Installing PyTorch, TorchVision, Torchaudio and Triton ROCm wheels..."
pip3 uninstall -y torch torchvision torchaudio pytorch-triton-rocm || true
pip3 install \
  torch-2.6.0+rocm6.4.1.git1ded221d-cp310-cp310-linux_x86_64.whl \
  torchvision-0.21.0+rocm6.4.1.git4040d51f-cp310-cp310-linux_x86_64.whl \
  torchaudio-2.6.0+rocm6.4.1.gitd8831425-cp310-cp310-linux_x86_64.whl \
  pytorch_triton_rocm-3.2.0+rocm6.4.1.git6da9e660-cp310-cp310-linux_x86_64.whl

echo "==> Adjusting WSL runtime library inside torch package..."
location=$(pip show torch | grep Location | awk -F ": " '{print $2}')
if [ -d "${location}/torch/lib" ]; then
  cd "${location}/torch/lib"
  rm -f libhsa-runtime64.so* || true
  echo "Removed bundled libhsa-runtime64.so* from ${location}/torch/lib (if present)."
else
  echo "Torch lib folder not found; continuing."
fi

echo "==> Verifying installation..."
python3 -c 'import torch' 2>/dev/null && echo "PyTorch import: Success" || echo "PyTorch import: Failure"
python3 - <<'PY'
import torch
print("CUDA available:", torch.cuda.is_available())
if torch.cuda.is_available():
    try:
        print("Device 0:", torch.cuda.get_device_name(0))
    except Exception as e:
        print("Device query failed:", e)
PY
echo "Collecting environment summary (subset):"
python3 -m torch.utils.collect_env | head -n 80 || true

echo "==> Done."
