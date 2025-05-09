use neo4rs::Graph;
use reqwest::Client;

#[derive(Clone)]
pub struct AppState {
    pub neo4j_client: Graph,
    pub http_client: Client,
    pub user_profile_service_url: String,
    pub product_catalog_service_url: String,
}
