# Image de base avec PyTorch déjà installé
FROM runpod/pytorch:2.1.0-py3.10-cuda11.8.0-devel

WORKDIR /workspace

# Variables d'environnement
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

# Installation minimale des dépendances système
RUN apt-get update && apt-get install -y --no-install-recommends \
    git wget ffmpeg libgl1 libglib2.0-0 && \
    rm -rf /var/lib/apt/lists/*

# Cloner ComfyUI directement (plus rapide que comfy-cli)
RUN echo "Cloning ComfyUI..." && \
    git clone https://github.com/comfyanonymous/ComfyUI.git /comfyui

WORKDIR /comfyui

# Installer les requirements de ComfyUI
RUN echo "Installing ComfyUI requirements..." && \
    pip install --no-cache-dir -r requirements.txt

# Installer RunPod SDK
RUN echo "Installing RunPod..." && \
    pip install --no-cache-dir runpod requests websocket-client

# Copier vos fichiers de configuration
COPY src/extra_model_paths.yaml ./
COPY src/start.sh src/handler.py ./
RUN chmod +x ./start.sh

# Scripts utilitaires (si vous en avez besoin)
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode || true

CMD ["./start.sh"]