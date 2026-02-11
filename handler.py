import runpod
import requests
import json
import time
import base64

COMFYUI_URL = "http://localhost:8188"
WORKFLOW_PATH = "/workflow_template.json"

# Charger le workflow template
print(f"Loading workflow from {WORKFLOW_PATH}")
with open(WORKFLOW_PATH, 'r', encoding='utf-8') as f:
    WORKFLOW_TEMPLATE = json.load(f)
print(f"✅ Workflow loaded ({len(WORKFLOW_TEMPLATE)} nodes)")


def get_history(prompt_id):
    """Récupérer l'historique"""
    try:
        response = requests.get(f"{COMFYUI_URL}/history/{prompt_id}")
        return response.json()
    except:
        return {}


def wait_for_completion(prompt_id, timeout=900):
    """Attendre la complétion"""
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        history = get_history(prompt_id)
        
        if prompt_id in history:
            prompt_history = history[prompt_id]
            
            if "outputs" in prompt_history:
                print(f"✅ Generation completed")
                return prompt_history["outputs"]
        
        elapsed = int(time.time() - start_time)
        if elapsed % 10 == 0:  # Log every 10s
            print(f"⏳ Waiting... ({elapsed}s / {timeout}s)")
        time.sleep(2)
    
    raise TimeoutError(f"Timeout after {timeout}s")


def upload_image(image_base64, filename="input.png"):
    """Upload image to ComfyUI"""
    try:
        image_data = base64.b64decode(image_base64)
        files = {'image': (filename, image_data, 'image/png')}
        response = requests.post(f"{COMFYUI_URL}/upload/image", files=files)
        
        if response.status_code == 200:
            return response.json().get('name')
        else:
            raise Exception(f"Upload failed: {response.text}")
    except Exception as e:
        print(f"❌ Upload error: {e}")
        raise


def modify_workflow(params):
    """Modifie le workflow avec les paramètres utilisateur"""
    import copy
    workflow = copy.deepcopy(WORKFLOW_TEMPLATE)
    
    # 1. Type de workflow (bypass_mode)
    workflow_type = params.get("workflow_type", 1)  # 1=simple, 2=fond
    if "184" in workflow:
        workflow["184"]["inputs"]["value"] = workflow_type
        print(f"✅ Workflow type: {workflow_type}")
    
    # 2. Format vidéo (9:16 ou 16:9)
    video_format = params.get("format", 0)  # 0=16:9, 1=9:16
    if "158" in workflow:
        workflow["158"]["inputs"]["index"] = video_format
        print(f"✅ Format: {'16:9' if video_format == 0 else '9:16'}")
    
    # 3. Taille (pourcentage de 0.3 à 1.0)
    size_scale = params.get("size_scale", 0.65)
    if "162" in workflow:
        workflow["162"]["inputs"]["Xf"] = size_scale
        print(f"✅ Size scale: {int(size_scale*100)}%")
    
    # 4. Longueur vidéo (frames)
    video_length = params.get("video_length", 61)
    if "279" in workflow:
        workflow["279"]["inputs"]["value"] = video_length
        print(f"✅ Video length: {video_length} frames")
    
    # 5. Upload image
    if "image_base64" in params:
        print("📤 Uploading image...")
        image_name = upload_image(params["image_base64"])
        
        # Mettre à jour le nœud LoadImage (186)
        if "186" in workflow:
            # Le nœud 186 est un switch, il faut trouver le vrai LoadImage
            # Pour l'instant, cherchons tous les LoadImage
            for node_id, node_data in workflow.items():
                if node_data.get("class_type") == "LoadImage":
                    node_data["inputs"]["image"] = image_name
                    print(f"✅ Image set in node {node_id}: {image_name}")
                    break
    
    # 6. Prompt utilisateur
    if "user_prompt" in params:
        prompt = params["user_prompt"]
        
        # Le nœud 147 contient le Gemini API
        if "147" in workflow:
            if "prompt2" in workflow["147"]["inputs"]:
                workflow["147"]["inputs"]["prompt2"] = prompt
                print(f"✅ User prompt set: {prompt[:50]}...")
    
    # 7. Seed (aléatoire par défaut)
    import random
    seed = params.get("seed", random.randint(0, 2**32 - 1))
    if "57" in workflow:
        workflow["57"]["inputs"]["noise_seed"] = seed
    if "58" in workflow:
        workflow["58"]["inputs"]["noise_seed"] = seed
    print(f"✅ Seed: {seed}")
    
    return workflow


def handler(job):
    """Handler RunPod"""
    job_id = job.get("id")
    print(f"\n{'='*50}")
    print(f"📥 Job ID: {job_id}")
    print(f"{'='*50}\n")
    
    job_input = job.get("input", {})
    
    # Option 1: Workflow custom complet
    if "workflow" in job_input and job_input["workflow"]:
        workflow = job_input["workflow"]
        print("Using custom workflow")
    
    # Option 2: Template avec paramètres
    else:
        print("Using template with parameters:")
        workflow = modify_workflow(job_input)
    
    try:
        # Envoyer à ComfyUI
        print("\n📤 Sending to ComfyUI...")
        response = requests.post(
            f"{COMFYUI_URL}/prompt",
            json={"prompt": workflow},
            timeout=30
        )
        
        if response.status_code != 200:
            return {"error": f"ComfyUI error: {response.text}"}
        
        result = response.json()
        prompt_id = result.get("prompt_id")
        
        print(f"✅ Queued: {prompt_id}\n")
        
        # Attendre
        timeout = job_input.get("timeout", 900)
        outputs = wait_for_completion(prompt_id, timeout)
        
        # Récupérer vidéos
        video_files = []
        for node_id, node_output in outputs.items():
            if "gifs" in node_output:
                for video_info in node_output["gifs"]:
                    video_files.append({
                        "filename": video_info.get("filename"),
                        "subfolder": video_info.get("subfolder"),
                        "type": video_info.get("type"),
                        "node_id": node_id
                    })
        
        print(f"\n✅ Success! Generated {len(video_files)} video(s)")
        
        return {
            "status": "success",
            "prompt_id": prompt_id,
            "video_files": video_files,
            "outputs": outputs
        }
        
    except TimeoutError as e:
        return {"error": str(e), "status": "timeout"}
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return {"error": str(e), "status": "failed"}


if __name__ == "__main__":
    print("="*50)
    print("🚀 Wan 2.2 RunPod Handler")
    print("="*50)
    runpod.serverless.start({"handler": handler})
