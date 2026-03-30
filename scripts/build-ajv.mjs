import { build } from 'esbuild';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

await build({
  entryPoints: [join(__dirname, 'ajv-entry.mjs')],
  bundle: true,
  platform: 'node',
  format: 'cjs',
  outfile: join(__dirname, 'ajv-bundle.js'),
  minify: false,
  banner: {
    js: '// Auto-generated AJV bundle — do not edit directly\n// Regenerate: npm run build:ajv\n'
  }
});

console.log('AJV bundle built: scripts/ajv-bundle.js');
