# YOLOEATS

YOLOEATS is a comprehensive food technology application designed to help users make informed decisions about food products. It features multi-modal product scanning (barcode, object detection, ingredient OCR), personalized allergy and dietary preference checking, robust product search, and intelligent recommendations.

## Key Features

* **Mobile Application (Flutter):**
    * **Multi-Modal Scanning:**
        * **Barcode Scanning:** Quickly retrieve product details by scanning barcodes.
        * **Object Detection (YOLO):** Identify packaged food items in real-time using the device camera.
        * **Ingredient OCR:** Scan and extract text from ingredient lists for automated analysis.
    * **Personalized Profiles:** Manage user allergies, dietary preferences (e.g., vegan, vegetarian, gluten-free), and risk tolerance levels.
    * **Product Information:** Access detailed product data, including name, brand, quantity, images, ingredients, categories, labels, and nutritional information (like Nutri-Score).
    * **Safety Check:** Receive immediate feedback on whether a product aligns with your defined allergies and dietary restrictions.
    * **Product Search:** Efficiently find products by name, brand, category, or other criteria.
    * **Recommendations:** Discover suitable alternative products based on your preferences and safety requirements.
* **Backend Services (Rust):**
    * **User Profile Service:** Manages user-specific data, including profiles, allergens, and dietary preferences.
    * **Product Catalog Service:** Provides access to an extensive product database, supporting detailed product information, search, and recommendations.
    * **Allergy Checker Service:** Assesses product suitability against user profiles by analyzing ingredient relationships and allergen information.
* **Data Processing & Enrichment:**
    * Automated Python scripts for building and maintaining knowledge graphs in Neo4j (from sources like OpenFoodFacts) and generating vector embeddings for products in Qdrant to power semantic search and recommendations.

## Architecture Overview

The YOLOEATS platform is built upon a microservices architecture with a Flutter-based mobile frontend.

* **Frontend:**
    * `yoloeats_app`: A cross-platform mobile application built with Flutter.
* **Backend Services (Rust):**
    * `user-profile-service`: Handles all user-related data.
    * `product-catalog-service`: Manages the product data, powers search and recommendations.
    * `allergy-checker-service`: Performs the core logic for checking product safety against user profiles.
* **Databases & Storage:**
    * **MongoDB:** Serves as the primary data store for product information (e.g., from OpenFoodFacts) and user profiles.
    * **Qdrant:** A vector database used for storing product embeddings to enable semantic search and similarity-based recommendations.
    * **Neo4j:** A graph database employed to model complex relationships between products, ingredients, allergens, and dietary preferences, crucial for the allergy checking logic.
    * **Redis:** Acts as a caching layer for the backend services to improve performance.
* **Message Queue:**
    * **RabbitMQ:** Included in the infrastructure setup, likely for asynchronous tasks or inter-service communication.
* **Data Pipelines:**
    * Python scripts facilitate ETL processes, such as transforming and loading data from MongoDB into Neo4j and generating embeddings for Qdrant.

## Technologies Used

* **Frontend:** Flutter, Dart
* **Backend:** Rust (likely using web frameworks like Actix or Axum)
* **Databases:** MongoDB, Qdrant, Neo4j, Redis
* **AI/ML:**
    * Object Detection: YOLO (via TFLite in the Flutter app)
    * Text Embeddings: Sentence Transformers
    * OCR: Google ML Kit Text Recognition
* **Containerization:** Docker, Docker Compose
* **Scripting:** Python
* **Key Libraries & Frameworks:**
    * **Flutter:** `flutter_riverpod`, `hive`, `camera`, `tflite_flutter`, `mobile_scanner`, `permission_handler`, `dio`, `google_mlkit_text_recognition`, `equatable`, `image`, `collection`.
    * **Python:** `pymongo`, `qdrant-client`, `sentence-transformers`, `python-dotenv`, `tqdm`, `unidecode`.
    * **Rust:** `mongodb`, `redis`, `neo4rs`, `qdrant-client` (Rust version), `reqwest`, `tokio`, `serde`, `chrono`, `dotenvy`, `tracing`, `axum`, `validator`. (Deduced from Cargo.toml files within service apps and shared lib)

## Prerequisites

* Git
* Docker & Docker Compose
* Flutter SDK (Version: `^3.7.2` or compatible)
* Rust Toolchain (Cargo)
* Python 3.x
* Environment-specific `.env` files for configuration.

## Getting Started

Follow these steps to set up and run the YOLOEATS project:

1.  **Clone the Repository:**
    ```bash
    git clone [https://github.com/giripriyadarshan/yoloeats.git](https://github.com/giripriyadarshan/yoloeats.git)
    cd yoloeats
    ```

