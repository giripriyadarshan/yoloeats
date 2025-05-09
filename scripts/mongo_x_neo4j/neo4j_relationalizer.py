import os
import re
import logging
import csv
from pymongo import MongoClient
from dotenv import load_dotenv
from unidecode import unidecode
from tqdm import tqdm

load_dotenv()

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

MONGO_URI = os.getenv("MONGO_URI")
MONGO_DB_NAME = "openfoods"
MONGO_COLLECTION_NAME = "openfoodfacts_products"

OUTPUT_TSV_FILE = "neo4j_bulk_data.tsv"
CSV_HEADER = ["LineType", "ID", "Name", "Label", "RelationshipType", "FromID", "FromLabel", "ToID", "ToLabel"]

KNOWN_ALLERGENS = {
    "en:milk", "en:eggs", "en:fish", "en:crustaceans", "en:molluscs",
    "en:peanuts", "en:nuts", "en:soybeans", "en:gluten", "en:celery",
    "en:mustard", "en:sesame-seeds", "en:sulphur-dioxide-and-sulphites", "en:lupin"
}

INGREDIENT_TO_ALLERGEN_MAP = {
    r"\bmilk\b": "en:milk", r"\bbutter\b": "en:milk", r"\bcheese\b": "en:milk",
    r"\bcream\b": "en:milk", r"\byogurt\b": "en:milk", r"\bcasein(?:ate)?\b": "en:milk",
    r"\bwhey\b": "en:milk", r"\blactose\b": "en:milk",
    r"\begg(s)?\b": "en:eggs", r"\bovalbumin\b": "en:eggs", r"\blysozyme\b": "en:eggs",
    r"\balbumin\b": "en:eggs",
    r"\bfish\b": "en:fish", r"\bsalmon\b": "en:fish", r"\btuna\b": "en:fish", r"\bcod\b": "en:fish",
    r"\banchovy\b": "en:fish", r"\btrout\b": "en:fish", r"\bhaddock\b": "en:fish",
    r"\bshrimp\b": "en:crustaceans", r"\bprawn(s)?\b": "en:crustaceans", r"\bcrab\b": "en:crustaceans",
    r"\blobster\b": "en:crustaceans", r"\bcrayfish\b": "en:crustaceans", r"\bkrill\b": "en:crustaceans",
    r"\bmollusc(s)?\b": "en:molluscs", r"\bmussel(s)?\b": "en:molluscs", r"\boyster(s)?\b": "en:molluscs",
    r"\bsquid\b": "en:molluscs", r"\boctopus\b": "en:molluscs", r"\bsnail(s)?\b": "en:molluscs",
    r"\bclam(s)?\b": "en:molluscs", r"\bscallop(s)?\b": "en:molluscs",
    r"\bpeanut(s)?\b": "en:peanuts", r"\barachis\b": "en:peanuts",
    r"\bnut(s)?\b": "en:nuts",
    r"\balmond(s)?\b": "en:nuts", r"\bhazelnut(s)?\b": "en:nuts", r"\bwalnut(s)?\b": "en:nuts",
    r"\bcashew(s)?\b": "en:nuts", r"\bpecan(s)?\b": "en:nuts", r"\bbrazil nut(s)?\b": "en:nuts",
    r"\bpistachio(s)?\b": "en:nuts", r"\bmacadamia(s)?\b": "en:nuts", r"\bqueensland nut(s)?\b": "en:nuts",
    r"\bsoy\b": "en:soybeans", r"\bsoya\b": "en:soybeans", r"\blecithin\b": "en:soybeans",
    r"\btofu\b": "en:soybeans", r"\bedamame\b": "en:soybeans", r"\bmiso\b": "en:soybeans",
    r"\btempeh\b": "en:soybeans", r"\bbean curd\b": "en:soybeans",
    r"\bwheat\b": "en:gluten", r"\bgluten\b": "en:gluten", r"\bbarley\b": "en:gluten",
    r"\brye\b": "en:gluten", r"\boat(s)?\b": "en:gluten",
    r"\bspelt\b": "en:gluten", r"\bkamut\b": "en:gluten", r"\bkhorasan wheat\b": "en:gluten",
    r"\bsemolina\b": "en:gluten", r"\bdurum\b": "en:gluten", r"\bcouscous\b": "en:gluten",
    r"\btriticale\b": "en:gluten", r"\bflour\b": "en:gluten",
    r"\bcelery\b": "en:celery", r"\bceleriac\b": "en:celery",
    r"\bmustard\b": "en:mustard",
    r"\bsesame\b": "en:sesame-seeds", r"\btahini\b": "en:sesame-seeds",
    r"\bsulphite(s)?\b": "en:sulphur-dioxide-and-sulphites",
    r"\bsulfite(s)?\b": "en:sulphur-dioxide-and-sulphites",
    r"\bsulphur dioxide\b": "en:sulphur-dioxide-and-sulphites",
    r"\bsulfur dioxide\b": "en:sulphur-dioxide-and-sulphites",
    r"\bE22[0-8]\b": "en:sulphur-dioxide-and-sulphites",
    r"\blupin(s)?\b": "en:lupin",
}

