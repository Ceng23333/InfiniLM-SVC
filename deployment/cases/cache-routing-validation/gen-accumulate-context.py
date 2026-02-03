#!/usr/bin/env python3
"""
Generate prompts with accumulating context for cache routing validation.

This simulates chatbot scenarios where:
- Each request contains full conversation history (accumulated context)
- New messages are appended to the conversation
- Requests with the same conversation history share a long common prefix
- This maximizes cache hit benefits in cache routing scenarios
"""

import json
import argparse
import random
import sys


def generate_accumulate_context_prompts(
    num_conversations: int,
    messages_per_conversation: int,
    context_len_per_message: int,
    new_message_len: int,
    output_file: str,
):
    """
    Generate prompts with accumulating context to simulate chatbot scenarios.

    Args:
        num_conversations: Number of different conversations (each gets a cache key)
        messages_per_conversation: Number of messages in each conversation
        context_len_per_message: Length of context added by each previous message
        new_message_len: Length of the new message (unique part)
        output_file: Output JSONL file path
    """
    # Generate conversation templates
    conversation_topics = [
        "artificial intelligence",
        "quantum computing",
        "space exploration",
        "climate change",
        "renewable energy",
        "biotechnology",
        "neural networks",
        "blockchain technology",
    ]

    # Ensure we have enough topics
    while len(conversation_topics) < num_conversations:
        conversation_topics.extend(conversation_topics)

    print(f"Generating {num_conversations} conversations with {messages_per_conversation} messages each...")
    print(f"  Context per message: ~{context_len_per_message} chars")
    print(f"  New message length: ~{new_message_len} chars")

    # Random seed for reproducibility
    random.seed(42)

    # First, generate all conversations (grouped by conversation)
    all_conversations = []

    for conv_idx in range(num_conversations):
        topic = conversation_topics[conv_idx % len(conversation_topics)]
        conversation_records = []

        # Build conversation history incrementally
        conversation_history = []
        conversation_id = f"conv_{conv_idx}"

        for msg_idx in range(messages_per_conversation):
            # Create a new user message
            if msg_idx == 0:
                # First message - introduce the topic with substantial context
                user_message = (
                    f"Let's discuss {topic}. "
                    f"This is a detailed conversation about {topic} and its implications. "
                    f"We will explore various aspects including technical details, "
                    f"real-world applications, and future prospects. "
                )
                # Pad to target length
                while len(user_message) < context_len_per_message:
                    user_message += f"Additional context about {topic} and its various aspects. "
                user_message = user_message[:context_len_per_message]
            else:
                # Subsequent messages - shorter new message (builds on accumulated context)
                user_message = (
                    f"Continuing our discussion about {topic}, "
                    f"let me add more details. "
                    f"Based on what we've discussed so far, "
                    f"I'd like to explore another aspect. "
                )
                # Pad to target length
                while len(user_message) < new_message_len:
                    user_message += f"More information about {topic}. "
                user_message = user_message[:new_message_len]

            # Add new user message to conversation history
            conversation_history.append({
                "role": "user",
                "content": user_message
            })

            # Create assistant response (simulated, for context accumulation)
            # In real scenario, this would be the model's response
            assistant_response = (
                f"That's an interesting point about {topic}. "
                f"Let me provide some insights based on our discussion. "
            )
            while len(assistant_response) < context_len_per_message:
                assistant_response += f"More details about {topic} and related concepts. "
            assistant_response = assistant_response[:context_len_per_message]

            # Add assistant response to history (for next request's context)
            conversation_history.append({
                "role": "assistant",
                "content": assistant_response
            })

            # Create prompt with full conversation history up to this point
            # This simulates real chatbot behavior where each request includes ALL previous messages
            # The key insight: later messages have MUCH longer shared prefixes (all previous messages)
            prompt_messages = conversation_history.copy()

            # Format for vLLM custom dataset
            # Include both "prompt" (for CustomDataset) and "messages" (for chat completions)
            # Also include explicit prompt_cache_key for cache routing
            # Convert messages to prompt string for CustomDataset compatibility
            prompt_text = "\n".join([
                f"{msg['role']}: {msg['content']}"
                for msg in prompt_messages
            ])

            record = {
                "prompt": prompt_text,  # For CustomDataset compatibility
                "messages": prompt_messages,  # For actual API requests
                "prompt_cache_key": conversation_id,  # Explicit cache key - same for all messages in conversation
                "conversation_id": conv_idx,  # For reference
                "message_index": msg_idx,  # For reference
            }

            conversation_records.append(record)

        all_conversations.append(conversation_records)

    # Shuffle conversations (but keep messages within each conversation in order)
    # This simulates real-world scenario where requests from different conversations
    # arrive interleaved, but each conversation maintains its order
    random.shuffle(all_conversations)

    # Write all records to file (conversations shuffled, but messages within conversations maintain order)
    with open(output_file, "w", encoding="utf-8") as f:
        for conversation_records in all_conversations:
            for record in conversation_records:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")

    # Print statistics
    print(f"✅ Generated prompts -> {output_file}")
    print(f"   Number of conversations: {num_conversations}")
    print(f"   Messages per conversation: {messages_per_conversation}")
    print(f"   Total prompts: {num_conversations * messages_per_conversation}")
    print(f"")
    print(f"   Expected behavior:")
    print(f"   - Requests from the same conversation share accumulated context")
    print(f"   - Later messages in a conversation have longer shared prefixes")
    print(f"   - Cache routing should show significant TTFT improvement for later messages")
    print(f"   - Each conversation should route to the same instance (cache key based)")


def main():
    parser = argparse.ArgumentParser(
        description="Generate accumulating context prompts for cache routing validation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate 4 conversations with 8 messages each (simulates 4 users chatting)
  python gen-accumulate-context.py --num-conversations 4 --messages-per-conv 8 --context-len 1024 --new-msg-len 128

  # Generate prompts for cache routing test
  python gen-accumulate-context.py --num-conversations 4 --messages-per-conv 16 --context-len 2048 --new-msg-len 64 --output accumulate_context.jsonl
        """
    )
    parser.add_argument(
        "--output",
        default="accumulate_context.jsonl",
        help="Output JSONL file path (default: accumulate_context.jsonl)"
    )
    parser.add_argument(
        "--num-conversations",
        type=int,
        default=4,
        help="Number of different conversations (default: 4)"
    )
    parser.add_argument(
        "--messages-per-conv",
        type=int,
        default=8,
        help="Number of messages per conversation (default: 8)"
    )
    parser.add_argument(
        "--context-len",
        type=int,
        default=1024,
        help="Length of context added by each message in characters (default: 1024)"
    )
    parser.add_argument(
        "--new-msg-len",
        type=int,
        default=128,
        help="Length of new message content in characters (default: 128)"
    )

    args = parser.parse_args()

    if args.num_conversations <= 0:
        print("Error: --num-conversations must be positive", file=sys.stderr)
        sys.exit(1)

    if args.messages_per_conv <= 0:
        print("Error: --messages-per-conv must be positive", file=sys.stderr)
        sys.exit(1)

    if args.context_len <= 0:
        print("Error: --context-len must be positive", file=sys.stderr)
        sys.exit(1)

    if args.new_msg_len <= 0:
        print("Error: --new-msg-len must be positive", file=sys.stderr)
        sys.exit(1)

    generate_accumulate_context_prompts(
        num_conversations=args.num_conversations,
        messages_per_conversation=args.messages_per_conv,
        context_len_per_message=args.context_len,
        new_message_len=args.new_msg_len,
        output_file=args.output,
    )


if __name__ == "__main__":
    main()
