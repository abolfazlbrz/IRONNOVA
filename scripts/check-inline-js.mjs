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
  'iron_place_order_v3',
  'iron_submit_order_receipt_v2',
  'iron_store_order_sellers_v2',
  'iron_store_discounts_v2',
  'iron_store_notifications_v2',
  'iron_admin_review_store_product_v2',
  'iron_seller_update_order_v2',
  'iron_store_send_message_v2',
  'shopChatPanel',
  'openStoreChat',
  'issueCoachVerificationCode',
  'iron_admin_issue_coach_code_v2',
  'iron_verify_coach_code_v2',
  'runStopwatch',
  'IRONNOVA_REFERENCE_PLAN',
  'workoutProgramsPage',
  'weightloss',
  'bodybuilding',
  'weightgain',
  'budget',
  'NativeAudio',
  'applyReferencePlan',
  'saveCurrentProgram',
  'validateSmartPlanLimits',
  'correctiveArt',
  'referenceLocked',
  'intro-orbit',
  'intro-shockwave',
  'resetCoachForVerification',
  'pickNativeMusic',
  'nativeMusicPanel',
  'iron_store_send_message_v2',
  'setWeights',
  'icContentVisibility',
  'iron_coach_group_messages_v2',
  'iron_create_group_v2',
  'ironFoods',
  'ironIntro',
  'intro-arm',
  'anatomy-panel',
  'anatomy-svg',
  'filterAnatomyMuscle',
  'coachSectionExplore',
  'coachSectionAccount',
  'coachSectionPlans',
  'loadCoachDirectory',
  'requestCoachConnection',
  'iron_admin_coaches_overview_v2',
  'introBurst',
  'icCoachExperience',
  'muscle-hit.is-selected'
];
for (const token of required) {
  if (!html.includes(token)) throw new Error('Missing expected IRONNOVA feature marker: ' + token);
}
console.log('Validated ' + scripts.length + ' inline JavaScript block(s) and ' + required.length + ' feature markers.');
