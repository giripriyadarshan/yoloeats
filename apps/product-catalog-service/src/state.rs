use mongodb::Database;
use redis::Client as RedisClient;

#[derive(Clone)]
pub struct AppState {
    pub mongo_db: Database,
    pub redis_client: RedisClient,
}
