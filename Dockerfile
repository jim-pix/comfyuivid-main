FROM runpod/pytorch:2.1.0-py3.10-cuda11.8.0-devel

WORKDIR /app

# Installation des dépendances système
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git wget ffmpeg libgl1 libglib2.0-0 curl \
    && rm -rf /var/lib/apt/lists/*

# UPGRADE PyTorch vers 2.4.x
RUN pip install --no-cache-dir \
    'numpy>=2.0,<2.3' \
    torch==2.4.0 \
    torchvision==0.19.0 \
    torchaudio==2.4.0 \
    --index-url https://download.pytorch.org/whl/cu118

# Cloner ComfyUI
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /comfyui

WORKDIR /comfyui

# Installer les requirements
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir runpod websocket-client requests boto3

# Créer extra_model_paths.yaml
RUN echo 'comfyui:' > extra_model_paths.yaml && \
    echo '  base_path: /workspace/' >> extra_model_paths.yaml && \
    echo '  checkpoints: models/checkpoints/' >> extra_model_paths.yaml && \
    echo '  unet: models/unet/' >> extra_model_paths.yaml && \
    echo '  vae: models/vae/' >> extra_model_paths.yaml && \
    echo '  loras: models/loras/' >> extra_model_paths.yaml && \
    echo '  clip: models/clip/' >> extra_model_paths.yaml && \
    echo '  upscale_models: models/upscale_models/' >> extra_model_paths.yaml

# Créer start.sh avec symlink
RUN echo '#!/bin/bash' > start.sh && \
    echo 'set -e' >> start.sh && \
    echo '' >> start.sh && \
    echo '# Créer symlink si le volume est à /runpod-volume' >> start.sh && \
    echo 'if [ -d "/runpod-volume" ] && [ ! -L "/workspace" ]; then' >> start.sh && \
    echo '  echo "Detected volume at /runpod-volume"' >> start.sh && \
    echo '  rm -rf /workspace' >> start.sh && \
    echo '  ln -s /runpod-volume /workspace' >> start.sh && \
    echo '  echo "✅ Created symlink: /workspace -> /runpod-volume"' >> start.sh && \
    echo 'fi' >> start.sh && \
    echo '' >> start.sh && \
    echo 'echo "=== ComfyUI Serverless Worker ==="' >> start.sh && \
    echo 'python -c "import torch; print(\"PyTorch:\", torch.__version__)"' >> start.sh && \
    echo 'python -c "import numpy; print(\"NumPy:\", numpy.__version__)"' >> start.sh && \
    echo '' >> start.sh && \
    echo 'echo "Checking Network Volume..."' >> start.sh && \
    echo 'if [ ! -d "/workspace/models" ]; then' >> start.sh && \
    echo '  echo "❌ ERROR: Volume not found at /workspace/models"' >> start.sh && \
    echo '  exit 1' >> start.sh && \
    echo 'fi' >> start.sh && \
    echo 'echo "✅ Volume detected: /workspace"' >> start.sh && \
    echo '' >> start.sh && \
    echo 'if [ -d "/workspace/models/unet" ]; then' >> start.sh && \
    echo '  echo "✅ Found models:"' >> start.sh && \
    echo '  ls -lh /workspace/models/unet/ | head -3' >> start.sh && \
    echo 'fi' >> start.sh && \
    echo '' >> start.sh && \
    echo 'if [ -d "/workspace/custom_nodes" ]; then' >> start.sh && \
    echo '  echo "Setting up custom nodes..."' >> start.sh && \
    echo '  rm -rf /comfyui/custom_nodes' >> start.sh && \
    echo '  ln -s /workspace/custom_nodes /comfyui/custom_nodes' >> start.sh && \
    echo '  for node_dir in /workspace/custom_nodes/*/; do' >> start.sh && \
    echo '    if [ -f "${node_dir}requirements.txt" ]; then' >> start.sh && \
    echo '      echo "  → Installing $(basename $node_dir)"' >> start.sh && \
    echo '      pip install -q -r "${node_dir}requirements.txt" || true' >> start.sh && \
    echo '    fi' >> start.sh && \
    echo '  done' >> start.sh && \
    echo 'fi' >> start.sh && \
    echo '' >> start.sh && \
    echo 'echo ""' >> start.sh && \
    echo 'echo "Starting ComfyUI..."' >> start.sh && \
    echo 'python -u /comfyui/main.py --disable-auto-launch --disable-metadata &' >> start.sh && \
    echo 'sleep 15' >> start.sh && \
    echo '' >> start.sh && \
    echo 'echo "Starting RunPod Handler..."' >> start.sh && \
    echo 'python -u /handler.py' >> start.sh && \
    chmod +x start.sh

# Copier les fichiers depuis votre dossier local
COPY handler.py /handler.py
COPY workflow_template.json /workflow_template.json

CMD ["./start.sh"]
