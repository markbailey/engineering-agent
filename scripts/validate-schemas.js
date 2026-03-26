#!/usr/bin/env node

/**
 * Validates JSON schema files in /schemas and optionally validates
 * data files against their schemas using AJV 2020-12.
 *
 * Usage:
 *   node scripts/validate-schemas.js                    # validate all schemas compile
 *   node scripts/validate-schemas.js data.json schema   # validate data.json against a named schema
 *
 * Examples:
 *   node scripts/validate-schemas.js runs/PROJ-123/PRD.json prd
 *   node scripts/validate-schemas.js runs/PROJ-123/REVIEW.json review
 */

const fs = require("fs");
const path = require("path");
const { Ajv2020, addFormats } = require("./ajv-bundle.js");

const SCHEMAS_DIR = path.resolve(__dirname, "..", "schemas");

function createAjv() {
  const ajv = new Ajv2020({ allErrors: true, strict: false });
  addFormats(ajv);
  return ajv;
}

function discoverSchemas() {
  return fs
    .readdirSync(SCHEMAS_DIR)
    .filter((f) => f.endsWith(".schema.json"))
    .sort();
}

function loadJSON(filepath) {
  return JSON.parse(fs.readFileSync(filepath, "utf-8"));
}

// --- Mode 1: validate all schema files compile ---

function validateAllSchemas() {
  const files = discoverSchemas();
  const errors = [];
  const ajv = createAjv();

  for (const file of files) {
    const filepath = path.join(SCHEMAS_DIR, file);
    try {
      const schema = loadJSON(filepath);
      ajv.compile(schema);
    } catch (err) {
      errors.push({ schema: file, message: err.message });
    }
  }

  const result = {
    valid: errors.length === 0,
    schemas_checked: files.length,
    errors,
  };

  process.stdout.write(JSON.stringify(result, null, 2) + "\n");
  process.exit(result.valid ? 0 : 1);
}

// --- Mode 2: validate data file against named schema ---

function validateData(dataPath, schemaName) {
  const schemaFile = `${schemaName}.schema.json`;
  const schemaPath = path.join(SCHEMAS_DIR, schemaFile);

  if (!fs.existsSync(schemaPath)) {
    const available = discoverSchemas().map((f) => f.replace(".schema.json", ""));
    const result = {
      valid: false,
      errors: [
        {
          path: "",
          message: `Unknown schema: ${schemaName}. Available: ${available.join(", ")}`,
        },
      ],
    };
    process.stdout.write(JSON.stringify(result, null, 2) + "\n");
    process.exit(1);
  }

  const resolvedDataPath = path.resolve(dataPath);
  let data;
  try {
    data = loadJSON(resolvedDataPath);
  } catch (err) {
    const result = {
      valid: false,
      errors: [{ path: "", message: `Failed to read ${dataPath}: ${err.message}` }],
    };
    process.stdout.write(JSON.stringify(result, null, 2) + "\n");
    process.exit(1);
  }

  const ajv = createAjv();
  const schema = loadJSON(schemaPath);
  const validate = ajv.compile(schema);
  const valid = validate(data);

  if (valid) {
    process.stdout.write(JSON.stringify({ valid: true }, null, 2) + "\n");
    process.exit(0);
  }

  const errors = (validate.errors || []).map((e) => ({
    path: e.instancePath || "/",
    message: e.message || "unknown error",
    ...(e.params && Object.keys(e.params).length > 0 ? { expected: JSON.stringify(e.params) } : {}),
  }));

  const result = { valid: false, errors };
  process.stdout.write(JSON.stringify(result, null, 2) + "\n");

  // Write invalid data for debugging
  const invalidPath = resolvedDataPath + ".invalid.json";
  fs.writeFileSync(invalidPath, JSON.stringify(data, null, 2) + "\n", "utf-8");

  process.exit(1);
}

// --- Main ---

function main() {
  const args = process.argv.slice(2);

  if (args.length === 2) {
    validateData(args[0], args[1]);
  } else if (args.length === 0) {
    validateAllSchemas();
  } else {
    process.stderr.write(
      "Usage:\n  node validate-schemas.js                  # validate all schemas\n  node validate-schemas.js data.json schema  # validate data against schema\n"
    );
    process.exit(1);
  }
}

main();