DIETARY_PREFERENCES_MAP = {
    "vegan": {"en:vegan", "vegan"},
    "vegetarian": {"en:vegetarian", "vegetarian"},
    "gluten_free": {"en:gluten-free", "gluten-free", "sans gluten"},
    "lactose_free": {"en:lactose-free", "lactose-free", "sans lactose"},
}

DIETARY_CONFLICT_MAP = {
    "vegan": {
        "en:non-vegan", "en:milk", "en:eggs", "en:fish", "en:crustaceans", "en:molluscs",
        "en:meat", "en:dairy", "en:honey", "en:collagen", "en:gelatin", "en:cheese"
    },
    "vegetarian": {
        "en:non-vegetarian", "en:fish", "en:crustaceans", "en:molluscs", "en:meat",
        "en:collagen", "en:gelatin"
    },
    "gluten_free": {"en:gluten"},
    "lactose_free": {"en:milk", "en:lactose"},
}


def normalize_ingredient_name(name):
    if not name:
        return None
    name = name.lower()
    name = unidecode(name)
    name = re.sub(r'[\(\[].*?[\)\]]', '', name)
    name = re.sub(r'[^\w\s-]', '', name)
    name = re.sub(r'\s+', ' ', name).strip()
    return name if name else None


def parse_ingredients_from_text(ingredients_text_str):
    if not ingredients_text_str:
        return set()
    raw_ingredients = re.split(r',\s*(?![^()]*\))', ingredients_text_str)
    normalized_ingredients = set()
    for item in raw_ingredients:
        item_clean = item.split(':')[0]  # Remove language prefixes like "en:"
        item_clean = item_clean.split('–')[0]  # Remove text after em-dash (often details)
        # Remove percentages like (25.5%) or 25.5% at the end of an ingredient
        item_clean = re.sub(r'\s*\(\s*\d+(\.\d+)?\s*%\s*\)\s*$', '', item_clean.strip()).strip()
        item_clean = re.sub(r'\s*\d+(\.\d+)?\s*%\s*$', '', item_clean.strip()).strip()
        normalized = normalize_ingredient_name(item_clean)
        if normalized:
            normalized_ingredients.add(normalized)
    return normalized_ingredients


def clean_tag(tag):
    if not isinstance(tag, str):
        return None
    return tag.strip().lower()


