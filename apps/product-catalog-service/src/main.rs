use axum::{
    Router,
    routing::{get, post},
};
use dotenvy::dotenv;
use rust_database_clients::{create_mongo_client, create_redis_client, load_config};
use std::{env, net::SocketAddr, sync::Arc};
use tracing::{error, info, warn};
use tracing_subscriber::{EnvFilter, fmt, layer::SubscriberExt, util::SubscriberInitExt};

mod db_setup;
mod errors;
mod handlers;
mod models;
mod state;

use errors::ServiceError;
use state::AppState;

use crate::handlers::{
    create_product, delete_product, get_product_by_barcode, get_product_by_id, search_products,
    update_product,
};

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
    let db_handle = mongo_client.database("yoloeats_catalog");
    let redis_client_handle = create_redis_client(&redis_uri)?;
    info!("Database connections established.");

    db_setup::create_indexes(&db_handle).await?;
    info!("MongoDB indexes checked/created successfully.");

    let app_state = Arc::new(AppState {
        mongo_db: db_handle,
        redis_client: redis_client_handle,
    });
    info!("Application state created.");

    let api_routes = Router::new()
        .route("/", post(create_product))
        .route("/search", get(search_products))
        .route(
            "/:id",
            get(get_product_by_id)
                .put(update_product)
                .delete(delete_product),
        )
        .route("/barcode/:code", get(get_product_by_barcode));

    let app = Router::new()
        .nest("/api/v1/products", api_routes)
        .route("/", get(|| async { "Product Catalog Service OK" }))
        // TODO: Add CORS layer here in the next step
        .with_state(app_state);

    info!("Axum router configured with API routes.");

    let port_str = env::var("PRODUCT_CATALOG_SERVICE_PORT").unwrap_or_else(|_| {
        info!("PRODUCT_CATALOG_SERVICE_PORT not set, defaulting to 8002");
        "8002".to_string()
    });
    let port = port_str.parse::<u16>().unwrap_or_else(|_| {
        error!("Invalid port '{}' specified, defaulting to 8002", port_str);
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
