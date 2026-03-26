#!/usr/bin/env node

/**
 * Validates JSON schema files in /schemas and optionally validates
 * data files against their schemas.
 *
 * Usage:
 *   node scripts/validate-schemas.js                    # validate all schemas are valid JSON Schema
 *   node scripts/validate-schemas.js data.json schema   # validate data.json against a named schema
 *
 * Examples:
 *   node scripts/validate-schemas.js runs/PROJ-123/PRD.json prd
 *   node scripts/validate-schemas.js runs/PROJ-123/REVIEW.json review
 */

const fs = require("fs");
const path = require("path");

const SCHEMAS_DIR = path.resolve(__dirname, "..", "schemas");

const SCHEMA_FILES = [
  "prd.schema.json",
  "review.schema.json",
  "feedback.schema.json",
  "conflict.schema.json",
  "repair.schema.json",
  "secrets.schema.json",
  "agent-learning.schema.json",
  "local-ticket.schema.json",
];

function loadSchema(filename) {
  const filepath = path.join(SCHEMAS_DIR, filename);
  const raw = fs.readFileSync(filepath, "utf-8");
  return JSON.parse(raw);
}

function validateSchemaStructure(filename, schema) {
  const errors = [];

  if (!schema.$schema) {
    errors.push("missing $schema");
  }
  if (!schema.$id) {
    errors.push("missing $id");
  }
  if (!schema.title) {
    errors.push("missing title");
  }
  if (!schema.description) {
    errors.push("missing description");
  }
  if (schema.type !== "object") {
    errors.push("root type must be 'object'");
  }
  if (!schema.required || !Array.isArray(schema.required)) {
    errors.push("missing required array");
  }
  if (schema.additionalProperties !== false) {
    errors.push("root additionalProperties should be false");
  }

  // Check all $ref targets resolve
  const refs = findRefs(schema);
  for (const ref of refs) {
    if (ref.startsWith("#/$defs/")) {
      const defName = ref.replace("#/$defs/", "");
      if (!schema.$defs || !schema.$defs[defName]) {
        errors.push(`unresolved $ref: ${ref}`);
      }
    }
  }

  return errors;
}

function findRefs(obj, refs = []) {
  if (obj && typeof obj === "object") {
    if (obj.$ref) {
      refs.push(obj.$ref);
    }
    for (const value of Object.values(obj)) {
      findRefs(value, refs);
    }
  }
  return refs;
}

function validateDataAgainstSchema(dataPath, schemaName) {
  const schemaFile = `${schemaName}.schema.json`;
  if (!SCHEMA_FILES.includes(schemaFile)) {
    console.error(`Unknown schema: ${schemaName}`);
    console.error(`Available: ${SCHEMA_FILES.map((f) => f.replace(".schema.json", "")).join(", ")}`);
    process.exit(1);
  }

  let data;
  try {
    const raw = fs.readFileSync(path.resolve(dataPath), "utf-8");
    data = JSON.parse(raw);
  } catch (err) {
    console.error(`Failed to read ${dataPath}: ${err.message}`);
    process.exit(1);
  }

  const schema = loadSchema(schemaFile);

  // Basic structural validation (required fields, types)
  const errors = validateRequired(data, schema, "root");
  if (errors.length === 0) {
    console.log(`PASS  ${dataPath} validates against ${schemaName}`);
  } else {
    console.error(`FAIL  ${dataPath} against ${schemaName}:`);
    errors.forEach((e) => console.error(`  - ${e}`));
    process.exit(1);
  }
}

function validateRequired(data, schema, path) {
  const errors = [];

  if (schema.required) {
    for (const field of schema.required) {
      if (!(field in data)) {
        errors.push(`${path}: missing required field '${field}'`);
      }
    }
  }

  if (schema.properties && typeof data === "object" && data !== null) {
    for (const [key, value] of Object.entries(data)) {
      const propSchema = schema.properties[key];
      if (!propSchema && schema.additionalProperties === false) {
        errors.push(`${path}: unexpected field '${key}'`);
      }
    }
  }

  return errors;
}

// --- Main ---

function main() {
  const args = process.argv.slice(2);

  // Mode: validate data file against schema
  if (args.length === 2) {
    validateDataAgainstSchema(args[0], args[1]);
    return;
  }

  // Mode: validate all schema files
  console.log("Validating schema files...\n");
  let allPassed = true;

  for (const file of SCHEMA_FILES) {
    const filepath = path.join(SCHEMAS_DIR, file);

    if (!fs.existsSync(filepath)) {
      console.error(`FAIL  ${file} — file not found`);
      allPassed = false;
      continue;
    }

    let schema;
    try {
      schema = loadSchema(file);
    } catch (err) {
      console.error(`FAIL  ${file} — invalid JSON: ${err.message}`);
      allPassed = false;
      continue;
    }

    const errors = validateSchemaStructure(file, schema);
    if (errors.length === 0) {
      console.log(`PASS  ${file}`);
    } else {
      console.error(`FAIL  ${file}`);
      errors.forEach((e) => console.error(`  - ${e}`));
      allPassed = false;
    }
  }

  console.log();
  if (allPassed) {
    console.log(`All ${SCHEMA_FILES.length} schemas valid.`);
  } else {
    console.error("Some schemas failed validation.");
    process.exit(1);
  }
}

main();
