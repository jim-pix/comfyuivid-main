# Image de base légère
ARG BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04
FROM ${BASE_IMAGE}

# Variables d'environnement
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1

# Installation des dépendances système
RUN echo "========== STEP 1: Installing system dependencies ==========" && \
    apt-get update && apt-get install -y --no-install-recommends \
    python3.12 python3.12-venv git wget libgl1 libglib2.0-0 ffmpeg && \
    ln -sf /usr/bin/python3.12 /usr/bin/python && \
    rm -rf /var/lib/apt/lists/* && \
    echo "========== System dependencies installed =========="

# Installation de 'uv' pour un build ultra-rapide
RUN echo "========== STEP 2: Installing uv ==========" && \
    wget -qO- https://astral.sh/uv/install.sh | sh && \
    ln -s /root/.local/bin/uv /usr/local/bin/uv && \
    uv venv /opt/venv && \
    echo "========== uv installed =========="

ENV PATH="/opt/venv/bin:${PATH}"

# Installation de ComfyUI via comfy-cli
RUN echo "========== STEP 3: Installing ComfyUI (this may take a while) ==========" && \
    uv pip install comfy-cli pip setuptools wheel && \
    echo "========== comfy-cli installed, now installing ComfyUI ==========" && \
    comfy --skip-prompt install --workspace /comfyui --nvidia && \
    echo "========== ComfyUI installed =========="

WORKDIR /comfyui

# Installation des dépendances RunPod
RUN echo "========== STEP 4: Installing RunPod dependencies ==========" && \
    uv pip install runpod requests websocket-client && \
    echo "========== RunPod dependencies installed =========="

# Copie de tes scripts locaux
RUN echo "========== STEP 5: Copying configuration files =========="
ADD src/extra_model_paths.yaml ./
ADD src/start.sh src/handler.py ./
RUN chmod +x ./start.sh && \
    echo "========== Configuration files copied =========="

# Scripts utilitaires
RUN echo "========== STEP 6: Copying utility scripts =========="
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-node-install /usr/local/bin/comfy-manager-set-mode && \
    echo "========== BUILD COMPLETE =========="

CMD ["./start.sh"]