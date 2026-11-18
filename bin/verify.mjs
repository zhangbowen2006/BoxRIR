import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';

const manifestName = 'run-manifest.json';
const incompleteMarker = '.boxrir-incomplete';

function rejectMarker(directory) {
  try {
    fs.lstatSync(path.join(directory, incompleteMarker));
  } catch (error) {
    if (error.code === 'ENOENT') return;
    throw error;
  }
  throw new Error('Bundle is marked incomplete');
}

function readManifest(directory) {
  const file = path.join(directory, manifestName);
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.size > 65536) throw new Error('Invalid run manifest file');
  const manifest = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!manifest || manifest.schema_version !== 1 || manifest.state !== 'complete' ||
      !manifest.files || typeof manifest.files !== 'object' || Array.isArray(manifest.files)) {
    throw new Error('Expected a completed BoxRIR run manifest');
  }
  const entries = Object.entries(manifest.files);
  if (entries.length === 0 || entries.length > 32) throw new Error('Invalid manifest file count');
  for (const [name, expected] of entries) {
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/.test(name) ||
        !/[A-Za-z0-9]$/.test(name) || name.toLowerCase() === manifestName ||
        !expected || !Number.isSafeInteger(expected.bytes) || expected.bytes < 0 ||
        !/^[0-9a-f]{64}$/.test(expected.sha256)) {
      throw new Error('Invalid run manifest file entry');
    }
  }
  if (new Set(entries.map(([name]) => name.toLowerCase())).size !== entries.length) {
    throw new Error('Duplicate portable names in the run manifest');
  }
  return {manifest, entries};
}

async function checkFile(directory, name, expected) {
  const file = path.join(directory, name);
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.size !== expected.bytes) {
    throw new Error('Bundle file type or length differs: ' + name);
  }
  const hash = createHash('sha256');
  let bytes = 0;
  for await (const chunk of fs.createReadStream(file)) {
    bytes += chunk.length;
    if (bytes > expected.bytes) throw new Error('Bundle file grew during verification: ' + name);
    hash.update(chunk);
  }
  if (bytes !== expected.bytes || hash.digest('hex') !== expected.sha256) {
    throw new Error('Bundle file checksum differs: ' + name);
  }
  return bytes;
}

export async function verifyBundle(location) {
  const directory = path.resolve(location);
  if (!fs.lstatSync(directory).isDirectory()) throw new Error('Expected a BoxRIR output directory');
  rejectMarker(directory);
  const {manifest, entries} = readManifest(directory);
  let bytes = 0;
  for (const [name, expected] of entries) {
    bytes += await checkFile(directory, name, expected);
  }
  rejectMarker(directory);
  return {
    directory,
    files_verified: entries.length,
    bytes_verified: bytes,
    recorded_version: manifest.version ?? null,
    recorded_backend: manifest.backend ?? null,
    recorded_engine_sha256: manifest.engine_sha256 ?? null,
  };
}
