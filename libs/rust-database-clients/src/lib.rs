use mongodb::{Client as MongoClient, options::ClientOptions};
use redis::Client as RedisClient;
use redis::Commands;
use std::env;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ConfigError {
    #[error("Missing environment variable: {0}")]
    MissingVariable(String),
    #[error("Dotenv error: {0}")]
    Dotenv(#[from] dotenvy::Error),
}

#[derive(Error, Debug)]
pub enum ClientCreationError {
    #[error("MongoDB client error: {0}")]
    Mongo(#[from] mongodb::error::Error),
    #[error("Redis client error: {0}")]
    Redis(#[from] redis::RedisError),
    #[error("Configuration error: {0}")]
    Config(#[from] ConfigError),
}

pub fn load_config() -> Result<(String, String), ConfigError> {
    dotenvy::dotenv().ok();

    let mongo_uri =
        env::var("MONGO_URI").map_err(|_| ConfigError::MissingVariable("MONGO_URI".to_string()))?;
    let redis_uri =
        env::var("REDIS_URI").map_err(|_| ConfigError::MissingVariable("REDIS_URI".to_string()))?;

    Ok((mongo_uri, redis_uri))
}

pub async fn create_mongo_client(db_uri: &str) -> Result<MongoClient, mongodb::error::Error> {
    tracing::info!("Attempting to connect to MongoDB at {}", db_uri);
    let client_options = ClientOptions::parse(db_uri).await?;
    let client = MongoClient::with_options(client_options)?;
    client
        .database("admin")
        .run_command(mongodb::bson::doc! {"ping": 1})
        .await?;
    tracing::info!("Successfully connected to MongoDB.");
    Ok(client)
}

pub fn create_redis_client(redis_uri: &str) -> Result<RedisClient, redis::RedisError> {
    tracing::info!("Creating Redis client for URI: {}", redis_uri);
    let client = RedisClient::open(redis_uri)?;
    let mut con = client.get_connection()?;
    // Test the connection by pinging Redis
    let _: () = con.ping()?;
    tracing::info!("Successfully connected to Redis.");
    tracing::info!("Successfully created Redis client.");
    Ok(client)
}

#[cfg(test)]
mod tests {

    use super::*;
    #[test]
    fn config_loading_requires_env_vars() {
        let result = load_config();
        assert!(result.is_err());
        if let Err(ConfigError::MissingVariable(_)) = result {
            // Expected error type
        } else {
            panic!("Expected MissingVariable error, got {:?}", result);
        }
    }

    #[test]
    fn can_create_redis_client() {
        let result = create_redis_client("redis://127.0.0.1/");
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn can_create_mongo_client() {
        // This requires a MongoDB instance running
        // and MONGO_URI env var set.
        match load_config() {
            Ok((mongo_uri, _)) => {
                let result = create_mongo_client(&mongo_uri).await;
                assert!(result.is_ok());
            }
            Err(_) => {
                // Skip test or fail if config loading is essential for the test setup
                println!("Skipping MongoDB client test due to missing config.");
            }
        }
    }
}
