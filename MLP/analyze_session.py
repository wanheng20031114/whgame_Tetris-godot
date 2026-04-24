"""
WIDE TETRIS session analysis script.

Reads each snapshot from a Godot session JSON file, evaluates board features
with the selected MLP model, and writes an analyzed JSON file containing
the ai_scores array.

Usage:
    python analyze_session.py <session_json> <output_json> [--model dqn]

Supported models: dqn, genetic, es, reinforce, a2c, ppo
"""
import argparse
import glob
import json
import os
import sys

import numpy as np
import torch

from network import CHECKPOINT_KEY_MODELS, MODEL_CONFIGS, PolicyNetwork


def find_model_file(models_dir: str, model_name: str) -> str:
    """Find the first matching .pth file in the models directory."""
    pattern = os.path.join(models_dir, f"{model_name}*.pth")
    matches = glob.glob(pattern)
    if not matches:
        raise FileNotFoundError(
            f"Model file not found: {pattern}\n"
            f"models directory contents: {os.listdir(models_dir)}"
        )
    return matches[0]


def load_model(model_path: str, model_name: str) -> PolicyNetwork:
    """Load model weights into PolicyNetwork."""
    config = MODEL_CONFIGS.get(model_name)
    if config is None:
        raise ValueError(f"Unknown model: {model_name}. Supported: {list(MODEL_CONFIGS.keys())}")

    net = PolicyNetwork(
        state_size=4,
        action_size=1,
        fc1_units=config["fc1"],
        fc2_units=config["fc2"]
    )

    checkpoint = torch.load(model_path, map_location="cpu", weights_only=False)

    checkpoint_key = CHECKPOINT_KEY_MODELS.get(model_name)
    if checkpoint_key and isinstance(checkpoint, dict) and checkpoint_key in checkpoint:
        state_dict = checkpoint[checkpoint_key]
    elif isinstance(checkpoint, dict) and "state_dict" in checkpoint:
        state_dict = checkpoint["state_dict"]
    else:
        state_dict = checkpoint

    net.load_state_dict(state_dict)
    net.eval()
    return net


def analyze_session(session_data: dict, model: PolicyNetwork) -> list:
    """Evaluate each session snapshot with the MLP model."""
    snapshots = session_data.get("snapshots", [])
    scores = []

    for snap in snapshots:
        lines_cleared = snap.get("lines_cleared_this_lock", 0)
        holes = snap.get("holes", 0)
        bumpiness = snap.get("bumpiness", 0)
        total_height = snap.get("total_height", 0)

        state = torch.FloatTensor([lines_cleared, holes, bumpiness, total_height])
        with torch.no_grad():
            value = model(state.unsqueeze(0)).item()
        scores.append(round(value, 4))

    return scores


def main():
    # Keep console-facing text ASCII. Some Windows consoles use cp932/cp936,
    # and non-ASCII output can raise UnicodeEncodeError.
    parser = argparse.ArgumentParser(description="WIDE TETRIS Session Analyzer")
    parser.add_argument("session_json", help="Input session JSON file path")
    parser.add_argument("output_json", help="Output analyzed JSON file path")
    parser.add_argument("--model", default="dqn", choices=list(MODEL_CONFIGS.keys()),
                        help="Model name to use (default: dqn)")
    args = parser.parse_args()

    with open(args.session_json, "r", encoding="utf-8") as f:
        session_data = json.load(f)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    models_dir = os.path.join(script_dir, "models")
    model_path = find_model_file(models_dir, args.model)
    print(f"Using model: {model_path}")

    model = load_model(model_path, args.model)

    ai_scores = analyze_session(session_data, model)
    print(f"Analysis complete: {len(ai_scores)} steps")

    output_data = {
        "session_id": session_data.get("session_id", "unknown"),
        "ai_model_used": args.model,
        "ai_model_file": os.path.basename(model_path),
        "ai_scores": ai_scores,
        "total_steps": len(ai_scores),
    }

    with open(args.output_json, "w", encoding="utf-8") as f:
        json.dump(output_data, f, indent="\t", ensure_ascii=False)

    print(f"Result saved: {args.output_json}")


if __name__ == "__main__":
    main()
