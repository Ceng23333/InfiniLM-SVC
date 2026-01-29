from flask import Flask, request, jsonify
import logging
import time
import sys
from datetime import datetime
from pathlib import Path
app = Flask(__name__)
from transformers import AutoModel, AutoModelForSequenceClassification, AutoTokenizer, LlamaTokenizer
import torch
import numpy as np

# Configure logging
log_file = f"embeddings_server_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_file),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

@app.before_request
def log_request_info():
    logger.info(f"Request: {request.method} {request.url} from {request.remote_addr}")

@app.after_request
def log_response_info(response):
    logger.info(f"Response: {response.status_code}")
    return response

embedding_model_name = "/workspace/models/MiniCPM-Embedding-Light"
logger.info(f"Loading embedding model: {embedding_model_name}")
tokenizer = LlamaTokenizer.from_pretrained(embedding_model_name, trust_remote_code=True, local_files_only=True)
embedding_model = AutoModel.from_pretrained(embedding_model_name, trust_remote_code=True, torch_dtype=torch.float16, local_files_only=True).to("cuda")
embedding_model.eval()
logger.info("Embedding model loaded successfully")

@app.route("/v1/embeddings", methods=["POST"])
def embeddings():
    """
    OpenAI-compatible embeddings endpoint.
    Accepts: {"model": "model-name", "input": "text" or ["text1", "text2"], "encoding_format": "float" (optional)}
    Returns: OpenAI-compatible response format
    """
    start_time = time.time()
    try:
        if not request.json:
            return jsonify({"error": {"message": "Request body must be JSON", "type": "invalid_request_error"}}), 400

        # Parse OpenAI-compatible request
        model_name = request.json.get("model", "text-embedding-ada-002")
        input_data = request.json.get("input")
        encoding_format = request.json.get("encoding_format", "float")

        if input_data is None:
            return jsonify({"error": {"message": "Missing required parameter: input", "type": "invalid_request_error"}}), 400

        # Handle both string and list inputs
        if isinstance(input_data, str):
            texts = [input_data]
        elif isinstance(input_data, list):
            texts = input_data
        else:
            return jsonify({"error": {"message": "input must be a string or array of strings", "type": "invalid_request_error"}}), 400

        logger.info(f"Embedding request - model: {model_name}, texts count: {len(texts)}")

        # Use encode_corpus for document embeddings (OpenAI doesn't distinguish query/doc)
        # If you need query-specific encoding, you could check a custom parameter or use encode_query
        embeddings_dense, embeddings_sparse = embedding_model.encode_corpus(texts, return_sparse_vectors=True)

        # Convert to numpy array if needed
        if isinstance(embeddings_dense, torch.Tensor):
            embeddings_dense = embeddings_dense.cpu().numpy()

        processing_time = time.time() - start_time
        logger.info(f"Processing time: {processing_time:.3f}s")

        # Build OpenAI-compatible response
        response_data = []
        for idx, embedding in enumerate(embeddings_dense):
            embedding_list = embedding.tolist()
            response_data.append({
                "object": "embedding",
                "embedding": embedding_list,
                "index": idx
            })

        # Estimate token usage (rough approximation)
        total_tokens = sum(len(text.split()) * 1.3 for text in texts)  # Rough token estimate

        response = {
            "object": "list",
            "data": response_data,
            "model": model_name,
            "usage": {
                "prompt_tokens": int(total_tokens),
                "total_tokens": int(total_tokens)
            }
        }

        return jsonify(response)

    except Exception as e:
        processing_time = time.time() - start_time
        logger.error(f"Error processing embedding request: {str(e)}, processing time: {processing_time:.3f}s")
        return jsonify({"error": {"message": str(e), "type": "server_error"}}), 500

