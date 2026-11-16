/** Six entries of https://openrouter.ai/api/v1/models (16 November 2026), only the fields the app reads. */
export const modelListFixture = JSON.stringify({
  "data": [
    {
      "id": "anthropic/claude-sonnet-5.5",
      "supported_parameters": [
        "include_reasoning",
        "max_completion_tokens",
        "max_tokens",
        "reasoning",
        "reasoning_effort",
        "response_format",
        "stop",
        "structured_outputs",
        "tool_choice",
        "tools",
        "verbosity"
      ],
      "top_provider": {
        "context_length": 1000000,
        "max_completion_tokens": 128000,
        "is_moderated": true
      },
      "reasoning": {
        "mandatory": true,
        "supported_efforts": [
          "max",
          "xhigh",
          "high",
          "medium",
          "low"
        ],
        "default_effort": "high"
      }
    },
    {
      "id": "mistralai/mistral-large-4-0",
      "supported_parameters": [
        "frequency_penalty",
        "include_reasoning",
        "logprobs",
        "max_tokens",
        "presence_penalty",
        "reasoning",
        "reasoning_effort",
        "response_format",
        "seed",
        "stop",
        "structured_outputs",
        "temperature",
        "tool_choice",
        "tools",
        "top_logprobs",
        "top_p"
      ],
      "top_provider": {
        "context_length": 1048576,
        "max_completion_tokens": 262144,
        "is_moderated": false
      },
      "reasoning": {
        "mandatory": false,
        "default_enabled": true,
        "supported_efforts": [
          "high",
          "none"
        ],
        "default_effort": "high"
      }
    },
    {
      "id": "anthropic/claude-haiku-5.5",
      "supported_parameters": [
        "include_reasoning",
        "max_completion_tokens",
        "max_tokens",
        "reasoning",
        "reasoning_effort",
        "response_format",
        "stop",
        "structured_outputs",
        "tool_choice",
        "tools",
        "verbosity"
      ],
      "top_provider": {
        "context_length": 1000000,
        "max_completion_tokens": 128000,
        "is_moderated": true
      },
      "reasoning": {
        "mandatory": false,
        "supported_efforts": [
          "max",
          "xhigh",
          "high",
          "medium",
          "low",
          "none"
        ],
        "default_effort": "medium"
      }
    },
    {
      "id": "anthropic/claude-sonnet-4.5",
      "supported_parameters": [
        "include_reasoning",
        "max_completion_tokens",
        "max_tokens",
        "reasoning",
        "response_format",
        "stop",
        "structured_outputs",
        "temperature",
        "tool_choice",
        "tools",
        "top_k",
        "top_p"
      ],
      "top_provider": {
        "context_length": 1000000,
        "max_completion_tokens": 64000,
        "is_moderated": true
      },
      "reasoning": {
        "mandatory": false
      }
    },
    {
      "id": "anthropic/claude-opus-4.8",
      "supported_parameters": [
        "include_reasoning",
        "max_completion_tokens",
        "max_tokens",
        "reasoning",
        "reasoning_effort",
        "response_format",
        "stop",
        "structured_outputs",
        "tool_choice",
        "tools",
        "verbosity"
      ],
      "top_provider": {
        "context_length": 1000000,
        "max_completion_tokens": 128000,
        "is_moderated": true
      },
      "reasoning": {
        "mandatory": false,
        "default_enabled": false,
        "supported_efforts": [
          "max",
          "xhigh",
          "high",
          "medium",
          "low",
          "none"
        ],
        "default_effort": "high"
      }
    },
    {
      "id": "deepseek/deepseek-chat",
      "supported_parameters": [
        "frequency_penalty",
        "logit_bias",
        "max_tokens",
        "min_p",
        "presence_penalty",
        "repetition_penalty",
        "response_format",
        "seed",
        "stop",
        "structured_outputs",
        "temperature",
        "tool_choice",
        "tools",
        "top_k",
        "top_p"
      ],
      "top_provider": {
        "context_length": 128000,
        "max_completion_tokens": 16000,
        "is_moderated": false
      }
    }
  ]
});
