import fs from 'node:fs';
import path from 'node:path';
import {execFile} from 'node:child_process';
const root=path.resolve('../..'),cache=path.join(root,'Saved/audio-cache');
let delays:Record<string,number>={};try{delays=JSON.parse(fs.readFileSync(path.join(cache,'sound-delays.json'),'utf8'));}catch{}
let serial=0;const pending=new Map<string,Promise<string>>();let renderQueue:Promise<unknown>=Promise.resolve();
export function audioMessage(message:any){const name=message.constructor.name;
 if(name==='SynthSound')return {event:++serial,kind:'sound',id:message.synth,loops:message.loops,delay:(message.delay+(delays[message.synth]??0))/50};
 if(name==='MidiSong')return {event:++serial,kind:'music',id:message.id===65535?-1:message.id,loops:1,delay:0};
 if(name==='MidiJingle')return {event:++serial,kind:'jingle',id:message.id,loops:1,delay:0,resumeAfter:message.delay/1000};
 return null;
}
export function audioFile(kind:string,id:number,loops:number){
 if(!['sound','music'].includes(kind)||!Number.isInteger(id)||id<0||id>65535||!Number.isInteger(loops)||loops<1||loops>8)throw Error('Invalid audio request');
 const file=path.join(cache,`${kind}-${id}-${loops}.wav`);if(fs.existsSync(file))return Promise.resolve(file);if(pending.has(file))return pending.get(file)!;
 if(kind==='music'&&!fs.existsSync(path.join(cache,'source',`${id}.mid`))||kind==='sound'&&delays[id]===undefined)throw Error('Original audio unavailable');
 const task=renderQueue.catch(()=>{}).then(()=>new Promise<string>((resolve,reject)=>execFile(process.execPath,[path.join(root,'tools/render-native-audio.mjs'),kind,String(id),String(loops)],{timeout:60000,maxBuffer:100000},err=>err?reject(Error('Audio rendering failed')):resolve(file))));
 renderQueue=task;pending.set(file,task);void task.finally(()=>pending.delete(file)).catch(()=>{});return task;
}
