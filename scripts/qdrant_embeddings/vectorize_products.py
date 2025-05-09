import os
import sys
import logging
import uuid
from dotenv import load_dotenv
from pymongo import MongoClient
from qdrant_client import QdrantClient
from qdrant_client.http.models import Distance, VectorParams, PointStruct, PayloadSchemaType
from qdrant_client.http.exceptions import UnexpectedResponse
from sentence_transformers import SentenceTransformer
from tqdm import tqdm
from typing import List, Dict, Any

# --- Configuration ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

load_dotenv()

MONGO_URI = os.getenv("MONGO_URI")
MONGO_DB_NAME = os.getenv("MONGO_DB_NAME", "yoloeats_catalog")
MONGO_COLLECTION_NAME = os.getenv("MONGO_COLLECTION_NAME", "products")
QDRANT_URL = os.getenv("QDRANT_URL", "http://localhost:6333")
QDRANT_API_KEY = os.getenv("QDRANT_API_KEY") # Can be None
QDRANT_COLLECTION_NAME = os.getenv("QDRANT_COLLECTION_NAME", "product_vectors")
EMBEDDING_MODEL_NAME = os.getenv("EMBEDDING_MODEL_NAME", "all-MiniLM-L6-v2")
try:
    VECTOR_DIMENSION = int(os.getenv("VECTOR_DIMENSION", "384"))
except ValueError:
    logging.error("Invalid VECTOR_DIMENSION in .env file. Must be an integer.")
    sys.exit(1)

VECTOR_DISTANCE = Distance.COSINE
BATCH_SIZE = 100
NAMESPACE_UUID = uuid.NAMESPACE_DNS

def connect_mongodb() -> MongoClient:
    """Establishes connection to MongoDB."""
    if not MONGO_URI:
        logging.error("MONGO_URI not found in environment variables.")
        sys.exit(1)
    try:
        logging.info(f"Connecting to MongoDB...")
        client = MongoClient(MONGO_URI)
        client.admin.command('ismaster')
        logging.info("MongoDB connection successful.")
        return client
    except Exception as e:
        logging.error(f"Failed to connect to MongoDB: {e}")
        sys.exit(1)

def connect_qdrant() -> QdrantClient:
    """Establishes connection to Qdrant."""
    try:
        logging.info(f"Connecting to Qdrant at {QDRANT_URL}...")
        client = QdrantClient(url=QDRANT_URL, api_key=QDRANT_API_KEY, timeout=60)
        client.get_collections()
        logging.info("Qdrant connection successful.")
        return client
    except Exception as e:
        logging.error(f"Failed to connect to Qdrant: {e}")
        sys.exit(1)

def setup_qdrant_collection(client: QdrantClient):
    """
    Ensures the Qdrant collection exists with the specified configuration.
    If it doesn't exist, it creates it. Also creates payload indexes.
    """
    try:
        collection_name = QDRANT_COLLECTION_NAME
        logging.info(f"Checking if Qdrant collection '{collection_name}' exists...")

        exists = client.collection_exists(collection_name=collection_name)

        if exists:
            logging.info(f"Collection '{collection_name}' already exists.")
            try:
                collection_info = client.get_collection(collection_name=collection_name)
                current_distance = getattr(getattr(collection_info.vectors_config, 'params', None), 'distance', None)
                current_dim = getattr(getattr(collection_info.vectors_config, 'params', None), 'size', None)

                if current_distance is None or current_dim is None:
                     logging.warning(f"Could not retrieve full vector configuration for existing collection '{collection_name}'. Skipping detailed config check.")
                elif current_distance != VECTOR_DISTANCE or current_dim != VECTOR_DIMENSION:
                    logging.warning(f"Collection '{collection_name}' exists but has mismatched configuration!")
                    logging.warning(f"  Expected: Distance={VECTOR_DISTANCE}, Dim={VECTOR_DIMENSION}")
                    logging.warning(f"  Found:    Distance={current_distance}, Dim={current_dim}")
                    logging.warning("  Consider manually deleting the collection via Qdrant UI/API and rerunning the script if the configuration MUST be updated.")
                else:
                    logging.info(f"Existing collection '{collection_name}' configuration matches.")
            except Exception as e:
                 logging.warning(f"Could not verify configuration of existing collection '{collection_name}': {e}")

        if not exists:
            logging.info(f"Collection '{collection_name}' does not exist. Creating...")
            client.create_collection(
                collection_name=collection_name,
                vectors_config=VectorParams(size=VECTOR_DIMENSION, distance=VECTOR_DISTANCE),
            )
            logging.info(f"Collection '{collection_name}' created successfully.")

        filterable_fields = [
            "category_tags", "brand_tags", "traces_tags", "labels_tags", "code"
        ]
        logging.info(f"Ensuring payload indexes exist for fields: {', '.join(filterable_fields)}")
        for field in filterable_fields:
             try:
                client.create_payload_index(
                    collection_name=collection_name,
                    field_name=field,
                    field_schema=PayloadSchemaType.KEYWORD
                )
             except UnexpectedResponse as e:
                 if e.status_code == 409:
                     logging.debug(f"Index for '{field}' likely already exists or creation in progress (HTTP 409).")
                 elif e.status_code == 400:
                      logging.warning(f"Bad request creating index for '{field}' (HTTP 400): {e}")
                 else:
                     logging.warning(f"Could not ensure index for '{field}'. Status Code: {e.status_code}. Response: {e}")
             except Exception as e:
                 logging.warning(f"Could not ensure index for '{field}'. Error: {e}")
        logging.info("Payload index setup complete.")

    except Exception as e:
        logging.error(f"Failed during Qdrant collection setup: {e}")
        sys.exit(1)