2.  **Environment Configuration:**
    This project relies heavily on `.env` files for configuring service connections, API keys, and other parameters. You'll need to create these files in several locations.

    * **Root Directory (`./.env` for Docker Compose):**
        Create a `.env` file in the project's root directory. This file is primarily used by `docker-compose.yaml`.
        Example:
        ```env
        MONGO_ROOT_USER=admin
        MONGO_ROOT_PASS=secret
        NEO4J_PASSWORD=your_neo4j_password # Choose a strong password
        RABBITMQ_USER=guest
        RABBITMQ_PASS=guest

        # Database URIs (primarily for services if they were run outside Docker, but good to define)
        # These might be overridden by service-specific .env files
        MONGO_URI=mongodb://admin:secret@mongodb:27017/
        REDIS_URI=redis://redis:6379
        QDRANT_URI=http://qdrant:6333 # Qdrant URL for backend services
        NEO4J_URI=bolt://neo4j:7687

        # Service URLs (adjust if not using Docker default networking or for local dev)
        USER_PROFILE_SERVICE_URL=http://localhost:8001
        PRODUCT_CATALOG_SERVICE_URL=http://localhost:8002
        ALLERGY_CHECKER_SERVICE_URL=http://localhost:8003

        # Python Scripts Configuration (can also be in script-specific .env)
        MONGO_DB_NAME_PYTHON=yoloeats_catalog # Or 'openfoods' if using raw OFF data for scripts
        MONGO_COLLECTION_NAME_PYTHON=products
        QDRANT_URL_PYTHON=http://localhost:6333 # Qdrant URL for Python scripts
        QDRANT_COLLECTION_NAME_PYTHON=product_vectors
        EMBEDDING_MODEL_NAME=all-MiniLM-L6-v2
        VECTOR_DIMENSION=384
        ```

    * **Backend Services (`apps/<service-name>/.env`):**
        Each Rust backend service (`user-profile-service`, `product-catalog-service`, `allergy-checker-service`) requires its own `.env` file.
        Example for `apps/user-profile-service/.env`:
        ```env
        MONGO_URI=mongodb://admin:secret@localhost:27017/yoloeats_user_profile # Connect to MongoDB via localhost if running service locally
        # Or if service runs in Docker: MONGO_URI=mongodb://admin:secret@mongodb:27017/yoloeats_user_profile
        REDIS_URI=redis://localhost:6379 # Or redis://redis:6379 if service in Docker
        USER_PROFILE_SERVICE_PORT=8001
        # Add other required vars like JWT_SECRET if auth is implemented
        ```
        Create similar `.env` files for `product-catalog-service` and `allergy-checker-service`, ensuring URIs point to the correct Docker services (e.g., `mongodb`, `redis`, `qdrant`, `neo4j`) or `localhost` if running services directly.

    * **Python Scripts (`scripts/qdrant_embeddings/.env` and `scripts/mongo_x_neo4j/.env`):**
        The Python scripts also need environment variables.
        Example for `scripts/qdrant_embeddings/.env`:
        ```env
        MONGO_URI=mongodb://admin:secret@localhost:27017/ # Or your MongoDB instance
        MONGO_DB_NAME=yoloeats_catalog # Or 'openfoods' if that's your raw data DB
        MONGO_COLLECTION_NAME=products
        QDRANT_URL=http://localhost:6333 # URL for Qdrant service
        # QDRANT_API_KEY= # Optional, if Qdrant is secured
        QDRANT_COLLECTION_NAME=product_vectors
        EMBEDDING_MODEL_NAME=all-MiniLM-L6-v2
        VECTOR_DIMENSION=384
        ```
        Configure similarly for `scripts/mongo_x_neo4j/.env` (primarily `MONGO_URI`, `MONGO_DB_NAME`).

3.  **Launch Infrastructure with Docker Compose:**
    Ensure Docker is running and your root `.env` file is configured.
    ```bash
    docker-compose up -d
    ```
    This command starts: MongoDB, Redis, Qdrant, Neo4j, and RabbitMQ.

