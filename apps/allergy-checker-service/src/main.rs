use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router, routing::post};
use dotenvy::dotenv;
use neo4rs::Graph;
use reqwest::Client;
use std::{env, net::SocketAddr, sync::Arc};
use tower_http::cors::{Any, CorsLayer};
use tracing::{info, warn};
use tracing_subscriber::{EnvFilter, fmt, layer::SubscriberExt, util::SubscriberInitExt};

mod errors;
mod handlers;
mod models;
mod state;

use errors::Result;
use state::AppState;

async fn check_product_safety(
    State(_state): State<Arc<AppState>>,
    Json(_payload): Json<models::CheckRequest>,
) -> Result<Json<models::CheckResult>> {
    warn!("'/api/v1/check' endpoint hit, but handler logic not implemented yet.");
    Ok(Json(models::CheckResult {
        status: models::SafetyStatus::Caution,
        conflicting_allergens: vec!["Not Implemented".to_string()],
        conflicting_diets: vec![],
        trace_allergens: vec![],
        is_offline_result: true,
    }))
}

async fn health_check() -> &'static str {
    "Allergy Checker Service OK"
}

#[tokio::main]
async fn main() -> std::result::Result<(), Box<dyn std::error::Error>> {
    dotenv().ok();

    tracing_subscriber::registry()
        .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .with(fmt::layer())
        .init();

    info!("Starting Allergy Checker Service...");

    let neo4j_uri = env::var("NEO4J_URI").expect("NEO4J_URI must be set");
    let neo4j_user = env::var("NEO4J_USER").unwrap_or_else(|_| "neo4j".to_string());
    let neo4j_password = env::var("NEO4J_PASSWORD").expect("NEO4J_PASSWORD must be set");
    let user_profile_service_url = env::var("USER_PROFILE_SERVICE_URL")
        .unwrap_or_else(|_| "http://user-profile-service:8001".to_string());
    let product_catalog_service_url = env::var("PRODUCT_CATALOG_SERVICE_URL")
        .unwrap_or_else(|_| "http://product-catalog-service:8002".to_string());
    let port_str = env::var("ALLERGY_CHECKER_SERVICE_PORT").unwrap_or_else(|_| "8003".to_string());
    let port = port_str.parse::<u16>().unwrap_or(8003);

    info!("Neo4j URI: {}", neo4j_uri);
    info!("User Profile Service URL: {}", user_profile_service_url);
    info!(
        "Product Catalog Service URL: {}",
        product_catalog_service_url
    );

    let http_client = Client::new();
    info!("Reqwest HTTP client created.");

    let neo4j_client = Graph::new(&neo4j_uri, &neo4j_user, &neo4j_password).await?;
    info!("Neo4j client connected successfully.");

    let app_state = Arc::new(AppState {
        neo4j_client,
        http_client,
        user_profile_service_url,
        product_catalog_service_url,
    });
    info!("Application state created.");

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);
    info!("CORS layer configured (permissive).");

    let app = Router::new()
        .route("/", get(health_check))
        .route("/api/v1/check", post(check_product_safety))
        .layer(cors)
        .with_state(app_state);
    info!("Axum router configured.");

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    info!("Server configured to listen on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    warn!("Warning: No authentication/authorization implemented yet.");
    info!(
        "Allergy Checker Service successfully started, listening on {}",
        addr
    );

    axum::serve(listener, app.into_make_service()).await?;
    Ok(())
}
