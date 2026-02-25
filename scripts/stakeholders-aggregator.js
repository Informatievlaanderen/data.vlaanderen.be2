#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const https = require("https");
const http = require("http");

// --- Configuration ---
const CONFIGDIR = process.argv[2] || "config";
const OUTPUT = process.argv[3] || "aggregated-stakeholders.csv";
const OUTPUT_JSON = process.argv[4] || "aggregated-stakeholders.json";

const configFile = path.join(CONFIGDIR, "config.json");
if (!fs.existsSync(configFile)) {
  console.error(`ERROR: config.json not found at ${configFile}`);
  process.exit(1);
}

const config = JSON.parse(fs.readFileSync(configFile, "utf8"));
const publicationPointsDirs = config.publicationpoints || [];

// Columns to drop from the output
const DROP_COLUMNS = new Set(["Website"]);

// Preferred column order after Thema (case-insensitive lookup)
const PREFERRED_ORDER = ["Voornaam", "Naam", "E-mail", "Affiliatie"];

// --- Helpers ---

/**
 * Download a file from a URL, following redirects.
 */
function downloadFile(url, maxRedirects = 5) {
  return new Promise((resolve, reject) => {
    if (maxRedirects <= 0) return reject(new Error("Too many redirects"));

    const client = url.startsWith("https") ? https : http;
    const headers = { "User-Agent": "merge-stakeholders-script" };
    if (process.env.GITHUB_TOKEN) {
      headers["Authorization"] = `token ${process.env.GITHUB_TOKEN}`;
    }
    client
      .get(url, { headers }, (res) => {
        if (
          res.statusCode >= 300 &&
          res.statusCode < 400 &&
          res.headers.location
        ) {
          return resolve(downloadFile(res.headers.location, maxRedirects - 1));
        }
        if (res.statusCode !== 200) {
          res.resume();
          return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
        }
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
        res.on("error", reject);
      })
      .on("error", reject);
  });
}

/**
 * Build the raw.githubusercontent.com URL for a file in a repo.
 */
function buildRawUrl(repository, branchtag, filepath) {
  const match = repository.match(/github\.com[/:]([^/]+)\/([^/.]+)/);
  if (!match) return null;
  const org = match[1];
  const repo = match[2];
  return `https://raw.githubusercontent.com/${org}/${repo}/${branchtag}/${filepath}`;
}

/**
 * Derive a clean thema name from a repository URL.
 * Strips the GitHub org prefix (e.g. "https://github.com/Informatievlaanderen/").
 */
function deriveThema(repository) {
  // Remove any trailing .git
  let cleaned = repository.replace(/\.git$/, "");
  // Strip GitHub URL prefix (any org)
  cleaned = cleaned.replace(/https?:\/\/github\.com\/[^/]+\//, "");
  // If still a URL or path, take last segment
  const repoMatch = cleaned.match(/\/([^/]+)$/);
  return repoMatch ? repoMatch[1] : cleaned;
}
/**
 * Parse a simple CSV string into an array of rows (each row = array of fields).
 * Handles quoted fields with embedded delimiters and newlines.
 */
function parseCSV(text, delimiter = ";") {
  const rows = [];
  let current = "";
  let inQuotes = false;
  const row = [];

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"') {
        if (i + 1 < text.length && text[i + 1] === '"') {
          current += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        current += ch;
      }
    } else {
      if (ch === '"') {
        inQuotes = true;
      } else if (ch === delimiter) {
        row.push(current);
        current = "";
      } else if (ch === "\n" || (ch === "\r" && text[i + 1] === "\n")) {
        if (ch === "\r") i++;
        row.push(current);
        current = "";
        if (row.length > 1 || row.some((f) => f.trim() !== "")) {
          rows.push([...row]);
        }
        row.length = 0;
      } else {
        current += ch;
      }
    }
  }
  // last row
  row.push(current);
  if (row.length > 1 || row.some((f) => f.trim() !== "")) {
    rows.push(row);
  }
  return rows;
}

/**
 * Escape a CSV field value.
 */
