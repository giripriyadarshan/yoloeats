use crate::models::Product;
use mongodb::{Database, IndexModel, bson::doc, options::IndexOptions};
use tracing::{error, info};

pub async fn create_indexes(db: &Database) -> Result<(), mongodb::error::Error> {
    let collection = db.collection::<Product>("openfoodfacts_products");
    info!("Attempting to create indexes for 'products' collection...");

    let code_options = IndexOptions::builder().unique(true).build();
    let code_index = IndexModel::builder()
        .keys(doc! { "code": 1 }) // 1 for ascending order
        .options(code_options)
        .build();

    let text_index = IndexModel::builder()
        .keys(doc! {
            "product_name": "text",
            "generic_name": "text",
            "ingredients_text": "text",
            "brands_tags": "text"
        })
        .build();

    let categories_index = IndexModel::builder()
        .keys(doc! { "categories_tags": 1 })
        .build();
    let labels_index = IndexModel::builder()
        .keys(doc! { "labels_tags": 1 })
        .build();
    let brands_idx = IndexModel::builder()
        .keys(doc! { "brands_tags": 1 })
        .build();
    let countries_index = IndexModel::builder()
        .keys(doc! { "countries_tags": 1 })
        .build();

    let nutriscore_index = IndexModel::builder()
        .keys(doc! { "nutrition_grade_fr": 1 })
        .build();

    match collection
        .create_indexes(vec![
            code_index,
            text_index,
            categories_index,
            labels_index,
            brands_idx,
            countries_index,
            nutriscore_index,
        ])
        .await
    {
        Ok(result) => {
            info!(
                "Successfully created MongoDB indexes for 'openfoodfacts_products' collection: {:?}",
                result.index_names
            );
            Ok(())
        }
        Err(e) => {
            error!("Failed to create MongoDB indexes: {}", e);
            Err(e) // Propagate the error for handling in main.rs
        }
    }
}
