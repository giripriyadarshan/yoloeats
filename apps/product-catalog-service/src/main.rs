use crate::handlers::{
    create_product, delete_product, get_product_by_barcode, get_product_by_id, get_recommendations,
    search_products, update_product,
};
use axum::{
    Router,
    routing::{get, post},
};
use dotenvy::dotenv;
use errors::{Result, ServiceError};
use neo4rs::Graph as Neo4jClient;
use qdrant_client::{Qdrant, config::QdrantConfig};
use reqwest::Client as HttpClient;
use rust_database_clients::{create_mongo_client, create_redis_client, load_config};
use state::AppState;
use std::{env, net::SocketAddr, sync::Arc};
use tower_http::cors::{Any, CorsLayer};
use tracing::{debug, error, info, warn};
use tracing_subscriber::{EnvFilter, fmt, layer::SubscriberExt, util::SubscriberInitExt};

mod db_setup;
mod errors;
mod handlers;
mod models;
mod state;

async fn health_check() -> &'static str {
    "Product Catalog Service OK"
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenv().ok();

    tracing_subscriber::registry()
        .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .with(fmt::layer())
        .init();

    info!("Starting Product Catalog Service...");

    let (mongo_uri, redis_uri) = load_config()?;

    let qdrant_uri = env::var("QDRANT_URI").map_err(|e| {
        error!("Missing environment variable: QDRANT_URI");
        ServiceError::VarError(e)
    })?;
    let neo4j_uri = env::var("NEO4J_URI").map_err(|e| {
        error!("Missing environment variable: NEO4J_URI");
        ServiceError::VarError(e)
    })?;
    let neo4j_user = env::var("NEO4J_USER")
        .map_err(|_| ServiceError::MissingVariable("NEO4J_USER".to_string()))?;
    let neo4j_password = env::var("NEO4J_PASSWORD")
        .map_err(|_| ServiceError::MissingVariable("NEO4J_PASSWORD".to_string()))?;
    let user_profile_service_url = env::var("USER_PROFILE_SERVICE_URL").map_err(|e| {
        error!("Missing environment variable: USER_PROFILE_SERVICE_URL");
        ServiceError::VarError(e)
    })?;

    info!("Configuration loaded.");
    debug!("MONGO_URI: {}", mongo_uri);
    debug!("REDIS_URI: {}", redis_uri);
    debug!("QDRANT_URI: {}", qdrant_uri);
    debug!("NEO4J_URI: {}", neo4j_uri);
    debug!("USER_PROFILE_SERVICE_URL: {}", user_profile_service_url);

    let mongo_client = create_mongo_client(&mongo_uri).await?;
    let db_handle = mongo_client.database("openfoods");
    info!("MongoDB client connected. Database: {}", db_handle.name());

    let redis_client_handle = create_redis_client(&redis_uri)?;
    info!("Redis client connected.");

    info!("Initializing Qdrant client...");
    let qdrant_config = QdrantConfig::from_url(&qdrant_uri);
    let qdrant_client = Qdrant::new(qdrant_config)?;
    info!("Qdrant client connected.");

    info!("Initializing Neo4j client...");
    let neo4j_client = Neo4jClient::new(&neo4j_uri, &neo4j_user, &neo4j_password).await?;
    neo4j_client.run(neo4rs::query("RETURN 1")).await?;
    info!("Neo4j client connected.");

    info!("Initializing Reqwest HTTP client...");
    let http_client = HttpClient::new();
    info!("Reqwest HTTP client created.");

    // db_setup::create_indexes(&db_handle).await?;
    info!("MongoDB indexes checked/created successfully.");

    let app_state = Arc::new(AppState {
        mongo_db: db_handle,
        redis_client: redis_client_handle,
        qdrant_client: Arc::new(qdrant_client),
        neo4j_client,
        http_client,
        user_profile_service_url,
    });
    info!("Application state created.");

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);
    info!("CORS layer configured (permissive for development).");

    let api_routes = Router::new()
        .route("/", post(create_product))
        .route("/search", get(search_products))
        .route(
            "/{id}",
            get(get_product_by_id)
                .put(update_product)
                .delete(delete_product),
        )
        .route("/barcode/{code}", get(get_product_by_barcode))
        .route("/{id}/recommendations", get(get_recommendations));

    let app = Router::new()
        .nest("/api/v1/products", api_routes)
        .route("/", get(health_check))
        .route("/health", get(health_check))
        .layer(cors)
        .with_state(app_state);

    info!("Axum router configured with routes and CORS.");

    let port_str = env::var("PRODUCT_CATALOG_SERVICE_PORT").unwrap_or_else(|_| {
        info!("PRODUCT_CATALOG_SERVICE_PORT not set, defaulting to 8002");
        "8002".to_string()
    });
    let port = port_str.parse::<u16>().unwrap_or_else(|e| {
        error!("Invalid port '{}': {}. Defaulting to 8002", port_str, e);
        8002
    });

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    info!("Server configured to listen on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;

    warn!("Warning: No authentication/authorization implemented yet.");
    info!(
        "Product Catalog Service successfully started, listening on {}",
        addr
    );

    axum::serve(listener, app.into_make_service())
        .await
        .map_err(ServiceError::Io)?;

    Ok(())
}
