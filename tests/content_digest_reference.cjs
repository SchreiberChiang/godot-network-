// Independent reference for tools/content_digest.ps1 (roomkit-content-digest-v2).
// Deliberately written from the rules, not translated from the PowerShell, so a
// disagreement between the two exposes a platform or implementation assumption.
// Usage: node tests/content_digest_reference.cjs <root>   -> prints the digest
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const TEXT = new Set(['.gd', '.json', '.godot', '.tscn', '.tres', '.cfg', '.md', '.txt', '.gdshader', '.csv', '.svg']);

function walk(root, relative, out) {
  for (const entry of fs.readdirSync(path.join(root, relative), { withFileTypes: true })) {
    const child = relative ? relative + '/' + entry.name : entry.name;
    if (entry.isDirectory()) {
      if (entry.name !== '.godot') walk(root, child, out);
    } else if (entry.isFile()) {
      if (child !== 'game_manifest.json' && child !== 'game/game_manifest.json') out.push(child);
    }
  }
}

function fileHash(root, relative) {
  let bytes = fs.readFileSync(path.join(root, relative));
  const dot = relative.lastIndexOf('.');
  const slash = relative.lastIndexOf('/');
  const extension = dot > slash ? relative.slice(dot).toLowerCase() : '';
  if (TEXT.has(extension) && !bytes.includes(0)) {
    const kept = [];
    for (let i = 0; i < bytes.length; i++) {
      if (bytes[i] === 13 && bytes[i + 1] === 10) continue;
      kept.push(bytes[i]);
    }
    bytes = Buffer.from(kept);
  }
  return crypto.createHash('sha256').update(bytes).digest('hex').toUpperCase();
}

function digest(root) {
  const files = [];
  walk(root, '', files);
  const lines = files.map(file => file + '=' + fileHash(root, file));
  // Default JS string comparison is by UTF-16 code unit, the same as .NET ordinal.
  lines.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  const text = ['roomkit-content-digest-v2', ...lines].join('\n');
  return crypto.createHash('sha256').update(Buffer.from(text, 'utf8')).digest('hex').slice(0, 12);
}

if (require.main === module) {
  process.stdout.write(digest(path.resolve(process.argv[2])) + '\n');
}
module.exports = { digest };
