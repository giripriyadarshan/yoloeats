use mongodb::Database;
use neo4rs::Graph as Neo4jClient;
use qdrant_client::Qdrant as QdrantClient;
use redis::Client as RedisClient;
use reqwest::Client as HttpClient;
use std::sync::Arc;

#[derive(Clone)]
pub struct AppState {
    pub mongo_db: Database,
    pub redis_client: RedisClient,

    pub qdrant_client: Arc<QdrantClient>,
    pub neo4j_client: Neo4jClient,
    pub http_client: HttpClient,
    pub user_profile_service_url: String,
}
