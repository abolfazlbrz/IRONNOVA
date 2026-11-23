import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync('index.html', 'utf8');
const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)]
  .map(match => match[1])
  .filter(source => source.trim().length > 0);

if (scripts.length === 0) throw new Error('No inline JavaScript found in index.html');
for (let i = 0; i < scripts.length; i += 1) {
  new vm.Script(scripts[i], { filename: 'index.html:inline-script-' + (i + 1) });
}

const required = [
  'educationPage',
  'iron_messages_v2',
  'iron_store_orders_v2',
  'iron_place_order_v2',
  'iron_submit_order_receipt_v2',
  'iron_coach_group_messages_v2',
  'iron_create_group_v2',
  'ironFoods'
];
for (const token of required) {
  if (!html.includes(token)) throw new Error('Missing expected IRONNOVA feature marker: ' + token);
}
console.log('Validated ' + scripts.length + ' inline JavaScript block(s) and ' + required.length + ' feature markers.');
