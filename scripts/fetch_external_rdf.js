#!/usr/bin/env node

const fs = require('fs');
const { rdfDereferencer } = require('rdf-dereference');

// Serialize a single RDFJS term to its N-Quads representation.
function serializeTerm(term) {
  if (term.termType === 'NamedNode') {
    return `<${term.value}>`;
  }
  if (term.termType === 'BlankNode') {
    return `_:${term.value}`;
  }
  if (term.termType === 'Literal') {
    const escaped = term.value.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n').replace(/\r/g, '\\r').replace(/\t/g, '\\t');
    if (term.language) {
      return `"${escaped}"@${term.language}`;
    }
    if (term.datatype && term.datatype.value !== 'http://www.w3.org/2001/XMLSchema#string') {
      return `"${escaped}"^^<${term.datatype.value}>`;
    }
    return `"${escaped}"`;
  }
  if (term.termType === 'DefaultGraph') {
    return '';
  }
  return `<${term.value}>`;
}

// Serialize a single RDFJS quad to an N-Quads line.
function serializeQuad(quad) {
  const { subject, predicate, object, graph } = quad;
  const graphPart = graph && graph.termType !== 'DefaultGraph' ? ` ${serializeTerm(graph)}` : '';
  return `${serializeTerm(subject)} ${serializeTerm(predicate)} ${serializeTerm(object)}${graphPart} .\n`;
}

async function main() {
  const [, , sourceUrl, targetFile] = process.argv;

  if (!sourceUrl || !targetFile) {
    console.error('Usage: fetch_external_rdf.js <source-url> <target-file>');
    process.exit(1);
  }

  const { data, headers, url } = await rdfDereferencer.dereference(sourceUrl, {
    parseUnsupportedVersions: true,
  });

  const lines = [];

  await new Promise((resolve, reject) => {
    data.on('data', (quad) => lines.push(serializeQuad(quad)));
    data.on('error', reject);
    data.on('end', resolve);
  });

  if (lines.length === 0) {
    throw new Error(`No RDF quads were dereferenced from ${sourceUrl}`);
  }

  fs.writeFileSync(targetFile, lines.join(''), 'utf8');

  const contentType = headers && typeof headers.get === 'function'
    ? headers.get('content-type')
    : 'unknown';

  console.log(`Fetched external source: ${url || sourceUrl} (${contentType || 'unknown'})`);
}

main().catch((error) => {
  console.error(error && error.message ? error.message : error);
  process.exit(1);
});