import runpod
import requests
import json
import time

COMFYUI_URL = "http://localhost:8188"

def get_history(prompt_id):
    """Récupérer l'historique d'une génération"""
    try:
        response = requests.get(f"{COMFYUI_URL}/history/{prompt_id}")
        return response.json()
    except:
        return {}

def wait_for_completion(prompt_id, timeout=600):
    """Attendre que la génération soit terminée"""
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        history = get_history(prompt_id)
        
        if prompt_id in history:
            prompt_history = history[prompt_id]
            
            # Vérifier si terminé
            if "outputs" in prompt_history:
                print(f"✅ Generation completed for {prompt_id}")
                return prompt_history["outputs"]
        
        print(f"⏳ Waiting for generation... ({int(time.time() - start_time)}s)")
        time.sleep(2)
    
    raise TimeoutError(f"Generation timed out after {timeout}s")

def handler(job):
    """Handler RunPod pour traiter les jobs"""
    job_id = job.get("id")
    print(f"📥 Job received: {job_id}")
    
    job_input = job.get("input", {})
    workflow = job_input.get("workflow")
    
    if not workflow:
        return {"error": "No workflow provided"}
    
    try:
        # Envoyer le workflow à ComfyUI
        print("📤 Sending workflow to ComfyUI...")
        response = requests.post(
            f"{COMFYUI_URL}/prompt",
            json={"prompt": workflow},
            timeout=30
        )
        
        if response.status_code != 200:
            return {"error": f"ComfyUI error: {response.text}"}
        
        result = response.json()
        prompt_id = result.get("prompt_id")
        
        print(f"✅ Prompt queued with ID: {prompt_id}")
        
        # Attendre la complétion
        timeout = job_input.get("timeout", 600)
        outputs = wait_for_completion(prompt_id, timeout=timeout)
        
        return {
            "status": "success",
            "prompt_id": prompt_id,
            "outputs": outputs,
            "message": "Video generation completed"
        }
        
    except TimeoutError as e:
        return {"error": str(e), "status": "timeout"}
    except Exception as e:
        print(f"❌ Error: {str(e)}")
        return {"error": str(e), "status": "failed"}

if __name__ == "__main__":
    print("="*50)
    print("🚀 Starting RunPod Handler")
    print("="*50)
    runpod.serverless.start({"handler": handler})