def create_embedding_text(product: Dict[str, Any]) -> str:
    """Combines relevant product fields into a single string for embedding."""
    name = product.get('product_name', '') or product.get('generic_name', '')
    categories = ' '.join(product.get('categories_tags', []) or [])
    brands = ' '.join(product.get('brands_tags', []) or [])
    ingredients = product.get('ingredients_text', '') or ''
    labels = ' '.join(product.get('labels_tags', []) or [])

    parts = [
        f"Product: {name}" if name else "",
        f"Categories: {categories}" if categories else "",
        f"Brands: {brands}" if brands else "",
        f"Labels: {labels}" if labels else "",
        f"Ingredients: {ingredients}" if ingredients else ""
    ]
    text_to_embed = " ".join(filter(None, parts)).strip()
    return text_to_embed if text_to_embed else "product information unavailable"

def main():
    logging.info("Starting offline data processing for Qdrant...")

    mongo_client = connect_mongodb()
    qdrant_client = connect_qdrant()
    try:
        logging.info(f"Loading sentence transformer model: '{EMBEDDING_MODEL_NAME}'...")
        embedding_model = SentenceTransformer(EMBEDDING_MODEL_NAME)
        logging.info("Sentence transformer model loaded successfully.")
    except Exception as e:
        logging.error(f"Failed to load sentence transformer model: {e}")
        if mongo_client:
            mongo_client.close()
        sys.exit(1)

    if not mongo_client or not qdrant_client:
         logging.error("Database connection failed. Exiting.")
         sys.exit(1)

    try:
        setup_qdrant_collection(qdrant_client)

        db = mongo_client[MONGO_DB_NAME]
        collection = db[MONGO_COLLECTION_NAME]

        logging.info(f"Fetching products from MongoDB collection '{MONGO_DB_NAME}.{MONGO_COLLECTION_NAME}'...")
        projection = {
            "_id": 1, "code": 1, "product_name": 1, "generic_name": 1,
            "ingredients_text": 1, "categories_tags": 1, "brands_tags": 1,
            "traces_tags": 1, "labels_tags": 1,
        }

        try:
            total_products = collection.count_documents({})
            logging.info(f"Found {total_products} products to process.")
        except Exception as e:
            logging.error(f"Failed to count documents in MongoDB: {e}")
            total_products = 0

        if total_products == 0:
            logging.warning("No products found in the MongoDB collection or failed to count. Exiting.")
            return

        mongo_cursor = collection.find({}, projection=projection)
        points_batch: List[PointStruct] = []
        processed_count = 0

        with tqdm(total=total_products, desc="Processing products", unit="product") as pbar:
            for product in mongo_cursor:
                try:
                    mongo_object_id = product.get('_id')
                    if not mongo_object_id:
                        logging.warning(f"Skipping product missing '_id': {product.get('code', 'N/A')}")
                        pbar.update(1)
                        continue
                    mongo_oid_str = str(mongo_object_id)

                    try:
                        point_id_uuid = uuid.uuid5(NAMESPACE_UUID, mongo_oid_str)
                        point_id = str(point_id_uuid)
                    except Exception as e:
                        logging.error(f"Failed to generate UUID for ObjectId string '{mongo_oid_str}': {e}. Skipping.")
                        pbar.update(1)
                        continue

                    text_to_embed = create_embedding_text(product)

                    try:
                        vector = embedding_model.encode(text_to_embed).tolist()
                    except Exception as encode_err:
                        logging.error(f"Error encoding text for product ID {point_id} (MongoID: {mongo_oid_str}): {encode_err}. Skipping.")
                        pbar.update(1)
                        continue

                    payload = {
                        "product_name": product.get('product_name') or product.get('generic_name', 'N/A'),
                        "code": product.get('code', 'N/A'),
                        "category_tags": product.get('categories_tags', []) or [],
                        "brand_tags": product.get('brands_tags', []) or [],
                        "traces_tags": product.get('traces_tags', []) or [],
                        "labels_tags": product.get('labels_tags', []) or [],
                    }
                    for key in ["category_tags", "brand_tags", "traces_tags", "labels_tags"]:
                        payload[key] = [str(item) for item in payload[key] if item is not None]

                    point = PointStruct(
                        id=point_id,
                        vector=vector,
                        payload=payload
                    )
                    points_batch.append(point)

                    if len(points_batch) >= BATCH_SIZE:
                        qdrant_client.upsert(
                            collection_name=QDRANT_COLLECTION_NAME,
                            points=points_batch,
                            wait=True
                        )
                        processed_count += len(points_batch)
                        points_batch = []

                except Exception as proc_err:
                    mongo_oid_str_err = str(product.get('_id', 'Unknown MongoID'))
                    logging.error(f"Error processing product MongoID {mongo_oid_str_err}: {proc_err}", exc_info=True)

                finally:
                     pbar.update(1)

            if points_batch:
                qdrant_client.upsert(
                    collection_name=QDRANT_COLLECTION_NAME,
                    points=points_batch,
                    wait=True
                )
                processed_count += len(points_batch)
                logging.info(f"Upserted final batch of {len(points_batch)} points.")

        logging.info(f"--- Qdrant Vectorization Complete ---")
        logging.info(f"Total products processed and attempted upsert: {processed_count}")

    except Exception as e:
        logging.error(f"An error occurred during the main processing loop: {e}", exc_info=True)
    finally:
        if mongo_client:
            logging.info("Closing MongoDB connection.")
            mongo_client.close()
        logging.info("Script finished.")


if __name__ == "__main__":
    main()