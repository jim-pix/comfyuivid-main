# Image de base légère
ARG BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04
FROM ${BASE_IMAGE}

# Variables d'environnement
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1

# Installation des dépendances système
RUN apt-get update && apt-get install -y \
    python3.12 python3.12-venv git wget libgl1 libglib2.0-0 \
    ffmpeg && ln -sf /usr/bin/python3.12 /usr/bin/python

# Installation de 'uv' pour un build ultra-rapide
RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -s /root/.local/bin/uv /usr/local/bin/uv \
    && uv venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# Installation de ComfyUI via comfy-cli
RUN uv pip install comfy-cli pip setuptools wheel \
    && /usr/bin/yes | comfy --workspace /comfyui install --nvidia

WORKDIR /comfyui

# Installation des dépendances RunPod
RUN uv pip install runpod requests websocket-client

# Copie de tes scripts locaux (doivent être dans ton repo GitHub)
ADD src/extra_model_paths.yaml ./
ADD src/start.sh handler.py ./
RUN chmod +x /start.sh

# Scripts utilitaires
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-node-install /usr/local/bin/comfy-manager-set-mode

CMD ["/start.sh"]