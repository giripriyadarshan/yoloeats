use crate::{
    errors::{AppError, Result},
    models::{CheckRequest, CheckResult, ProductData, SafetyStatus, UserProfileData},
    state::AppState,
};
use axum::{Json, extract::State};
use neo4rs::{Error as Neo4jError, query};
use reqwest::StatusCode;
use std::{collections::HashSet, sync::Arc};
use tracing::{debug, info, instrument, warn};

// TODO: Replace with a more robust NLP or rule-based parser
fn parse_ingredients(text: Option<String>) -> HashSet<String> {
    text.map(|s| {
        s.split(',')
            .map(|item| item.trim().to_lowercase())
            .filter(|item| !item.is_empty())
            .collect::<HashSet<String>>()
    })
    .unwrap_or_default()
}

#[instrument(skip(state, payload), fields(user_id = %payload.user_id, product = %payload.product_identifier))]
pub async fn check_product_safety(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<CheckRequest>,
) -> Result<Json<CheckResult>> {
    info!("Received safety check request");

    // TODO: Use actual user_id from payload or auth context
    let profile_url = format!("{}/api/v1/profile", state.user_profile_service_url);
    debug!("Fetching user profile from: {}", profile_url);

    let profile_resp = state.http_client.get(&profile_url).send().await?;

    let user_profile: UserProfileData = match profile_resp.status() {
        StatusCode::OK => profile_resp.json::<UserProfileData>().await.map_err(|e| {
            tracing::error!("Failed to deserialize user profile JSON: {}", e);
            AppError::ProfileProcessingError(format!("Failed to parse profile data: {}", e))
        })?,
        StatusCode::NOT_FOUND => {
            warn!("User profile not found at {}", profile_url);
            return Err(AppError::NotFoundError(format!(
                "User profile not found for user {}",
                payload.user_id
            )));
        }
        other_status => {
            let body = profile_resp.text().await.unwrap_or_default();
            tracing::error!(
                "User profile service failed with status {}: {}",
                other_status,
                body
            );
            return Err(AppError::UpstreamServiceError {
                service: "user-profile-service".to_string(),
                status: other_status.as_u16(),
            });
        }
    };
    debug!(
        "User profile fetched. Allergens: {}, Diets: {}",
        user_profile.allergens.len(),
        user_profile.dietary_prefs.len()
    );

    let product_url = format!(
        "{}/api/v1/products/barcode/{}",
        state.product_catalog_service_url, payload.product_identifier
    );
    debug!("Fetching product data from: {}", product_url);
    let product_resp = state.http_client.get(&product_url).send().await?;
    let product_data: ProductData = match product_resp.status() {
        StatusCode::OK => product_resp.json::<ProductData>().await.map_err(|e| {
            tracing::error!("Failed to deserialize product data JSON: {}", e);
            AppError::ProductProcessingError(format!("Failed to parse product data: {}", e))
        })?,
        StatusCode::NOT_FOUND => {
            warn!("Product not found at {}", product_url);
            return Err(AppError::NotFoundError(format!(
                "Product not found for identifier {}",
                payload.product_identifier
            )));
        }
        other_status => {
            let body = product_resp.text().await.unwrap_or_default();
            tracing::error!(
                "Product catalog service failed with status {}: {}",
                other_status,
                body
            );
            return Err(AppError::UpstreamServiceError {
                service: "product-catalog-service".to_string(),
                status: other_status.as_u16(),
            });
        }
    };
    debug!(
        "Product data fetched. Ingredients present: {}, Traces: {}",
        product_data.ingredients_text.is_some(),
        product_data.traces_tags.len()
    );

    let ingredients = parse_ingredients(product_data.ingredients_text);
    let trace_ingredients: HashSet<String> = product_data
        .traces_tags
        .into_iter()
        .map(|t| t.to_lowercase())
        .collect();
    let all_potential_ingredients = ingredients
        .union(&trace_ingredients)
        .cloned()
        .collect::<Vec<String>>();

    if all_potential_ingredients.is_empty() {
        warn!(
            "No ingredients found or parsed for product {}",
            payload.product_identifier
        );
        return Ok(Json(CheckResult {
            status: SafetyStatus::Caution,
            conflicting_allergens: vec![],
            conflicting_diets: vec![],
            trace_allergens: vec![],
            is_offline_result: false,
        }));
    }

    debug!("Querying Neo4j for conflicts...");
    let user_allergens: Vec<String> = user_profile.allergens.into_iter().collect();
    let user_diets: Vec<String> = user_profile.dietary_prefs.into_iter().collect();

    let cypher_query = query(
        r#"
        UNWIND $ingredients AS ingredientName
        MATCH (i:Ingredient {name: ingredientName}) // Match ingredients from the input list
        OPTIONAL MATCH (i)-[:IS_ALLERGEN]->(a:Allergen) WHERE a.name IN $userAllergens
        OPTIONAL MATCH (i)-[:MAY_CONTAIN_TRACE]->(ta:Allergen) WHERE ta.name IN $userAllergens
        OPTIONAL MATCH (i)-[:CONFLICTS_WITH_DIET]->(d:DietaryPreference) WHERE d.name IN $userDiets
        RETURN ingredientName,
               collect(DISTINCT a.name) AS conflictingAllergens,
               collect(DISTINCT ta.name) AS traceAllergens,
               collect(DISTINCT d.name) AS conflictingDiets
    "#,
    )
    .param("ingredients", all_potential_ingredients)
    .param("userAllergens", user_allergens)
    .param("userDiets", user_diets);

    let mut result_stream = state.neo4j_client.execute(cypher_query).await?;

    let mut conflicting_allergens_set = HashSet::new();
    let mut trace_allergens_set = HashSet::new();
    let mut conflicting_diets_set = HashSet::new();

    loop {
        match result_stream.next().await {
            Ok(Some(row)) => {
                let conflicts: Vec<String> = row
                    .get("conflictingAllergens")
                    .map_err(|e| AppError::Neo4jError(Neo4jError::DeserializationError(e)))?;
                let traces: Vec<String> = row
                    .get("traceAllergens")
                    .map_err(|e| AppError::Neo4jError(Neo4jError::DeserializationError(e)))?;
                let diets: Vec<String> = row
                    .get("conflictingDiets")
                    .map_err(|e| AppError::Neo4jError(Neo4jError::DeserializationError(e)))?;

                conflicting_allergens_set.extend(conflicts);
                trace_allergens_set.extend(traces);
                conflicting_diets_set.extend(diets);
            }
            Ok(None) => {
                break;
            }
            Err(e) => {
                tracing::error!("Error fetching row from Neo4j stream: {}", e);
                return Err(AppError::Neo4jError(e));
            }
        }
    }

    debug!(
        "Neo4j conflicts found - Allergens: {:?}, Traces: {:?}, Diets: {:?}",
        conflicting_allergens_set, trace_allergens_set, conflicting_diets_set
    );

    let final_status = if !conflicting_allergens_set.is_empty() || !conflicting_diets_set.is_empty()
    {
        SafetyStatus::Unsafe
    } else if !trace_allergens_set.is_empty() {
        // TODO: Factor in user_profile.risk_tolerance here
        warn!("Trace allergens found, setting status to Caution (risk tolerance not implemented)");
        SafetyStatus::Caution
    } else {
        SafetyStatus::Safe
    };
    info!("Final safety status determined: {:?}", final_status);

    let check_result = CheckResult {
        status: final_status,
        conflicting_allergens: conflicting_allergens_set.into_iter().collect(),
        conflicting_diets: conflicting_diets_set.into_iter().collect(),
        trace_allergens: trace_allergens_set.into_iter().collect(),
        is_offline_result: false,
    };

    Ok(Json(check_result))
}
