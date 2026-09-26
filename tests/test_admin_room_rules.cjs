'use strict';
// Production JS functions with DOM/API doubles: not a browser acceptance test.
const fs=require('fs'),vm=require('vm');
const source=fs.readFileSync('host/admin.html','utf8').match(/<script>([\s\S]*?)<\/script>/)[1];
new Function(source);
const names=['roomRuleFields','readRoomRules','roomRulesText','roomRecreate'];
const code=names.map(name=>source.split(/\r?\n/).find(l=>l.startsWith('function '+name+'('))).join('\n');
const manifest=JSON.parse(fs.readFileSync('examples/shooter/game_manifest.json','utf8'));
let job,sent,passed=0;
const context=vm.createContext({snapshot:{games:[manifest,{game_id:'racer',room_rules:{laps:{title:'圈数',minimum:1,maximum:50,default:3}}}]},reason:{name:'reason'},ask:v=>job=v,api:(action,payload)=>sent={action,payload}});
vm.runInContext(code,context);
function check(condition,label){if(!condition)throw new Error(label);passed++;console.log('PASS '+label);}
const fields=context.roomRuleFields(manifest);
check(fields.length===3,'three shooter fields generated from trusted metadata');
check(fields.find(f=>f.name==='rule_kill_limit').value===0,'zero kill target remains zero');
check(context.roomRuleFields({}).length===0,'unconfigured games do not acquire shooter options');
check(context.roomRuleFields({room_rules:{laps:{title:'圈数',minimum:1,maximum:50,default:3}}})[0].name==='rule_laps','other game can declare its own rule without UI changes');
check(context.readRoomRules({rule_kill_limit:'15',reason:'test'}).kill_limit===15,'form numbers convert to integer values');
check(!Object.hasOwn(context.readRoomRules({reason:'test'}),'reason'),'audit reason does not enter game rules');
context.roomRecreate({room_id:'r_test',game_id:'shooter',options:{rules:{duration_seconds:90,kill_limit:25,respawn_seconds:0}}});
check(job.fields.find(f=>f.name==='rule_duration_seconds').value===90,'recreate prefills saved duration');
check(job.fields.find(f=>f.name==='rule_respawn_seconds').value===0,'recreate preserves zero wait');
job.run({rule_duration_seconds:'60',rule_kill_limit:'10',rule_respawn_seconds:'2',reason:'test'});
check(sent.action==='room.recreate'&&sent.payload.room_id==='r_test'&&sent.payload.rules.kill_limit===10,'recreate sends scoped rules and room identity');
check(context.roomRulesText({game_id:'shooter',options:{rules:{kill_limit:10}}}).includes('10'),'room table displays configured target');
console.log('ADMIN_ROOM_RULES_RESULT passed='+passed+' failed=0');