function escapeCSV(value, delimiter = ";") {
  if (value == null) return "";
  const str = String(value);
  if (str.includes(delimiter) || str.includes('"') || str.includes("\n")) {
    return '"' + str.replace(/"/g, '""') + '"';
  }
  return str;
}

// --- Main ---

async function main() {
  // 1. Collect all unique repository+branchtag combinations from publication files
  const repoMap = new Map();

  for (const dir of publicationPointsDirs) {
    const fullDir = path.join(CONFIGDIR, dir);
    if (!fs.existsSync(fullDir)) {
      console.warn(`WARN: directory ${fullDir} does not exist, skipping`);
      continue;
    }

    const files = fs
      .readdirSync(fullDir)
      .filter((f) => f.endsWith(".publication.json"));
    for (const file of files) {
      const filePath = path.join(fullDir, file);
      let pubPoints;
      try {
        pubPoints = JSON.parse(fs.readFileSync(filePath, "utf8"));
      } catch (e) {
        console.warn(`WARN: could not parse ${filePath}: ${e.message}`);
        continue;
      }

      if (!Array.isArray(pubPoints)) continue;

      for (const pp of pubPoints) {
        if (!pp.repository || !pp.branchtag) continue;
        if (pp.type === "raw") continue;
        if (pp.disabled) continue;

        const repo = pp.repository.trim();
        const key = `${repo}|${pp.branchtag}`;
        if (!repoMap.has(key)) {
          repoMap.set(key, {
            repository: repo,
            branchtag: pp.branchtag,
            thema: deriveThema(repo),
          });
        }
      }
    }
  }

  console.log(`Found ${repoMap.size} unique repository/branch combinations`);

  // 2. Download stakeholders.csv from each repo
  // Deduplicate: only download once per thema (pick the first occurrence)
  const themaMap = new Map();
  for (const [key, info] of repoMap) {
    if (!themaMap.has(info.thema)) {
      themaMap.set(info.thema, info);
    }
  }

  console.log(`Found ${themaMap.size} unique themas after deduplication`);

  const allHeaders = new Set();
  const allData = [];
  const themaHeader = "Thema";
  allHeaders.add(themaHeader);

  const stakeholderFiles = ["stakeholders.csv", "src/stakeholders.csv"];

  for (const [thema, info] of themaMap) {
    let csvText = null;
    for (const filepath of stakeholderFiles) {
      const url = buildRawUrl(info.repository, info.branchtag, filepath);
      if (!url) continue;
      try {
        console.log(`  Downloading ${url}`);
        csvText = await downloadFile(url);
        break;
      } catch (e) {
        // try next path
      }
    }

    if (!csvText) {
      console.warn(
        `  WARN: no stakeholders.csv found for ${info.thema} (${info.repository}@${info.branchtag})`,
      );
      continue;
    }

    const parsed = parseCSV(csvText, ";");
    if (parsed.length < 2) {
      console.warn(
        `  WARN: stakeholders.csv is empty or header-only for ${info.thema}`,
      );
      continue;
    }

    const headers = parsed[0].map((h) => h.trim());
    headers.forEach((h) => {
      if (!DROP_COLUMNS.has(h)) {
        allHeaders.add(h);
      }
    });

    const rows = parsed.slice(1);

    // Deduplicate rows within this thema based on a person key (Voornaam + Naam + E-mail)
    const seen = new Set();
    const uniqueRows = [];
    const voornaamIdx = headers.indexOf("Voornaam");
    const naamIdx = headers.indexOf("Naam");
    const emailIdx = headers.indexOf("E-mail");

    for (const row of rows) {
      const voornaam = (voornaamIdx >= 0 ? row[voornaamIdx] || "" : "")
        .trim()
        .toLowerCase();
      const naam = (naamIdx >= 0 ? row[naamIdx] || "" : "")
        .trim()
        .toLowerCase();
      const email = (emailIdx >= 0 ? row[emailIdx] || "" : "")
        .trim()
        .toLowerCase();
      const personKey = `${voornaam}|${naam}|${email}`;

      if (seen.has(personKey)) {
        continue;
      }
      seen.add(personKey);
      uniqueRows.push(row);
    }

    allData.push({ thema: info.thema, headers, rows: uniqueRows });
    console.log(`  OK: ${rows.length} stakeholder rows from ${info.thema}`);
  }

  // 3. Build merged CSV with a unified header
  //    Order: Thema, then preferred columns, then remaining sorted alphabetically
  const remainingHeaders = [...allHeaders]
    .filter(
      (h) =>
        h !== themaHeader &&
        !PREFERRED_ORDER.includes(h) &&
        !DROP_COLUMNS.has(h),
    )
    .sort();

  const preferredPresent = PREFERRED_ORDER.filter((h) => allHeaders.has(h));
  const finalHeaders = [themaHeader, ...preferredPresent, ...remainingHeaders];

  const outputRows = [];
  for (const entry of allData) {
    const headerIndexMap = {};
    entry.headers.forEach((h, i) => {
      headerIndexMap[h] = i;
    });

    for (const row of entry.rows) {
      const outputRow = finalHeaders.map((h) => {
        if (h === themaHeader) return entry.thema;
        const idx = headerIndexMap[h];
        return idx != null ? row[idx] || "" : "";
      });
      outputRows.push(outputRow);
    }
  }

  // Sort by thema, then by Naam (index 2), then Voornaam (index 1)
  outputRows.sort((a, b) => {
    const cmp = a[0].localeCompare(b[0]);
    if (cmp !== 0) return cmp;
    const cmp2 = (a[2] || "").localeCompare(b[2] || "");
    if (cmp2 !== 0) return cmp2;
    return (a[1] || "").localeCompare(b[1] || "");
  });

  // Write CSV
  const csvLines = [
    finalHeaders.map((h) => escapeCSV(h)).join(";"),
    ...outputRows.map((row) => row.map((v) => escapeCSV(v)).join(";")),
  ];
  fs.writeFileSync(OUTPUT, csvLines.join("\n"), "utf8");
  console.log(
    `\nMerged CSV written to ${OUTPUT} (${outputRows.length} rows, ${finalHeaders.length} columns)`,
  );

  // 4. Also produce a JSON grouped by thema
  const grouped = {};
  for (const entry of allData) {
    if (!grouped[entry.thema]) {
      grouped[entry.thema] = [];
    }
    for (const row of entry.rows) {
      const obj = {};
      entry.headers.forEach((h, i) => {
        if (!DROP_COLUMNS.has(h)) {
          obj[h] = row[i] || "";
        }
      });
      grouped[entry.thema].push(obj);
    }
  }
  fs.writeFileSync(OUTPUT_JSON, JSON.stringify(grouped, null, 2), "utf8");
  console.log(
    `Grouped JSON written to ${OUTPUT_JSON} (${Object.keys(grouped).length} themas)`,
  );
}

main().catch((err) => {
  console.error("FATAL:", err);
  process.exit(1);
});
