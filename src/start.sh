#!/usr/bin/env bash
set -e

echo "========================================="
echo "worker-comfyui: Initializing"
echo "========================================="

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Vérifier que le Network Volume est monté
echo "Checking Network Volume..."
if [ ! -d "/workspace/Models" ]; then
    echo "❌ ERROR: Network Volume not mounted at /workspace"
    echo "Please attach your Network Volume with Models and custom_nodes"
    exit 1
fi

echo "✅ Network Volume detected"
echo "📁 Models location: /workspace/Models"
echo "📁 Custom nodes location: /workspace/custom_nodes"

# Lister le contenu pour debug
echo ""
echo "Content of /workspace:"
ls -la /workspace/ || echo "Cannot list /workspace"

# Créer un symlink pour les custom nodes depuis le volume
echo ""
echo "Setting up custom nodes from Network Volume..."
if [ -d "/workspace/custom_nodes" ]; then
    # Supprimer le dossier custom_nodes de ComfyUI s'il existe
    if [ -d "/comfyui/custom_nodes" ]; then
        echo "Removing default custom_nodes..."
        rm -rf /comfyui/custom_nodes
    fi
    
    # Créer le symlink vers le volume
    echo "Creating symlink to /workspace/custom_nodes..."
    ln -s /workspace/custom_nodes /comfyui/custom_nodes
    
    # Installer les dépendances des custom nodes
    echo "Installing custom node dependencies..."
    for node_dir in /workspace/custom_nodes/*/; do
        if [ -f "${node_dir}requirements.txt" ]; then
            node_name=$(basename "$node_dir")
            echo "  → Installing requirements for $node_name"
            pip install -r "${node_dir}requirements.txt" --no-cache-dir --quiet || echo "    ⚠️ Failed to install requirements for $node_name"
        fi
    done
    echo "✅ Custom nodes setup complete"
else
    echo "⚠️ Warning: No custom_nodes found in /workspace/custom_nodes"
fi

# Vérifier la présence des modèles
echo ""
echo "Checking models..."
if [ -d "/workspace/Models" ]; then
    echo "Available model directories:"
    ls -la /workspace/Models/ || echo "Cannot list Models directory"
else
    echo "⚠️ Warning: No Models directory found"
fi

# Ensure ComfyUI-Manager runs in offline network mode inside the container
echo ""
echo "Configuring ComfyUI-Manager..."
comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2

echo ""
echo "========================================="
echo "worker-comfyui: Starting ComfyUI"
echo "========================================="

# Allow operators to tweak verbosity; default is DEBUG.
: "${COMFY_LOG_LEVEL:=DEBUG}"

# Serve the API and don't shutdown the container
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --listen --verbose "${COMFY_LOG_LEVEL}" --log-stdout &
    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --verbose "${COMFY_LOG_LEVEL}" --log-stdout &
    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py
fi