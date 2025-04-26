use axum::{routing::get, Router};
use dotenvy::dotenv;
use rust_database_clients::{create_mongo_client, create_redis_client, load_config};
use std::{env, net::SocketAddr, sync::Arc};
use axum::routing::post;
use tracing::{error, info, warn};
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

use crate::handlers::{
    get_product_by_id, get_product_by_barcode, search_products,
    create_product, update_product, delete_product
};

mod db_setup;
mod errors;
mod models;
mod state;
mod handlers;

use errors::ServiceError;
use state::AppState;

async fn health_check() -> &'static str {
    "Product Catalog Service OK"
}

#[tokio::main]
async fn main() -> Result<(), ServiceError> {
    dotenv().ok();

    tracing_subscriber::registry()
        .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .with(fmt::layer())
        .init();

    info!("Starting Product Catalog Service...");

    let (mongo_uri, redis_uri) = load_config()?;

    let mongo_client = create_mongo_client(&mongo_uri).await?;
    info!("Successfully connected to MongoDB.");

    let db_handle = mongo_client.database("yoloeats_catalog");
    info!("Using MongoDB database: {}", db_handle.name());

    let redis_client_handle = create_redis_client(&redis_uri)?;
    info!("Successfully connected to Redis.");

    info!("Attempting to create MongoDB indexes...");
    db_setup::create_indexes(&db_handle).await?;
    info!("MongoDB indexes checked/created successfully.");

    let app_state = Arc::new(AppState {
        mongo_db: db_handle,
        redis_client: redis_client_handle,
    });
    info!("Application state created.");

    let product_routes = Router::new()
        .route("/", post(create_product).get(search_products))
        .route("/id/:id", get(get_product_by_id).patch(update_product).delete(delete_product))
        .route("/barcode/:code", get(get_product_by_barcode));

    let app = Router::new()
        .route("/", get(health_check))
        .nest("/api/v1/products", product_routes)
        .with_state(app_state);

    info!("Axum router configured.");

    let port_str = env::var("PRODUCT_CATALOG_SERVICE_PORT").unwrap_or_else(|_| {
        info!("PRODUCT_CATALOG_SERVICE_PORT not set, defaulting to 8002");
        "8002".to_string()
    });
    let port = port_str.parse::<u16>().unwrap_or_else(|_| {
        error!(
            "Invalid port '{}' specified, defaulting to 8002",
            port_str
        );
        8002
    });

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    info!("Server configured to listen on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .map_err(ServiceError::Io)?;

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