# Keep the old endpoint for backward compatibility
@app.route("/embedding", methods=["GET", "POST"])
def emb():
    start_time = time.time()
    try:
        embedding_type: str = request.json["embedding_type"]
        texts: list[str] = request.json["texts"]
        logger.info(f"Embedding request - type: {embedding_type}, texts count: {len(texts)}")

        if embedding_type == "query":
            embeddings_dense, embeddings_sparse = embedding_model.encode_query(texts, return_sparse_vectors=True)
        elif embedding_type == "doc":
            embeddings_dense, embeddings_sparse = embedding_model.encode_corpus(texts, return_sparse_vectors=True)
        else:
            logger.error(f"Invalid embedding type: {embedding_type}")
            return {"error": "Invalid embedding type"}, 400

        processing_time = time.time() - start_time
        logger.info(f"Processing time: {processing_time:.3f}s")

        return {"dense_embeddings": embeddings_dense.tolist(), "sparse_embeddings": embeddings_sparse}

    except Exception as e:
        processing_time = time.time() - start_time
        logger.error(f"Error: {str(e)}, processing time: {processing_time:.3f}s")
        return {"error": str(e)}, 500


rerank_model_name = "/workspace/models/MiniCPM-Reranker-Light"
logger.info(f"Loading reranking model: {rerank_model_name}")
rerank_tokenizer = LlamaTokenizer.from_pretrained(rerank_model_name, trust_remote_code=True, local_files_only=True)
rerank_model = AutoModelForSequenceClassification.from_pretrained(rerank_model_name, trust_remote_code=True, torch_dtype=torch.float16, local_files_only=True).to("cuda")
rerank_model.eval()
logger.info("Reranking model loaded successfully")

@app.route("/rerank", methods=["GET", "POST"])
def rerank():
    start_time = time.time()
    try:
        query: str = request.json["query"]
        passages: list[str] = request.json["passages"]
        logger.info(f"Rerank request - query length: {len(query)}, passages count: {len(passages)}")

        rerank_score = rerank_model.rerank(query, passages,query_instruction="Query:", batch_size=32, max_length=8000)

        processing_time = time.time() - start_time
        logger.info(f"Processing time: {processing_time:.3f}s")

        return rerank_score.tolist()

    except Exception as e:
        processing_time = time.time() - start_time
        logger.error(f"Error: {str(e)}, processing time: {processing_time:.3f}s")
        return {"error": str(e)}, 500



bcepath = "/workspace/models/bce-reranker-base_v1"
logger.info(f"Loading BCE reranker model: {bcepath}")
bce_tokenizer = AutoTokenizer.from_pretrained(bcepath, local_files_only=True)
bce_model = AutoModelForSequenceClassification.from_pretrained(bcepath, local_files_only=True)

device = 'cuda'  # if no GPU, set "cpu"
bce_model.to(device)
logger.info("BCE reranker model loaded successfully")

@app.route("/rerankbce", methods=["GET", "POST"])
def rerankbce():
    start_time = time.time()
    try:
        query: str = request.json["query"]
        passages: list[str] = request.json["passages"]
        logger.info(f"BCE rerank request - query length: {len(query)}, passages count: {len(passages)}")

        # get inputs
        sentence_pairs = [[query, passage] for passage in passages]
        inputs = bce_tokenizer(sentence_pairs, padding=True, truncation=True, max_length=512, return_tensors="pt")
        inputs_on_device = {k: v.to(device) for k, v in inputs.items()}

        # calculate scores
        scores = bce_model(**inputs_on_device, return_dict=True).logits.view(-1,).float()
        scores = torch.sigmoid(scores)

        processing_time = time.time() - start_time
        logger.info(f"Processing time: {processing_time:.3f}s")

        return scores.tolist()

    except Exception as e:
        processing_time = time.time() - start_time
        logger.error(f"Error: {str(e)}, processing time: {processing_time:.3f}s")
        return {"error": str(e)}, 500


if __name__ == "__main__":
    logger.info("Starting Flask server...")
    logger.info("Available endpoints:")
    logger.info("  POST /v1/embeddings - OpenAI-compatible embeddings endpoint")
    logger.info("  POST /embedding - Legacy embeddings endpoint (backward compatibility)")
    logger.info("  POST /rerank - Rerank passages using MiniCPM model")
    logger.info("  POST /rerankbce - Rerank passages using BCE model")
    logger.info("Server will run on host=0.0.0.0, port=20002")

    try:
        app.run(host="0.0.0.0", port=20002, debug=True, use_reloader=False)
    except KeyboardInterrupt:
        logger.info("Server shutdown requested by user")
    except Exception as e:
        logger.error(f"Server error: {e}")
    finally:
        logger.info("Server stopped")
