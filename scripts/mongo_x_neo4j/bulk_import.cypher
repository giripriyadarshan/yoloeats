CREATE CONSTRAINT IF NOT EXISTS FOR (p:Product) REQUIRE p.code IS UNIQUE;
CREATE CONSTRAINT IF NOT EXISTS FOR (i:Ingredient) REQUIRE i.name IS UNIQUE;
CREATE CONSTRAINT IF NOT EXISTS FOR (a:Allergen) REQUIRE a.name IS UNIQUE;
CREATE CONSTRAINT IF NOT EXISTS FOR (d:DietaryPreference) REQUIRE d.name IS UNIQUE;

CREATE INDEX IF NOT EXISTS FOR (p:Product) ON (p.name);
CREATE INDEX IF NOT EXISTS FOR (i:Ingredient) ON (i.name);


LOAD CSV WITH HEADERS FROM 'file:///neo4j_bulk_data.tsv' AS row FIELDTERMINATOR '\t'
CALL {
    WITH row

    FOREACH (ignore IN CASE WHEN row.LineType = 'Node' AND row.Label = 'Product' THEN [1] ELSE [] END |
        MERGE (p:Product {code: row.ID})
        ON CREATE SET
            p.name = row.Name,
            p.displayName = CASE
                                WHEN row.Name IS NOT NULL AND row.Name <> 'Unknown Product' AND row.Name <> ('Product ' + row.ID) THEN row.Name
                                ELSE row.ID
                            END
        ON MATCH SET
            p.name = row.Name,
            p.displayName = CASE
                                WHEN row.Name IS NOT NULL AND row.Name <> 'Unknown Product' AND row.Name <> ('Product ' + row.ID) THEN row.Name
                                ELSE row.ID
                            END
    )

    FOREACH (ignore IN CASE WHEN row.LineType = 'Node' AND row.Label = 'Ingredient' THEN [1] ELSE [] END |
        MERGE (i:Ingredient {name: row.ID})
    )

    FOREACH (ignore IN CASE WHEN row.LineType = 'Node' AND row.Label = 'Allergen' THEN [1] ELSE [] END |
        MERGE (a:Allergen {name: row.ID})
    )

    FOREACH (ignore IN CASE WHEN row.LineType = 'Node' AND row.Label = 'DietaryPreference' THEN [1] ELSE [] END |
        MERGE (d:DietaryPreference {name: row.ID})
    )

    FOREACH (ignore IN CASE WHEN row.LineType = 'Relationship' AND row.RelationshipType = 'HAS_INGREDIENT' THEN [1] ELSE [] END |
        MERGE (p:Product {code: row.FromID})
        MERGE (i:Ingredient {name: row.ToID})
        MERGE (p)-[:HAS_INGREDIENT]->(i)
    )

    FOREACH (ignore IN CASE WHEN row.LineType = 'Relationship' AND row.RelationshipType = 'IS_ALLERGEN' THEN [1] ELSE [] END |
        MERGE (i:Ingredient {name: row.FromID})
        MERGE (a:Allergen {name: row.ToID})
        MERGE (i)-[:IS_ALLERGEN]->(a)
    )

    FOREACH (ignore IN CASE WHEN row.LineType = 'Relationship' AND row.RelationshipType = 'MAY_CONTAIN_ALLERGEN' THEN [1] ELSE [] END |
        MERGE (p:Product {code: row.FromID})
        MERGE (a:Allergen {name: row.ToID})
        MERGE (p)-[:MAY_CONTAIN_ALLERGEN]->(a)
    )

    FOREACH (ignore IN CASE WHEN row.LineType = 'Relationship' AND row.RelationshipType = 'IS_SUITABLE_FOR' THEN [1] ELSE [] END |
        MERGE (p:Product {code: row.FromID})
        MERGE (d:DietaryPreference {name: row.ToID})
        MERGE (p)-[:IS_SUITABLE_FOR]->(d)
    )

    FOREACH (ignore IN CASE WHEN row.LineType = 'Relationship' AND row.RelationshipType = 'CONFLICTS_WITH_DIET' THEN [1] ELSE [] END |
        MERGE (ing:Ingredient {name: row.FromID})
        MERGE (diet:DietaryPreference {name: row.ToID})
        MERGE (ing)-[:CONFLICTS_WITH_DIET]->(diet)
    )

} IN TRANSACTIONS OF 5000 ROWS;