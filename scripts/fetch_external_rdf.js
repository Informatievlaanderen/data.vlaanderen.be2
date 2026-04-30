#!/usr/bin/env node

const fs = require('fs');
const { Writer } = require('n3');
const { rdfDereferencer } = require('rdf-dereference');

async function main() {
  const [, , sourceUrl, targetFile] = process.argv;

  if (!sourceUrl || !targetFile) {
    console.error('Usage: fetch_external_rdf.js <source-url> <target-file>');
    process.exit(1);
  }

  const { data, headers, url } = await rdfDereferencer.dereference(sourceUrl, {
    parseUnsupportedVersions: true,
  });

  const writer = new Writer({ format: 'N-Quads' });
  let quadCount = 0;

  await new Promise((resolve, reject) => {
    data.on('data', (quad) => {
      quadCount += 1;
      writer.addQuad(quad);
    });
    data.on('error', reject);
    data.on('end', resolve);
  });

  if (quadCount === 0) {
    throw new Error(`No RDF quads were dereferenced from ${sourceUrl}`);
  }

  const serialized = await new Promise((resolve, reject) => {
    writer.end((error, result) => {
      if (error) {
        reject(error);
      } else {
        resolve(result);
      }
    });
  });

  fs.writeFileSync(targetFile, serialized, 'utf8');

  const contentType = headers && typeof headers.get === 'function'
    ? headers.get('content-type')
    : 'unknown';

  console.log(`Fetched external source: ${url || sourceUrl} (${contentType || 'unknown'})`);
}

main().catch((error) => {
  console.error(error && error.message ? error.message : error);
  process.exit(1);
});