FROM runpod/pytorch:2.1.0-py3.10-cuda11.8.0-devel

WORKDIR /app

# Installation rapide en une seule couche
RUN apt-get update && \
    apt-get install -y --no-install-recommends git wget ffmpeg libgl1 libglib2.0-0 && \
    rm -rf /var/lib/apt/lists/* && \
    git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /comfyui && \
    cd /comfyui && \
    pip install --no-cache-dir -r requirements.txt runpod websocket-client requests

WORKDIR /comfyui

# Créer start.sh inline
RUN printf '#!/bin/bash\nset -e\necho "Checking volume..."\nif [ ! -d "/workspace/models" ]; then echo "ERROR: Volume not mounted"; exit 1; fi\nif [ -d "/workspace/custom_nodes" ]; then rm -rf /comfyui/custom_nodes; ln -s /workspace/custom_nodes /comfyui/custom_nodes; fi\necho "Starting ComfyUI..."\npython -u /comfyui/main.py --disable-auto-launch --disable-metadata &\nsleep 10\necho "Starting handler..."\npython -u /handler.py\n' > start.sh && chmod +x start.sh

# Créer handler.py minimal
RUN printf 'import runpod\nimport subprocess\nimport time\n\ndef handler(job):\n    print("Job received:", job)\n    return {"status": "success", "message": "Handler running"}\n\nif __name__ == "__main__":\n    print("Starting RunPod handler...")\n    runpod.serverless.start({"handler": handler})\n' > /handler.py

# Créer extra_model_paths.yaml
RUN printf 'comfyui:\n  base_path: /workspace/\n  checkpoints: models/checkpoints/\n  unet: models/unet/\n  vae: models/vae/\n  loras: models/loras/\n  clip: models/clip/\n  upscale_models: models/upscale_models/\n' > extra_model_paths.yaml

CMD ["./start.sh"]