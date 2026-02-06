FROM runpod/worker-comfy:latest

WORKDIR /comfyui

# Installer juste RunPod SDK
RUN pip install --no-cache-dir runpod websocket-client requests

# Créer extra_model_paths.yaml
RUN printf 'comfyui:\n  base_path: /workspace/\n  checkpoints: models/checkpoints/\n  unet: models/unet/\n  vae: models/vae/\n  loras: models/loras/\n  clip: models/clip/\n  upscale_models: models/upscale_models/\n' > extra_model_paths.yaml

# Créer start.sh
RUN printf '#!/bin/bash\nset -e\necho "Checking volume..."\nif [ ! -d "/workspace/models" ]; then echo "ERROR: Volume not mounted"; exit 1; fi\nif [ -d "/workspace/custom_nodes" ]; then\n  echo "Linking custom nodes..."\n  rm -rf /comfyui/custom_nodes\n  ln -s /workspace/custom_nodes /comfyui/custom_nodes\n  echo "Installing custom node dependencies..."\n  for node_dir in /workspace/custom_nodes/*/; do\n    if [ -f "${node_dir}requirements.txt" ]; then\n      pip install -q -r "${node_dir}requirements.txt" || true\n    fi\n  done\nfi\necho "Starting ComfyUI..."\npython -u /comfyui/main.py --disable-auto-launch --disable-metadata &\nsleep 10\necho "Starting handler..."\npython -u /handler.py\n' > start.sh && chmod +x start.sh

# Créer handler.py
RUN printf 'import runpod\nimport requests\nimport json\nimport time\n\ndef handler(job):\n    job_input = job.get("input", {})\n    workflow = job_input.get("workflow")\n    \n    if not workflow:\n        return {"error": "No workflow provided"}\n    \n    try:\n        response = requests.post(\n            "http://localhost:8188/prompt",\n            json={"prompt": workflow}\n        )\n        \n        if response.status_code != 200:\n            return {"error": f"ComfyUI error: {response.text}"}\n        \n        result = response.json()\n        return {"status": "success", "prompt_id": result.get("prompt_id")}\n    except Exception as e:\n        return {"error": str(e)}\n\nif __name__ == "__main__":\n    print("Starting RunPod handler...")\n    runpod.serverless.start({"handler": handler})\n' > /handler.py

CMD ["./start.sh"]


