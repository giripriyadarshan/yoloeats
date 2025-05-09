use axum::{Router, routing::get};
use handlers::{get_allergens, get_profile, update_profile};
use rust_database_clients::{create_mongo_client, create_redis_client, load_config};
use state::AppState;
use std::{env, net::SocketAddr, sync::Arc};
use tower_http::cors::{Any, CorsLayer};
use tracing::{error, info, warn};
use tracing_subscriber::{EnvFilter, fmt, layer::SubscriberExt, util::SubscriberInitExt};

mod errors;
mod handlers;
mod models;
mod state;

async fn root_handler() -> &'static str {
    "User Profile Service OK V2"
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    dotenvy::dotenv().ok();

    tracing_subscriber::registry()
        .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .with(fmt::layer())
        .init();

    info!("Starting User Profile Service (V2)...");

    let (mongo_uri, redis_uri) = load_config().map_err(|e| {
        error!("Config loading failed: {}", e);
        Box::new(e) as Box<dyn std::error::Error>
    })?;

    let mongo_client = create_mongo_client(&mongo_uri).await.map_err(|e| {
        error!("Mongo connection failed: {}", e);
        Box::new(e) as Box<dyn std::error::Error>
    })?;
    info!("MongoDB client created successfully.");
    let mongo_db = mongo_client.database("yoloeats_user_profile");
    info!("Using MongoDB database: {}", mongo_db.name());

    let redis_client = create_redis_client(&redis_uri).map_err(|e| {
        error!("Redis connection failed: {}", e);
        Box::new(e) as Box<dyn std::error::Error>
    })?;
    info!("Redis client created successfully.");

    let app_state = Arc::new(AppState {
        mongo_db,
        redis_client,
    });

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let user_profile_routes =
        Router::new().route("/{user_id}/profile", get(get_profile).put(update_profile));

    let allergen_routes = Router::new().route("/", get(get_allergens));

    let app = Router::new()
        .route("/", get(root_handler))
        .nest("/api/v1/users", user_profile_routes)
        .nest("/api/v1/allergens", allergen_routes)
        .layer(cors)
        .with_state(app_state);

    let port_str = env::var("USER_PROFILE_SERVICE_PORT").unwrap_or_else(|_| "8001".to_string());
    let port = port_str.parse::<u16>().unwrap_or(8001);
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    info!("Server configured to listen on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    warn!(
        "Warning: Authentication not implemented. User ID in path is currently not validated against an authenticated principal."
    );
    info!(
        "User Profile Service (V2) successfully started, listening on {}",
        addr
    );

    axum::serve(listener, app.into_make_service()).await?;

    Ok(())
}
