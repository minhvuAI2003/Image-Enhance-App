def load_model(task: str):
    args = get_default_args()
    args.backend = "cuda" if torch.cuda.is_available() else "cpu"  # Add backend parameter
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