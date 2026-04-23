"""
纯推理用 MLP 网络定义。
仅包含 PolicyNetwork 的前向传播逻辑，不含任何训练代码。
支持不同 fc_units 配置以加载各模型的权重。
"""
import torch
import torch.nn as nn
import torch.nn.functional as F


# 各模型的网络参数配置（fc1_units, fc2_units）
# 必须与训练时使用的配置完全一致，否则无法加载权重。
MODEL_CONFIGS = {
    "dqn":       {"fc1": 64,  "fc2": 64},
    "genetic":   {"fc1": 32,  "fc2": 32},
    "es":        {"fc1": 32,  "fc2": 32},
    "reinforce": {"fc1": 128, "fc2": 128},
    "a2c":       {"fc1": 64,  "fc2": 64},
    "ppo":       {"fc1": 64,  "fc2": 64},
}

# DQN 模型的 checkpoint 使用 'v_network_state_dict' 键；
# 其他模型（Genetic/ES/Reinforce/A2C/PPO）直接保存为裸 state_dict。
CHECKPOINT_KEY_MODELS = {"dqn": "v_network_state_dict"}


class PolicyNetwork(nn.Module):
    """简单的三层全连接网络，输入状态特征，输出价值标量。"""

    def __init__(self, state_size: int = 4, action_size: int = 1,
                 fc1_units: int = 64, fc2_units: int = 64):
        super().__init__()
        self.fc1 = nn.Linear(state_size, fc1_units)
        self.fc2 = nn.Linear(fc1_units, fc2_units)
        self.fc3 = nn.Linear(fc2_units, action_size)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = F.relu(self.fc1(x))
        x = F.relu(self.fc2(x))
        return self.fc3(x)
