from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
from ngrok import ngrok
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI()

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"]
)

@app.post("/{task}")
async def process_image_endpoint(task: str, request: ImageRequest):
    """Process image from base64 string"""
    try:
        logger.info(f"Received request for task: {task}")
        logger.info(f"Request headers: {request.headers}")
        logger.info(f"Request client: {request.client}")
        
        # Validate task
        if task not in ["derain", "gaussian_denoise", "real_denoise"]:
            logger.error(f"Unsupported task: {task}")
            raise HTTPException(status_code=400, detail=f"Unsupported task: {task}")
        
        logger.info("Converting base64 to image...")
        # Convert base64 to image
        image = base64_to_image(request.image)
        logger.info(f"Image size: {image.size}")
        logger.info(f"Image mode: {image.mode}")
        
        logger.info("Processing image...")
        # Process image
        processed_base64 = await process_image_base64(image, task)
        logger.info("Image processed successfully")
        logger.info(f"Processed image size: {len(processed_base64)} bytes")
        
        return {"enhanced_image": processed_base64}
    
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/")
async def root():
    """API endpoints information"""
    logger.info("Root endpoint called")
    logger.info("Returning available endpoints")
    return {
        "status": "ok",
        "endpoints": {
            "/derain": "Remove rain from image",
            "/gaussian-denoise": "Remove Gaussian noise from image",
            "/real-denoise": "Remove real noise from image"
        }
    }

if __name__ == "__main__":
    # Setup ngrok
    public_url = setup_ngrok()
    logger.info(f"Server running at: {public_url}")
    logger.info("Starting uvicorn server...")
    # Run the FastAPI app with detailed logging
    uvicorn.run(
        app, 
        host="0.0.0.0", 
        port=8000, 
        log_level="debug",
        access_log=True
    ) 