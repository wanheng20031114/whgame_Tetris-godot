"""
Inference-only MLP network definition.

This module contains only the forward-pass network structure required to load
existing checkpoints and run replay analysis.
"""
import torch
import torch.nn as nn
import torch.nn.functional as F


MODEL_CONFIGS = {
    "dqn":       {"fc1": 64,  "fc2": 64},
    "genetic":   {"fc1": 32,  "fc2": 32},
    "es":        {"fc1": 32,  "fc2": 32},
    "reinforce": {"fc1": 128, "fc2": 128},
    "a2c":       {"fc1": 64,  "fc2": 64},
    "ppo":       {"fc1": 64,  "fc2": 64},
}

CHECKPOINT_KEY_MODELS = {"dqn": "v_network_state_dict"}


class PolicyNetwork(nn.Module):
    """Simple three-layer fully connected network for scalar state values."""

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
