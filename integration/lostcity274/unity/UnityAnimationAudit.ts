import fs from 'node:fs';
import SeqType from '#/cache/config/SeqType.js';
import ObjType from '#/cache/config/ObjType.js';
import {sequence} from './UnityAnimation.js';
SeqType.load('data/pack');ObjType.load('data/pack');
const report={sequenceNames:{} as Record<number,string>,sequences:0,heldSequences:0,heldModels:0,emptyOriginalWearModels:[] as string[],failures:[] as string[]};
for(let id=0;id<SeqType.count;id++){
 const seq=sequence(id);report.sequences++;report.sequenceNames[id]=SeqType.get(id).debugname??String(id);
 if(seq.replaceheldleft>=0||seq.replaceheldright>=0)report.heldSequences++;
 for(const [name,value,part] of [['leftMale',seq.replaceheldleft,seq.leftMale],['leftFemale',seq.replaceheldleft,seq.leftFemale],['rightMale',seq.replaceheldright,seq.rightMale],['rightFemale',seq.replaceheldright,seq.rightFemale]] as const){
  if(value>=512&&!part?.models.length)report.emptyOriginalWearModels.push(`${id}:${name}: original item ${value-512} defines no wear models`);
  for(const model of part?.models??[]){report.heldModels++;if(!fs.existsSync(`../../Unity/Assets/LostCity274/models/${model}.ob2`))report.failures.push(`${id}:${name}: model ${model} unavailable`);}
 }
}
fs.writeFileSync('../../Saved/animation-cache-audit.json',JSON.stringify(report,null,2));console.log(JSON.stringify({...report,sequenceNames:undefined}));if(report.failures.length)process.exitCode=1;
