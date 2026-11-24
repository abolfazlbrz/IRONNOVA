import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const root = process.cwd();
const javaRoot = join(root, 'android', 'app', 'src', 'main', 'java');
function findMain(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      const found = findMain(full);
      if (found) return found;
    } else if (entry.name === 'MainActivity.java') return full;
  }
  return null;
}
if (!existsSync(javaRoot)) throw new Error('Android Java source directory was not generated.');
const mainPath = findMain(javaRoot);
if (!mainPath) throw new Error('Capacitor MainActivity.java was not found.');
let main = readFileSync(mainPath, 'utf8');
const packageName = main.match(/^package\s+([\w.]+);/m)?.[1];
if (!packageName) throw new Error('Cannot determine Android package name.');
const pluginPath = join(javaRoot, ...packageName.split('.'), 'NativeAudioPlugin.java');
mkdirSync(dirname(pluginPath), { recursive: true });
const pluginSource = readFileSync(join(root, 'android-native', 'NativeAudioPlugin.java'), 'utf8')
  .replace(/^package\s+[\w.]+;/m, 'package ' + packageName + ';');
writeFileSync(pluginPath, pluginSource, 'utf8');
if (!main.includes('registerPlugin(NativeAudioPlugin.class)')) {
  if (!main.includes('import android.os.Bundle;')) main = main.replace(/(package\s+[\w.]+;)/, '$1\n\nimport android.os.Bundle;');
  if (!main.includes('import ' + packageName + '.NativeAudioPlugin;')) {
    main = main.replace(/(import com\.getcapacitor\.BridgeActivity;)/, '$1\nimport ' + packageName + '.NativeAudioPlugin;');
  }
  main = main.replace(/public class MainActivity extends BridgeActivity\s*\{\s*\}/,
    'public class MainActivity extends BridgeActivity {\n    @Override\n    public void onCreate(Bundle savedInstanceState) {\n        registerPlugin(NativeAudioPlugin.class);\n        super.onCreate(savedInstanceState);\n    }\n}');
  if (!main.includes('registerPlugin(NativeAudioPlugin.class)')) throw new Error('Could not register NativeAudioPlugin in MainActivity.');
  writeFileSync(mainPath, main, 'utf8');
}
console.log('Registered NativeAudioPlugin in ' + mainPath);
