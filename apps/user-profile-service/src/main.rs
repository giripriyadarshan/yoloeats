use axum::{
    Router,
    routing::{get, post},
};
use rust_database_clients::{create_mongo_client, create_redis_client, load_config};
use std::{env, net::SocketAddr, sync::Arc};
use tracing::{error, info};
use tracing_subscriber::{EnvFilter, fmt, layer::SubscriberExt, util::SubscriberInitExt};

mod handlers;
use handlers::{create_user_profile, get_user_profile_by_id};

mod cache;
mod errors;
mod models;
mod state;
use state::AppState;

async fn root_handler() -> &'static str {
    "User Profile Service OK"
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    dotenvy::dotenv().ok();

    // Sets the default log level to "info" if RUST_LOG env var is not set
    tracing_subscriber::registry()
        .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .with(fmt::layer())
        .init();

    info!("Starting User Profile Service...");

    let (mongo_uri, redis_uri) = match load_config() {
        Ok(config) => config,
        Err(e) => {
            error!("Failed to load configuration: {}", e);
            return Err(Box::new(e) as Box<dyn std::error::Error>);
        }
    };

    let mongo_client = match create_mongo_client(&mongo_uri).await {
        Ok(client) => client,
        Err(e) => {
            error!("Failed to create MongoDB client: {}", e);
            return Err(Box::new(e) as Box<dyn std::error::Error>);
        }
    };
    info!("MongoDB client created successfully.");

    let mongo_db = mongo_client.database("yoloeats_user_profile");
    info!("Using MongoDB database: {}", mongo_db.name());

    let redis_client = match create_redis_client(&redis_uri) {
        Ok(client) => client,
        Err(e) => {
            error!("Failed to create Redis client: {}", e);
            return Err(Box::new(e) as Box<dyn std::error::Error>);
        }
    };
    info!("Redis client created successfully.");

    let app_state = Arc::new(AppState {
        mongo_db,
        redis_client,
    });

    let user_routes = Router::new()
        .route("/", post(create_user_profile)) // POST /api/v1/users
        .route("/{id}", get(get_user_profile_by_id)); // GET /api/v1/users/:id

    let app = Router::new()
        .route("/", get(root_handler)) // Health check at the root
        .nest("/api/v1/users", user_routes) // Nest user routes under /api/v1/users
        .with_state(app_state); // state

    let port_str = env::var("USER_PROFILE_SERVICE_PORT").unwrap_or_else(|_| {
        info!("USER_PROFILE_SERVICE_PORT not set, defaulting to 8001");
        "8001".to_string()
    });
    let port = port_str.parse::<u16>().unwrap_or_else(|_| {
        error!("Invalid port specified, defaulting to 8001");
        8001
    });

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    info!("Server configured to listen on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .map_err(|e| Box::new(e) as Box<dyn std::error::Error>)?;
    info!(
        "User Profile Service successfully started, listening on {}",
        addr
    );
    tracing::warn!(
        "Warning: No authentication/authorization implemented yet. Service is currently insecure."
    );
    axum::serve(listener, app.into_make_service())
        .await
        .map_err(|e| Box::new(e) as Box<dyn std::error::Error>)?;

    Ok(())
}
