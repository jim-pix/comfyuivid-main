FROM runpod/pytorch:2.1.0-py3.10-cuda11.8.0-devel

WORKDIR /app

# Installation des dépendances système + outils de debug
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git wget ffmpeg libgl1 libglib2.0-0 \
    htop curl \
    && rm -rf /var/lib/apt/lists/*

# UPGRADE PyTorch vers 2.2.x (compatible avec numpy<2 ET torch.uint64)
RUN pip install --no-cache-dir \
    torch==2.2.2 \
    torchvision==0.17.2 \
    torchaudio==2.2.2 \
    --index-url https://download.pytorch.org/whl/cu118

# Cloner ComfyUI
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /comfyui

WORKDIR /comfyui

# Modifier requirements.txt pour forcer numpy<2
RUN sed -i 's/numpy.*/numpy<2/' requirements.txt || echo "numpy<2" >> requirements.txt

# Installer les requirements modifiés + RunPod + bibliothèques utiles
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir \
    runpod \
    websocket-client \
    requests \
    boto3 \
    && pip check || echo "Warning: dependency conflicts detected"

# Créer extra_model_paths.yaml
RUN printf 'comfyui:\n  base_path: /workspace/\n  checkpoints: models/checkpoints/\n  unet: models/unet/\n  vae: models/vae/\n  loras: models/loras/\n  clip: models/clip/\n  upscale_models: models/upscale_models/\n  diffusers: models/diffusers/\n' > extra_model_paths.yaml

# Créer start.sh amélioré avec plus de checks
RUN printf '#!/bin/bash\nset -e\n\necho "=== ComfyUI Serverless Worker ==="\necho "PyTorch version: $(python -c \"import torch; print(torch.__version__)\")"\necho "NumPy version: $(python -c \"import numpy; print(numpy.__version__)\")"\n\n# Vérifier le Network Volume\necho "Checking Network Volume..."\nif [ ! -d "/workspace/models" ]; then\n  echo "ERROR: Network Volume not mounted at /workspace"\n  exit 1\nfi\necho "✅ Volume detected: /workspace"\n\n# Vérifier que les modèles existent\necho "Checking for models..."\nif [ -d "/workspace/models/unet" ]; then\n  echo "✅ Found unet models:"\n  ls -lh /workspace/models/unet/ | head -5\nelse\n  echo "⚠️  No unet models found"\nfi\n\n# Setup custom nodes\nif [ -d "/workspace/custom_nodes" ]; then\n  echo "Setting up custom nodes..."\n  rm -rf /comfyui/custom_nodes\n  ln -s /workspace/custom_nodes /comfyui/custom_nodes\n  \n  echo "Installing custom node dependencies..."\n  for node_dir in /workspace/custom_nodes/*/; do\n    if [ -f "${node_dir}requirements.txt" ]; then\n      node_name=$(basename "$node_dir")\n      echo "  → Installing for $node_name"\n      pip install -q -r "${node_dir}requirements.txt" || echo "    ⚠️  Failed for $node_name"\n    fi\n  done\n  echo "✅ Custom nodes setup complete"\nelse\n  echo "⚠️  No custom_nodes directory found"\nfi\n\n# Démarrer ComfyUI\necho ""\necho "========================================"\necho "Starting ComfyUI..."\necho "========================================"\npython -u /comfyui/main.py --disable-auto-launch --disable-metadata &\n\n# Attendre que ComfyUI soit prêt\nsleep 15\n\n# Vérifier que ComfyUI répond\necho "Checking if ComfyUI is ready..."\nfor i in {1..10}; do\n  if curl -s http://localhost:8188 > /dev/null 2>&1; then\n    echo "✅ ComfyUI is responding"\n    break\n  fi\n  echo "Waiting for ComfyUI... ($i/10)"\n  sleep 2\ndone\n\necho ""\necho "========================================"\necho "Starting RunPod Handler..."\necho "========================================"\npython -u /handler.py\n' > start.sh && chmod +x start.sh

# Handler amélioré avec WebSocket pour suivre la progression
RUN printf 'import runpod\nimport requests\nimport json\nimport time\n\nCOMFYUI_URL = "http://localhost:8188"\n\ndef get_history(prompt_id):\n    """Récupérer l historique d une génération"""\n    try:\n        response = requests.get(f"{COMFYUI_URL}/history/{prompt_id}")\n        return response.json()\n    except:\n        return {}\n\ndef wait_for_completion(prompt_id, timeout=600):\n    """Attendre que la génération soit terminée"""\n    start_time = time.time()\n    \n    while time.time() - start_time < timeout:\n        history = get_history(prompt_id)\n        \n        if prompt_id in history:\n            prompt_history = history[prompt_id]\n            \n            # Vérifier si terminé\n            if "outputs" in prompt_history:\n                print(f"✅ Generation completed for {prompt_id}")\n                return prompt_history["outputs"]\n        \n        print(f"⏳ Waiting for generation... ({int(time.time() - start_time)}s)")\n        time.sleep(2)\n    \n    raise TimeoutError(f"Generation timed out after {timeout}s")\n\ndef handler(job):\n    """Handler RunPod pour traiter les jobs"""\n    print(f"📥 Job received: {job.get(\\"id\\")}")\n    \n    job_input = job.get("input", {})\n    workflow = job_input.get("workflow")\n    \n    if not workflow:\n        return {"error": "No workflow provided"}\n    \n    try:\n        # Envoyer le workflow à ComfyUI\n        print("📤 Sending workflow to ComfyUI...")\n        response = requests.post(\n            f"{COMFYUI_URL}/prompt",\n            json={"prompt": workflow},\n            timeout=30\n        )\n        \n        if response.status_code != 200:\n            return {"error": f"ComfyUI error: {response.text}"}\n        \n        result = response.json()\n        prompt_id = result.get("prompt_id")\n        \n        print(f"✅ Prompt queued with ID: {prompt_id}")\n        \n        # Attendre la complétion\n        timeout = job_input.get("timeout", 600)\n        outputs = wait_for_completion(prompt_id, timeout=timeout)\n        \n        return {\n            "status": "success",\n            "prompt_id": prompt_id,\n            "outputs": outputs,\n            "message": "Video generation completed"\n        }\n        \n    except TimeoutError as e:\n        return {"error": str(e), "status": "timeout"}\n    except Exception as e:\n        print(f"❌ Error: {str(e)}")\n        return {"error": str(e), "status": "failed"}\n\nif __name__ == "__main__":\n    print("="*50)\n    print("🚀 Starting RunPod Handler")\n    print("="*50)\n    runpod.serverless.start({"handler": handler})\n' > /handler.py

CMD ["./start.sh"]
