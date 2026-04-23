"""
WIDE TETRIS — Session 分析脚本

从 Godot 的 session JSON 中读取每步快照的地形特征，
送入指定的 MLP 模型进行状态价值评估，
输出带有 ai_scores 数组的分析结果 JSON。

用法:
    python analyze_session.py <session_json> <output_json> [--model dqn]

支持的模型: dqn, genetic, es, reinforce, a2c, ppo
"""
import os
import sys
import json
import glob
import argparse

import torch
import numpy as np

from network import PolicyNetwork, MODEL_CONFIGS, CHECKPOINT_KEY_MODELS


def find_model_file(models_dir: str, model_name: str) -> str:
    """在 models/ 目录下查找匹配的 .pth 文件。"""
    pattern = os.path.join(models_dir, f"{model_name}*.pth")
    matches = glob.glob(pattern)
    if not matches:
        raise FileNotFoundError(
            f"找不到模型文件: {pattern}\n"
            f"models/ 目录内容: {os.listdir(models_dir)}"
        )
    # 取第一个匹配的文件
    return matches[0]


def load_model(model_path: str, model_name: str) -> PolicyNetwork:
    """加载模型权重到 PolicyNetwork。"""
    config = MODEL_CONFIGS.get(model_name)
    if config is None:
        raise ValueError(f"未知模型: {model_name}。支持: {list(MODEL_CONFIGS.keys())}")

    net = PolicyNetwork(
        state_size=4,
        action_size=1,
        fc1_units=config["fc1"],
        fc2_units=config["fc2"]
    )

    checkpoint = torch.load(model_path, map_location="cpu", weights_only=False)

    # DQN 模型的 checkpoint 是一个字典，包含 'v_network_state_dict' 键
    # 其他模型直接保存为 state_dict
    checkpoint_key = CHECKPOINT_KEY_MODELS.get(model_name)
    if checkpoint_key and isinstance(checkpoint, dict) and checkpoint_key in checkpoint:
        state_dict = checkpoint[checkpoint_key]
    elif isinstance(checkpoint, dict) and "state_dict" in checkpoint:
        state_dict = checkpoint["state_dict"]
    else:
        # 直接就是 state_dict（Genetic/ES 等）
        state_dict = checkpoint

    net.load_state_dict(state_dict)
    net.eval()
    return net


def analyze_session(session_data: dict, model: PolicyNetwork) -> list:
    """对 session 中每个 snapshot 进行 MLP 评估。

    MLP 输入特征: [lines_cleared_this_lock, holes, bumpiness, total_height]
    MLP 输出: 状态价值标量（越高表示棋盘状态越好）

    Returns:
        list: 每步的 AI 评分（原始浮点值）
    """
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
    parser = argparse.ArgumentParser(description="WIDE TETRIS Session 分析器")
    parser.add_argument("session_json", help="输入的 session JSON 文件路径")
    parser.add_argument("output_json", help="输出的分析结果 JSON 文件路径")
    parser.add_argument("--model", default="dqn", choices=list(MODEL_CONFIGS.keys()),
                        help="使用的模型名称 (默认: dqn)")
    args = parser.parse_args()

    # 读取 session JSON
    with open(args.session_json, "r", encoding="utf-8") as f:
        session_data = json.load(f)

    # 查找并加载模型
    script_dir = os.path.dirname(os.path.abspath(__file__))
    models_dir = os.path.join(script_dir, "models")
    model_path = find_model_file(models_dir, args.model)
    print(f"使用模型: {model_path}")

    model = load_model(model_path, args.model)

    # 分析
    ai_scores = analyze_session(session_data, model)
    print(f"分析完成: {len(ai_scores)} 步")

    # 构造输出
    output_data = {
        "session_id": session_data.get("session_id", "unknown"),
        "ai_model_used": args.model,
        "ai_model_file": os.path.basename(model_path),
        "ai_scores": ai_scores,
        "total_steps": len(ai_scores),
    }

    # 写入输出 JSON
    with open(args.output_json, "w", encoding="utf-8") as f:
        json.dump(output_data, f, indent="\t", ensure_ascii=False)

    print(f"结果已保存: {args.output_json}")


if __name__ == "__main__":
    main()
