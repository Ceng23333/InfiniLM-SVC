#!/usr/bin/env python3
"""
Generate prompts with configurable probability of large initial context for cache type routing validation.

This simulates scenarios where:
- Some conversations start with large initial context (route to static cache)
- Other conversations start with small context (route to paged cache)
- Message body size determines routing to paged vs static cache instances
"""

import json
import argparse
import random
import sys


def generate_large_context_prompts(
    num_conversations: int,
    messages_per_conversation: int,
    context_len_per_message: int,
    new_message_len: int,
    large_context_prob: float = None,
    num_large_context: int = None,
    large_context_len: int = 16000,
    output_file: str = "large_context.jsonl",
):
    """
    Generate prompts with configurable large initial context.

    Args:
        num_conversations: Number of different conversations
        messages_per_conversation: Number of messages in each conversation
        context_len_per_message: Length of context added by each message in characters
        new_message_len: Length of new message content in characters
        large_context_prob: Probability of large initial context (0.0-1.0) - used if num_large_context is None
        num_large_context: Exact number of conversations with large context (overrides large_context_prob if set)
        large_context_len: Length of large initial context in characters (~4 chars per token)
        output_file: Output JSONL file path
    """
    # Character-based generation (1 token ≈ 4 characters)
    print("Using character-based generation (1 token ≈ 4 characters)")
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
    print(f"  Context per message: ~{context_len_per_message} chars (~{context_len_per_message // 4} tokens)")
    print(f"  New message length: ~{new_message_len} chars (~{new_message_len // 4} tokens)")

    # Determine which conversations should have large context
    if num_large_context is not None:
        # Use exact number of large context conversations
        if num_large_context > num_conversations:
            print(f"Warning: num_large_context ({num_large_context}) > num_conversations ({num_conversations}), using {num_conversations}", file=sys.stderr)
            num_large_context = num_conversations
        large_context_indices = set(range(num_large_context))
        print(f"  Large context conversations: {num_large_context} (exact number)")
    else:
        # Use probability-based selection
        large_context_indices = set()
        if large_context_prob is None:
            large_context_prob = 0.5
        print(f"  Large context probability: {large_context_prob}")
    print(f"  Large context length: ~{large_context_len} chars (~{large_context_len // 4} tokens)")

    # Random seed for reproducibility
    random.seed(42)

    # If using probability, select conversations randomly
    if num_large_context is None:
        for conv_idx in range(num_conversations):
            if random.random() < large_context_prob:
                large_context_indices.add(conv_idx)

    # First, generate all conversations (grouped by conversation)
    all_conversations = []

    for conv_idx in range(num_conversations):
        topic = conversation_topics[conv_idx % len(conversation_topics)]
        conversation_records = []

        # Check if this conversation should have large initial context
        has_large_context = conv_idx in large_context_indices

        # Build conversation history incrementally
        conversation_history = []
        conversation_id = f"conv_{conv_idx}"

        for msg_idx in range(messages_per_conversation):
            # Create a new user message
            if msg_idx == 0:
                # First message - introduce the topic
                if has_large_context:
                    # Large initial context - will route to static cache (~4k tokens)
                    user_message = (
                        f"Let's discuss {topic}. "
                        f"This is a detailed conversation about {topic} and its implications. "
                        f"We will explore various aspects including technical details, "
                        f"real-world applications, and future prospects. "
                    )
                    # Pad to large context length (~16k chars ≈ 4k tokens)
                    while len(user_message) < large_context_len:
                        user_message += (
                            f"Additional context about {topic} and its various aspects. "
                            f"More information about {topic} and related concepts. "
                            f"Detailed explanations of {topic} and its implications. "
                            f"Further discussion of {topic} and its applications. "
                            f"Exploring {topic} from different perspectives. "
                        )
                    user_message = user_message[:large_context_len]
                else:
                    # Small initial context - will route to paged cache
                    user_message = (
                        f"Let's discuss {topic}. "
                        f"This is a conversation about {topic}. "
                    )
                    # Pad to target length
                    while len(user_message) < context_len_per_message:
                        user_message += f"Additional context about {topic}. "
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
            prompt_messages = conversation_history.copy()

            # Format for vLLM custom dataset
            # Include both "prompt" (for CustomDataset) and "messages" (for chat completions)
            # Convert messages to prompt string for CustomDataset compatibility
            prompt_text = "\n".join([
                f"{msg['role']}: {msg['content']}"
                for msg in prompt_messages
            ])

            record = {
                "prompt": prompt_text,  # For CustomDataset compatibility
                "messages": prompt_messages,  # For actual API requests
                "conversation_id": conv_idx,  # For reference
                "message_index": msg_idx,  # For reference
                "has_large_context": has_large_context,  # For reference
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
    large_context_count = sum(
        1 for conv in all_conversations
        for record in conv
        if record.get("has_large_context", False)
    )
    small_context_count = sum(
        1 for conv in all_conversations
        for record in conv
        if not record.get("has_large_context", False)
    )

    # Calculate statistics (character-based, approximate tokens)
    all_records = [record for conv in all_conversations for record in conv]
    char_counts = [sum(len(msg["content"]) for msg in r.get("messages", [])) for r in all_records]
    max_chars = max(char_counts) if char_counts else 0
    avg_chars = sum(char_counts) / len(char_counts) if char_counts else 0

    print(f"✅ Generated prompts -> {output_file}")
    print(f"   Number of conversations: {num_conversations}")
    print(f"   Messages per conversation: {messages_per_conversation}")
    print(f"   Total prompts: {num_conversations * messages_per_conversation}")
    print(f"   Conversations with large context: {sum(1 for conv in all_conversations if conv[0].get('has_large_context', False))}")
    print(f"   Conversations with small context: {sum(1 for conv in all_conversations if not conv[0].get('has_large_context', False))}")
    print(f"   Character statistics (approximate tokens = chars / 4):")
    print(f"     Max input chars: {max_chars} (~{max_chars // 4} tokens)")
    print(f"     Avg input chars: {avg_chars:.1f} (~{avg_chars // 4:.1f} tokens)")
    print(f"")
    print(f"   Expected behavior:")
    print(f"   - Requests with large initial context (> threshold) should route to static cache")
    print(f"   - Requests with small initial context (≤ threshold) should route to paged cache")
    print(f"   - Routing is based on message body size (sum of all message content lengths)")


def main():
    parser = argparse.ArgumentParser(
        description="Generate prompts with configurable probability of large initial context for cache type routing validation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate 4 conversations with up to 4k tokens (~16k chars)
  python gen-large-context.py --num-conversations 4 --messages-per-conv 8 --context-len 1024 --new-msg-len 128 --large-context-prob 0.5 --large-context-len 16000

  # Generate prompts for cache type routing test with 4k token approximation
  python gen-large-context.py --num-conversations 4 --messages-per-conv 8 --context-len 1024 --new-msg-len 128 --large-context-prob 0.5 --large-context-len 16000 --output large_context_4k.jsonl
        """
    )
    parser.add_argument(
        "--output",
        default="large_context.jsonl",
        help="Output JSONL file path (default: large_context.jsonl)"
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
        help="Length of context added by each message in characters (default: 1024, ~256 tokens)"
    )
    parser.add_argument(
        "--new-msg-len",
        type=int,
        default=128,
        help="Length of new message content in characters (default: 128, ~32 tokens)"
    )
    parser.add_argument(
        "--large-context-prob",
        type=float,
        default=None,
        help="Probability of large initial context (0.0-1.0). Ignored if --num-large-context is set."
    )
    parser.add_argument(
        "--num-large-context",
        type=int,
        default=None,
        help="Exact number of conversations with large initial context (overrides --large-context-prob if set)"
    )
    parser.add_argument(
        "--large-context-len",
        type=int,
        default=16000,
        help="Length of large initial context in characters (default: 16000, ~4000 tokens)"
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

    if args.large_context_prob is not None and not 0.0 <= args.large_context_prob <= 1.0:
        print("Error: --large-context-prob must be between 0.0 and 1.0", file=sys.stderr)
        sys.exit(1)

    if args.num_large_context is not None and args.num_large_context < 0:
        print("Error: --num-large-context must be non-negative", file=sys.stderr)
        sys.exit(1)

    if args.large_context_len <= 0:
        print("Error: --large-context-len must be positive", file=sys.stderr)
        sys.exit(1)

    generate_large_context_prompts(
        num_conversations=args.num_conversations,
        messages_per_conversation=args.messages_per_conv,
        context_len_per_message=args.context_len,
        new_message_len=args.new_msg_len,
        large_context_prob=args.large_context_prob,
        num_large_context=args.num_large_context,
        large_context_len=args.large_context_len,
        output_file=args.output,
    )


if __name__ == "__main__":
    main()
