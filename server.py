from fastapi import FastAPI, File, UploadFile, Form, HTTPException
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import torch
from torchvision import transforms
from PIL import Image
import io
import base64
from model import Restormer
from utils import get_default_args
from pyngrok import ngrok, conf
import uvicorn

app = FastAPI()

# Enable CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# === Ngrok setup ===
def setup_ngrok():
    conf.get_default().auth_token = "2p1nq5rK3ywq2n3HvcTGVDgtUGb_WPjQ2a39CcdETaTn4jFq"
    public_url = ngrok.connect(8000)
    print(f"Public URL: {public_url}")
    return public_url

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# === Load model ===
def load_model(task: str):
    args = get_default_args()
    model = Restormer(
        num_blocks=args.num_blocks,
        num_heads=args.num_heads,
        channels=args.channels,
        num_refinement=args.num_refinement,
        expansion_factor=args.expansion_factor
    )

    ckpt_paths = {
        "derain": "models/derain.pth",
        "gaussian_denoise": "models/gauss_denoise.pth",
        "real_denoise": "models/real_denoise.pth"
    }
    ckpt_path = ckpt_paths.get(task)
    if not ckpt_path:
        raise ValueError("Unsupported task")

    try:
        state_dict = torch.load(ckpt_path, map_location=device)
        model.load_state_dict(state_dict)
        model.eval()
        return model.to(device)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error loading model: {str(e)}")

# === Cắt ảnh về kích thước chia hết cho 8 ===
def crop_to_multiple_of_8(img: Image.Image) -> Image.Image:
    w, h = img.size
    w = w - (w % 8)
    h = h - (h % 8)
    return img.crop((0, 0, w, h))

transform = transforms.Compose([
    transforms.ToTensor(),
])

class ImageRequest(BaseModel):
    image: str  # base64 encoded image
    task: str   # task name

def base64_to_image(base64_string: str) -> Image.Image:
    """Convert base64 string to PIL Image"""
    try:
        image_data = base64.b64decode(base64_string)
        image = Image.open(io.BytesIO(image_data)).convert("RGB")
        return image
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid image data: {str(e)}")

def image_to_base64(image: Image.Image) -> str:
    """Convert PIL Image to base64 string"""
    buffered = io.BytesIO()
    image.save(buffered, format="PNG")
    return base64.b64encode(buffered.getvalue()).decode()

async def process_image_base64(image: Image.Image, task: str):
    """Process image from base64 string"""
    try:
        # Process image
        image = crop_to_multiple_of_8(image)
        image_tensor = transform(image).unsqueeze(0).to(device)

        if image_tensor is None:
            raise HTTPException(status_code=500, detail="Failed to convert image to tensor")

        # Load and run model
        model = load_model(task)
        with torch.no_grad():
            output_tensor = model(image_tensor).squeeze().clamp(0, 1).cpu()

        if output_tensor is None:
            raise HTTPException(status_code=500, detail="Model failed to process image")

        # Convert to image and return base64
        output_image = transforms.ToPILImage()(output_tensor)
        return image_to_base64(output_image)

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error processing image: {str(e)}")

async def process_image_file(file: UploadFile, task: str):
    """Process image from uploaded file"""
    try:
        # Validate file
        if not file.content_type.startswith('image/'):
            raise HTTPException(status_code=400, detail="File must be an image")

        # Read and validate image
        image_bytes = await file.read()
        if not image_bytes:
            raise HTTPException(status_code=400, detail="Empty file")

        try:
            image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Invalid image format: {str(e)}")

        # Process image
        image = crop_to_multiple_of_8(image)
        image_tensor = transform(image).unsqueeze(0).to(device)

        if image_tensor is None:
            raise HTTPException(status_code=500, detail="Failed to convert image to tensor")

        # Load and run model
        model = load_model(task)
        with torch.no_grad():
            output_tensor = model(image_tensor).squeeze().clamp(0, 1).cpu()

        if output_tensor is None:
            raise HTTPException(status_code=500, detail="Model failed to process image")

        # Convert to image and return
        output_image = transforms.ToPILImage()(output_tensor)
        buf = io.BytesIO()
        output_image.save(buf, format='PNG')
        buf.seek(0)

        return StreamingResponse(buf, media_type="image/png")

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error processing image: {str(e)}")

@app.post("/{task}")
async def process_image_endpoint(task: str, request: ImageRequest):
    """Process image from base64 string"""
    try:
        # Validate task
        if task not in ["derain", "gaussian_denoise", "real_denoise"]:
            raise HTTPException(status_code=400, detail=f"Unsupported task: {task}")
        
        # Convert base64 to image
        image = base64_to_image(request.image)
        
        # Process image
        processed_base64 = await process_image_base64(image, task)
        
        return {"enhanced_image": processed_base64}
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/derain")
async def derain(file: UploadFile = File(...)):
    """Remove rain from image"""
    return await process_image_file(file, "derain")

@app.post("/gaussian-denoise")
async def gaussian_denoise(file: UploadFile = File(...)):
    """Remove Gaussian noise from image"""
    return await process_image_file(file, "gaussian_denoise")

@app.post("/real-denoise")
async def real_denoise(file: UploadFile = File(...)):
    """Remove real noise from image"""
    return await process_image_file(file, "real_denoise")

@app.get("/")
async def root():
    """API endpoints information"""
    return {
        "endpoints": {
            "/derain": "Remove rain from image",
            "/gaussian-denoise": "Remove Gaussian noise from image",
            "/real-denoise": "Remove real noise from image"
        }
    }

if __name__ == "__main__":
    # Setup ngrok
    public_url = setup_ngrok()
    # Run the FastAPI app
    uvicorn.run(app, host="0.0.0.0", port=8000) 