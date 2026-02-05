FROM runpod/pytorch:2.1.0-py3.10-cuda11.8.0-devel

WORKDIR /workspace

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

# Installation minimale
RUN apt-get update && apt-get install -y --no-install-recommends \
    git wget ffmpeg libgl1 libglib2.0-0 && \
    rm -rf /var/lib/apt/lists/*

# Cloner ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /comfyui

WORKDIR /comfyui

# Installer requirements
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir runpod requests websocket-client

# Copier les fichiers depuis la racine et src/
COPY src/extra_model_paths.yaml ./
COPY src/start.sh ./
COPY handler.py ./
RUN chmod +x ./start.sh

# Script utilitaire si vous en avez besoin
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode 2>/dev/null || true
RUN chmod +x /usr/local/bin/comfy-manager-set-mode 2>/dev/null || true

CMD ["./start.sh"]