4.  **Data Preparation and Seeding (Crucial Initial Step):**

    * **Populate MongoDB (Source Data):**
        * This project expects product data (e.g., from OpenFoodFacts) to be present in a MongoDB database. The scripts reference `openfoods.openfoodfacts_products` and `yoloeats_catalog.products`.
        * **Action Required:** You will need to source this data and import it into your MongoDB instance (the one running in Docker). Specify the database and collection names in the script `.env` files accordingly.

    * **Run Neo4j Relationalizer Script:**
        This script processes data from MongoDB and generates a TSV file for Neo4j import.
        ```bash
        cd scripts/mongo_x_neo4j
        # Ensure .env in this directory (or ../.env) is configured for MongoDB access.
        python -m venv venv
        source venv/bin/activate # On Windows: venv\Scripts\activate
        pip install -r ../qdrant_embeddings/requirements.txt # Assuming shared or create specific requirements
        # Relevant requirements: pymongo, python-dotenv, unidecode, tqdm
        python neo4j_relationalizer.py
        deactivate
        ```
        **Importing data into Neo4j:**
        1.  The script generates `neo4j_bulk_data.tsv`.
        2.  Copy this file to the Neo4j import directory: `sudo cp neo4j_bulk_data.tsv ../../neo4j_data/import/` (Adjust path/permissions as needed). The `neo4j_data/import` volume is mapped in `docker-compose.yaml`.
        3.  Use the Neo4j Browser (http://localhost:7474) or `cypher-shell` to load the data using `LOAD CSV` commands tailored to the structure of your TSV. Alternatively, for very large datasets, use the `neo4j-admin database import` tool (this would require adapting the script to produce specific CSV formats for nodes and relationships).

    * **Run Qdrant Vectorization Script:**
        This script creates vector embeddings for products and stores them in Qdrant.
        ```bash
        cd scripts/qdrant_embeddings
        # Ensure .env in this directory (or ../.env) is configured for MongoDB and Qdrant.
        python -m venv venv
        source venv/bin/activate # On Windows: venv\Scripts\activate
        pip install -r requirements.txt
        python vectorize_products.py
        deactivate
        ```

5.  **Build and Run Backend Services:**
    For each Rust service (`user-profile-service`, `product-catalog-service`, `allergy-checker-service`):
    ```bash
    cd apps/<service-name>
    # Ensure .env file in this directory is correctly configured to connect to
    # Dockerized databases (e.g., MONGO_URI=mongodb://admin:secret@localhost:27017/...)
    # and other services (e.g., USER_PROFILE_SERVICE_URL=http://localhost:8001 for product-catalog-service)
    cargo build --release
    cargo run --release
    ```
    *Note: Consider creating Dockerfiles for each Rust service and adding them to `docker-compose.yaml` for easier management.*

6.  **Build and Run Flutter App:**
    ```bash
    cd apps/yoloeats_app
    flutter pub get

    # IMPORTANT: Update API Endpoints
    # Ensure lib/providers/api_service_providers.dart has the correct base URLs
    # for your running backend services (e.g., http://localhost:8001 for user-profile-service).
    # If running the app on an Android emulator, use [http://10.0.2.2](http://10.0.2.2):<port> to refer to localhost services.
    # If running on a physical device, ensure the device can reach the machine hosting the services
    # via its network IP address.

    flutter run
    ```

## Project Structure
```
yoloeats/
├── apps/
│   ├── yoloeats_app/                # Flutter Mobile Application
│   │   ├── android/
│   │   ├── ios/
│   │   ├── lib/                     # Core Dart code (models, providers, services, views)
│   │   │   ├── data/                # Repositories, data sources (local/remote)
│   │   │   ├── models/              # Data models (Product, UserProfile, etc.)
│   │   │   ├── providers/           # Riverpod providers
│   │   │   ├── services/            # Business logic services (OCR, TFLite)
│   │   │   └── views/               # UI (screens, widgets, painters)
│   │   ├── assets/                  # ML models (yoloeats_v1.tflite), labels
│   │   └── pubspec.yaml
│   ├── product-catalog-service/    # Rust Backend Service
│   │   └── src/
│   ├── user-profile-service/       # Rust Backend Service
│   │   └── src/
│   └── allergy-checker-service/    # Rust Backend Service
│       └── src/
├── libs/
│   └── rust-database-clients/    # Shared Rust library for DB connections
│       └── src/
├── scripts/
│   ├── qdrant_embeddings/          # Python script for product vectorization
│   │   ├── vectorize_products.py
│   │   └── requirements.txt
│   └── mongo_x_neo4j/              # Python script for Neo4j data preparation
│       └── neo4j_relationalizer.py
├── docker-compose.yaml             # Defines and runs multi-container Docker applications
├── .env.example                    # Example environment file (recommend creating this)
└── README.md                       # This file
```

## API Endpoints

The backend services expose the following RESTful API endpoints (refer to individual service code or documentation for detailed request/response schemas):

* **User Profile Service (`user-profile-service`):**
    * `GET /api/v1/users/{user_id}/profile`: Retrieve user profile.
    * `PUT /api/v1/users/{user_id}/profile`: Create or update user profile.
    * `GET /api/v1/allergens`: Get a list of common allergens.
* **Product Catalog Service (`product-catalog-service`):**
    * `POST /api/v1/products`: Create a new product.
    * `GET /api/v1/products/search`: Search for products (supports query params like `q`, `category`, `brand`, `allergens`, `diets`).
    * `GET /api/v1/products/{id}`: Get product by its MongoDB ObjectId.
    * `PUT /api/v1/products/{id}`: Update product by its MongoDB ObjectId.
    * `DELETE /api/v1/products/{id}`: Delete product by its MongoDB ObjectId.
    * `GET /api/v1/products/barcode/{code}`: Get product by its barcode.
    * `GET /api/v1/products/{id}/recommendations`: Get personalized product recommendations.
* **Allergy Checker Service (`allergy-checker-service`):**
    * `POST /api/v1/check`: Check a product's safety against a user's profile. Expects `productIdentifier` and `userId` in the request body.
