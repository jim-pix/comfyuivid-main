FROM runpod/pytorch:2.1.0-py3.10-cuda11.8.0-devel

WORKDIR /app

# Installation des dépendances système
RUN apt-get update && \
    apt-get install -y --no-install-recommends git wget ffmpeg libgl1 libglib2.0-0 && \
    rm -rf /var/lib/apt/lists/*

# Cloner ComfyUI
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /comfyui

WORKDIR /comfyui

# CRITIQUE : Downgrade NumPy AVANT d'installer les requirements
RUN pip install --no-cache-dir 'numpy<2' && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir runpod websocket-client requests

# Créer extra_model_paths.yaml
RUN printf 'comfyui:\n  base_path: /workspace/\n  checkpoints: models/checkpoints/\n  unet: models/unet/\n  vae: models/vae/\n  loras: models/loras/\n  clip: models/clip/\n  upscale_models: models/upscale_models/\n' > extra_model_paths.yaml

# Créer start.sh
RUN printf '#!/bin/bash\nset -e\necho "=== ComfyUI Serverless Worker ==="\necho "Checking Network Volume..."\nif [ ! -d "/workspace/models" ]; then\n  echo "ERROR: Network Volume not mounted at /workspace"\n  exit 1\nfi\necho "Volume detected: /workspace"\nif [ -d "/workspace/custom_nodes" ]; then\n  echo "Setting up custom nodes..."\n  rm -rf /comfyui/custom_nodes\n  ln -s /workspace/custom_nodes /comfyui/custom_nodes\n  echo "Installing custom node dependencies..."\n  for node_dir in /workspace/custom_nodes/*/; do\n    if [ -f "${node_dir}requirements.txt" ]; then\n      echo "  Installing for $(basename $node_dir)"\n      pip install -q -r "${node_dir}requirements.txt" || true\n    fi\n  done\nfi\necho "Starting ComfyUI..."\npython -u /comfyui/main.py --disable-auto-launch --disable-metadata &\nsleep 10\necho "Starting RunPod Handler..."\npython -u /handler.py\n' > start.sh && chmod +x start.sh

# Créer handler.py
RUN printf 'import runpod\nimport requests\nimport json\nimport time\n\ndef handler(job):\n    job_input = job.get("input", {})\n    workflow = job_input.get("workflow")\n    \n    if not workflow:\n        return {"error": "No workflow provided"}\n    \n    try:\n        response = requests.post(\n            "http://localhost:8188/prompt",\n            json={"prompt": workflow}\n        )\n        \n        if response.status_code != 200:\n            return {"error": f"ComfyUI error: {response.text}"}\n        \n        result = response.json()\n        return {"status": "success", "prompt_id": result.get("prompt_id")}\n    except Exception as e:\n        return {"error": str(e)}\n\nif __name__ == "__main__":\n    print("Starting RunPod handler...")\n    runpod.serverless.start({"handler": handler})\n' > /handler.py

CMD ["./start.sh"]