def generate_csv_data(mongo_collection, output_filename):
    fields_to_fetch = {
        "code": 1,
        "product_name": 1, "product_name_en": 1, "generic_name": 1, "generic_name_en": 1,
        "ingredients_text": 1, "ingredients_text_en": 1,
        "allergens_tags": 1,
        "traces_tags": 1,
        "labels_tags": 1,
    }
    mongo_query = {
        "$and": [
            {"code": {"$exists": True, "$ne": "", "$ne": None}},
            {"$or": [
                {"ingredients_text": {"$exists": True, "$ne": ""}},
                {"ingredients_text_en": {"$exists": True, "$ne": ""}},
                {"allergens_tags": {"$exists": True, "$ne": []}},
                {"traces_tags": {"$exists": True, "$ne": []}},
                {"labels_tags": {"$exists": True, "$ne": []}},
            ]}
        ]
    }

    total_products = mongo_collection.count_documents(mongo_query)
    logging.info(f"Found {total_products} products to process in MongoDB for CSV generation.")
    if total_products == 0:
        logging.info("No products found matching the criteria. Exiting CSV generation.")
        return

    products_cursor = mongo_collection.find(mongo_query, fields_to_fetch)


    written_ingredients = set()
    written_allergens = set()
    written_diet_prefs = set()

    try:
        with open(output_filename, 'w', newline='', encoding='utf-8') as tsvfile:
            writer = csv.writer(tsvfile, delimiter='\t', quoting=csv.QUOTE_MINIMAL)
            writer.writerow(CSV_HEADER)

            for allergen_name in KNOWN_ALLERGENS:
                if allergen_name not in written_allergens:
                    writer.writerow(["Node", allergen_name, "", "Allergen", "", "", "", "", ""])
                    written_allergens.add(allergen_name)
            logging.info(f"Wrote {len(written_allergens)} predefined Allergen nodes to TSV.")

            for diet_name in DIETARY_PREFERENCES_MAP.keys():
                if diet_name not in written_diet_prefs:
                    writer.writerow(["Node", diet_name, "", "DietaryPreference", "", "", "", "", ""])
                    written_diet_prefs.add(diet_name)
            logging.info(f"Wrote {len(written_diet_prefs)} predefined DietaryPreference nodes to TSV.")

            processed_count = 0
            missing_code_skipped = 0

            for product_doc in tqdm(products_cursor, total=total_products, unit="product", desc="Generating TSV rows"):
                product_code = product_doc.get("code")
                if not product_code or not isinstance(product_code, str) or product_code.strip() == "":
                    logging.warning(f"Skipping product due to missing/invalid code: {product_doc.get('_id')}")
                    missing_code_skipped += 1
                    continue

                product_name = (
                        product_doc.get("product_name_en")
                        or product_doc.get("product_name")
                        or product_doc.get("generic_name_en")
                        or product_doc.get("generic_name")
                        or f"Product {product_code}"
                )

                writer.writerow(["Node", product_code, product_name, "Product", "", "", "", "", ""])

                ingredients_text_str = product_doc.get("ingredients_text_en") or product_doc.get("ingredients_text", "")
                parsed_ingredient_names = parse_ingredients_from_text(ingredients_text_str)

                for ing_name in parsed_ingredient_names:
                    if ing_name not in written_ingredients:
                        writer.writerow(["Node", ing_name, "", "Ingredient", "", "", "", "", ""])
                        written_ingredients.add(ing_name)

                    writer.writerow(
                        ["Relationship", "", "", "", "HAS_INGREDIENT", product_code, "Product", ing_name, "Ingredient"])

                    for keyword_pattern, allergen_tag_value in INGREDIENT_TO_ALLERGEN_MAP.items():
                        if re.search(keyword_pattern, ing_name, re.IGNORECASE):
                            if allergen_tag_value in KNOWN_ALLERGENS:
                                writer.writerow(["Relationship", "", "", "", "IS_ALLERGEN", ing_name, "Ingredient",
                                                 allergen_tag_value, "Allergen"])

                    for diet_pref_name, conflicting_allergen_tags_for_diet in DIETARY_CONFLICT_MAP.items():
                        is_conflicting_ingredient = False
                        for keyword_pattern, mapped_allergen_from_ingredient in INGREDIENT_TO_ALLERGEN_MAP.items():
                            if re.search(keyword_pattern, ing_name, re.IGNORECASE):
                                if mapped_allergen_from_ingredient in conflicting_allergen_tags_for_diet:
                                    is_conflicting_ingredient = True
                                    break
                        if is_conflicting_ingredient:
                            writer.writerow(["Relationship", "", "", "", "CONFLICTS_WITH_DIET", ing_name, "Ingredient",
                                             diet_pref_name, "DietaryPreference"])

                explicit_product_allergens = set()
                allergens_tags_raw = product_doc.get("allergens_tags", [])
                if isinstance(allergens_tags_raw, list):
                    for tag in allergens_tags_raw:
                        cleaned_tag = clean_tag(tag)
                        if cleaned_tag and cleaned_tag in KNOWN_ALLERGENS:
                            explicit_product_allergens.add(cleaned_tag)
                elif isinstance(allergens_tags_raw, str):
                    for tag_part in allergens_tags_raw.split(','):
                        cleaned_tag = clean_tag(tag_part)
                        if cleaned_tag and cleaned_tag in KNOWN_ALLERGENS:
                            explicit_product_allergens.add(cleaned_tag)

                for allergen_name in explicit_product_allergens:
                    is_explained_by_ingredient = False
                    for ing_name in parsed_ingredient_names:
                        for keyword_pattern, mapped_allergen in INGREDIENT_TO_ALLERGEN_MAP.items():
                            if re.search(keyword_pattern, ing_name, re.IGNORECASE) and mapped_allergen == allergen_name:
                                is_explained_by_ingredient = True
                                break
                        if is_explained_by_ingredient:
                            break

                    if not is_explained_by_ingredient:
                        proxy_ingredient_name = f"{allergen_name}_source_for_{product_code}"

                        if proxy_ingredient_name not in written_ingredients:
                            writer.writerow(["Node", proxy_ingredient_name, "", "Ingredient", "", "", "", "", ""])
                            written_ingredients.add(proxy_ingredient_name)

                        writer.writerow(["Relationship", "", "", "", "HAS_INGREDIENT", product_code, "Product",
                                         proxy_ingredient_name, "Ingredient"])
                        writer.writerow(["Relationship", "", "", "", "IS_ALLERGEN", proxy_ingredient_name, "Ingredient",
                                         allergen_name, "Allergen"])

                traces_tags_data = product_doc.get("traces_tags", [])
                processed_traces_allergens = set()
                if isinstance(traces_tags_data, str):
                    traces_tags_data = [t.strip() for t in traces_tags_data.split(',') if t.strip()]

                if isinstance(traces_tags_data, list):
                    for trace_tag_raw in traces_tags_data:
                        trace_allergen_name = clean_tag(trace_tag_raw)
                        if trace_allergen_name and trace_allergen_name in KNOWN_ALLERGENS:
                            processed_traces_allergens.add(trace_allergen_name)

                for trace_allergen_name in processed_traces_allergens:
                    writer.writerow(["Relationship", "", "", "", "MAY_CONTAIN_ALLERGEN", product_code, "Product",
                                     trace_allergen_name, "Allergen"])

                labels_tags_data = product_doc.get("labels_tags", [])
                product_dietary_labels = set()

                if isinstance(labels_tags_data, str):
                    labels_tags_data = [t.strip() for t in labels_tags_data.split(',') if t.strip()]

                if isinstance(labels_tags_data, list):
                    for label_tag_raw in labels_tags_data:
                        cleaned_label = clean_tag(label_tag_raw)
                        if cleaned_label:
                            product_dietary_labels.add(cleaned_label)

                suitable_diet_prefs_for_product = set()
                for diet_name_key, diet_keywords_set in DIETARY_PREFERENCES_MAP.items():
                    if not diet_keywords_set.isdisjoint(
                            product_dietary_labels):
                        suitable_diet_prefs_for_product.add(diet_name_key)

                for diet_name in suitable_diet_prefs_for_product:
                    writer.writerow(["Relationship", "", "", "", "IS_SUITABLE_FOR", product_code, "Product", diet_name,
                                     "DietaryPreference"])

                processed_count += 1

            logging.info(f"\nFinished generating TSV. Total products processed: {processed_count}")
            if missing_code_skipped > 0:
                logging.warning(f"Skipped {missing_code_skipped} products due to missing/invalid codes.")

    except IOError as e:
        logging.error(f"Error writing to TSV file {output_filename}: {e}", exc_info=True)
    except Exception as e:
        logging.error(f"An unexpected error occurred during TSV generation: {e}", exc_info=True)


if __name__ == "__main__":
    if not MONGO_URI:
        logging.error("Missing environment variable: MONGO_URI")
        exit(1)

    try:
        mongo_client = MongoClient(MONGO_URI)
        mongo_client.admin.command('ping')
        db = mongo_client[MONGO_DB_NAME]
        collection = db[MONGO_COLLECTION_NAME]
        logging.info(f"Connected to MongoDB: DB: {MONGO_DB_NAME}, Collection: {MONGO_COLLECTION_NAME}")
    except Exception as e:
        logging.error(f"MongoDB connection failed: {e}", exc_info=True)
        exit(1)

    try:
        generate_csv_data(collection, OUTPUT_TSV_FILE)
        logging.info(f"TSV file '{OUTPUT_TSV_FILE}' generated successfully.")
    finally:
        if 'mongo_client' in locals() and mongo_client:
            mongo_client.close()
            logging.info("MongoDB connection closed.")
